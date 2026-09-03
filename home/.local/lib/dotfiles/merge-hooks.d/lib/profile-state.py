#!/usr/bin/env python3
"""Reverse one owned structured-config generation without losing user edits."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import tempfile
from typing import Any


class Conflict(Exception):
    """The current document changed an owned semantic unit."""


MISSING = object()


def _empty_document_like(document: Any) -> dict[str, Any] | list[Any]:
    """Return an empty document preserving the parsed top-level shape."""
    if isinstance(document, list):
        return []
    if isinstance(document, dict):
        return {}
    raise ValueError("profile-state document must be an object or array")


def _identity(policy: str, path: tuple[str, ...], value: Any) -> str | None:
    """Return the stable identity used by an explicitly mergeable array."""
    if policy in {"claude", "muse"}:
        if path in {
            ("permissions", "allow"),
            ("permissions", "additionalDirectories"),
        } and isinstance(value, str):
            return value
    if policy in {"claude", "muse", "gemini", "codex"}:
        if len(path) == 2 and path[0] == "hooks" and isinstance(value, dict):
            commands = [
                hook.get("command") for hook in value.get("hooks", []) if isinstance(hook, dict)
            ]
            return json.dumps(
                [value.get("matcher"), commands],
                sort_keys=True,
                separators=(",", ":"),
            )
    if (
        policy == "vscode-settings"
        and path == ("terminal.integrated.commandsToSkipShell",)
        and isinstance(value, str)
    ):
        return value.removeprefix("-")
    if policy == "vscode-keybindings" and not path and isinstance(value, dict):
        key = value.get("key")
        when = value.get("when", "")
        if isinstance(key, str) and isinstance(when, str):
            return json.dumps([key, when], separators=(",", ":"))
    if policy == "vscode-extensions" and not path and isinstance(value, dict):
        identifier = value.get("identifier")
        if isinstance(identifier, dict):
            extension_id = identifier.get("id")
            if isinstance(extension_id, str) and extension_id:
                return extension_id
    return None


def _indexed(policy: str, path: tuple[str, ...], values: list[Any]) -> dict[str, Any] | None:
    """Index a mergeable array, rejecting ambiguous identities."""
    indexed: dict[str, Any] = {}
    for value in values:
        identity = _identity(policy, path, value)
        if identity is None or identity in indexed:
            return None
        indexed[identity] = value
    return indexed


def _reverse_list(
    policy: str,
    path: tuple[str, ...],
    before: list[Any],
    applied: list[Any],
    current: list[Any],
) -> list[Any]:
    """Reverse an owned list delta when this path has a stable identity."""
    before_index = _indexed(policy, path, before)
    applied_index = _indexed(policy, path, applied)
    current_index: dict[str, list[Any]] = {}
    for value in current:
        identity = _identity(policy, path, value)
        if identity is None:
            current_index = {}
            break
        current_index.setdefault(identity, []).append(value)
    if before_index is None or applied_index is None or not current_index and current:
        if current == applied or current == before:
            return before
        raise Conflict(f"owned array changed at {'.'.join(path) or '<root>'}")

    result = list(current)
    for identity in set(before_index) | set(applied_index):
        old = before_index.get(identity, MISSING)
        managed = applied_index.get(identity, MISSING)
        live_values = current_index.get(identity, [])
        if old == managed:
            continue
        if old is MISSING:
            if not live_values:
                continue
            if all(value == managed for value in live_values):
                result = [value for value in result if _identity(policy, path, value) != identity]
                continue
            raise Conflict(f"owned array entry changed at {'.'.join(path) or '<root>'}")
        if managed is MISSING:
            if not live_values:
                insert_at = min(before.index(old), len(result))
                result.insert(insert_at, old)
                continue
            if all(value == old for value in live_values):
                if len(live_values) > 1:
                    kept = False
                    deduplicated = []
                    for value in result:
                        if _identity(policy, path, value) != identity:
                            deduplicated.append(value)
                        elif not kept:
                            deduplicated.append(value)
                            kept = True
                    result = deduplicated
                continue
            raise Conflict(f"owned array entry changed at {'.'.join(path) or '<root>'}")
        if live_values and all(value == managed for value in live_values):
            result = [value for value in result if _identity(policy, path, value) != identity]
            if old is not MISSING:
                insert_at = min(before.index(old), len(result))
                result.insert(insert_at, old)
            continue
        if live_values and old is not MISSING and all(value == old for value in live_values):
            if len(live_values) > 1:
                kept = False
                deduplicated = []
                for value in result:
                    if _identity(policy, path, value) != identity:
                        deduplicated.append(value)
                    elif not kept:
                        deduplicated.append(value)
                        kept = True
                result = deduplicated
            continue
        raise Conflict(f"owned array entry changed at {'.'.join(path) or '<root>'}")
    return result


def reverse(
    policy: str,
    before: Any,
    applied: Any,
    current: Any,
    path: tuple[str, ...] = (),
) -> Any:
    """Reverse the semantic delta from before to applied out of current."""
    if before == applied:
        return current
    if current == applied or current == before:
        return before

    before_object = {} if before is MISSING else before
    applied_object = {} if applied is MISSING else applied
    current_object = {} if current is MISSING else current
    if all(isinstance(value, dict) for value in (before_object, applied_object, current_object)):
        result: dict[str, Any] = {}
        keys = set(before_object) | set(applied_object) | set(current_object)
        for key in keys:
            value = reverse(
                policy,
                before_object.get(key, MISSING),
                applied_object.get(key, MISSING),
                current_object.get(key, MISSING),
                (*path, key),
            )
            if value is not MISSING:
                result[key] = value
        if before is MISSING and not result:
            return MISSING
        return result

    before_list = [] if before is MISSING else before
    applied_list = [] if applied is MISSING else applied
    current_list = [] if current is MISSING else current
    if all(isinstance(value, list) for value in (before_list, applied_list, current_list)):
        result = _reverse_list(policy, path, before_list, applied_list, current_list)
        if before is MISSING and not result:
            return MISSING
        return result

    raise Conflict(f"owned value changed at {'.'.join(path) or '<root>'}")


def _capture_list(
    policy: str,
    path: tuple[str, ...],
    before: list[Any],
    applied: list[Any],
    current: list[Any],
) -> list[Any]:
    """Recover the baseline while treating divergent identities as user edits."""
    before_index = _indexed(policy, path, before)
    applied_index = _indexed(policy, path, applied)
    current_index = _indexed(policy, path, current)
    if before_index is None or applied_index is None or current_index is None:
        return before if current == applied else current

    result = list(current)
    for identity in set(before_index) | set(applied_index):
        old = before_index.get(identity, MISSING)
        managed = applied_index.get(identity, MISSING)
        live = current_index.get(identity, MISSING)
        if old == managed:
            continue
        if live == managed:
            result = [value for value in result if _identity(policy, path, value) != identity]
            if old is not MISSING:
                result.insert(min(before.index(old), len(result)), old)
    return result


def capture(
    policy: str,
    before: Any,
    applied: Any,
    current: Any,
    path: tuple[str, ...] = (),
) -> Any:
    """Recover a baseline before refresh, retaining divergent user edits."""
    if before == applied:
        return current
    if current == applied or current == before:
        return before

    before_object = {} if before is MISSING else before
    applied_object = {} if applied is MISSING else applied
    current_object = {} if current is MISSING else current
    if all(isinstance(value, dict) for value in (before_object, applied_object, current_object)):
        result: dict[str, Any] = {}
        keys = set(before_object) | set(applied_object) | set(current_object)
        for key in keys:
            value = capture(
                policy,
                before_object.get(key, MISSING),
                applied_object.get(key, MISSING),
                current_object.get(key, MISSING),
                (*path, key),
            )
            if value is not MISSING:
                result[key] = value
        if before is MISSING and not result:
            return MISSING
        return result

    before_list = [] if before is MISSING else before
    applied_list = [] if applied is MISSING else applied
    current_list = [] if current is MISSING else current
    if all(isinstance(value, list) for value in (before_list, applied_list, current_list)):
        result = _capture_list(policy, path, before_list, applied_list, current_list)
        if before is MISSING and not result:
            return MISSING
        return result

    return current


def adopt(
    policy: str,
    managed: Any,
    current: Any,
    path: tuple[str, ...] = (),
) -> Any:
    """Infer a pre-receipt baseline by removing exact managed values."""
    if current == managed:
        return MISSING
    if isinstance(managed, dict) and isinstance(current, dict):
        result = dict(current)
        for key, managed_value in managed.items():
            if key not in current:
                continue
            value = adopt(policy, managed_value, current[key], (*path, key))
            if value is MISSING:
                result.pop(key, None)
            else:
                result[key] = value
        return result
    if isinstance(managed, list) and isinstance(current, list):
        managed_index = _indexed(policy, path, managed)
        current_index = _indexed(policy, path, current)
        if managed_index is None or current_index is None:
            return current
        return [
            value
            for value in current
            if not (
                (identity := _identity(policy, path, value)) in managed_index
                and managed_index[identity] == value
            )
        ]
    return current


def _read(path: pathlib.Path) -> Any:
    with path.open(encoding="utf-8") as source:
        return json.load(source)


def _write(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = pathlib.Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(value, output, indent=2, sort_keys=True)
            output.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def publish_in_place(source: pathlib.Path, destination: pathlib.Path) -> None:
    """Replace a file through a verified handle, restoring it on failure."""
    expected = source.read_bytes()
    try:
        original = destination.read_bytes()
        existed = True
    except FileNotFoundError:
        original = b""
        existed = False

    def write_bytes(data: bytes) -> None:
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT, 0o600)
        try:
            view = memoryview(data)
            written = 0
            while written < len(view):
                written += os.write(descriptor, view[written:])
            os.ftruncate(descriptor, len(data))
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

    try:
        write_bytes(expected)
        if destination.read_bytes() != expected:
            raise OSError("destination did not match expected bytes after write")
    except BaseException:
        try:
            if existed:
                write_bytes(original)
            else:
                destination.unlink(missing_ok=True)
        except BaseException:
            pass
        raise


def files_equal(left: pathlib.Path, right: pathlib.Path) -> bool:
    """Compare file bytes without relying on a platform-specific utility."""
    return left.read_bytes() == right.read_bytes()


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    reverse_parser = subparsers.add_parser("reverse")
    reverse_parser.add_argument("--policy", required=True)
    reverse_parser.add_argument("--before", required=True, type=pathlib.Path)
    reverse_parser.add_argument("--applied", required=True, type=pathlib.Path)
    reverse_parser.add_argument("--current", required=True, type=pathlib.Path)
    reverse_parser.add_argument("--output", required=True, type=pathlib.Path)
    adopt_parser = subparsers.add_parser("adopt")
    adopt_parser.add_argument("--policy", required=True)
    adopt_parser.add_argument("--managed", required=True, type=pathlib.Path)
    adopt_parser.add_argument("--current", required=True, type=pathlib.Path)
    adopt_parser.add_argument("--output", required=True, type=pathlib.Path)
    capture_parser = subparsers.add_parser("capture")
    capture_parser.add_argument("--policy", required=True)
    capture_parser.add_argument("--before", required=True, type=pathlib.Path)
    capture_parser.add_argument("--applied", required=True, type=pathlib.Path)
    capture_parser.add_argument("--current", required=True, type=pathlib.Path)
    capture_parser.add_argument("--output", required=True, type=pathlib.Path)
    publish_parser = subparsers.add_parser("publish-in-place")
    publish_parser.add_argument("--source", required=True, type=pathlib.Path)
    publish_parser.add_argument("--destination", required=True, type=pathlib.Path)
    equal_parser = subparsers.add_parser("equal")
    equal_parser.add_argument("--left", required=True, type=pathlib.Path)
    equal_parser.add_argument("--right", required=True, type=pathlib.Path)
    arguments = parser.parse_args()

    if arguments.command == "reverse":
        try:
            current = _read(arguments.current)
            result = reverse(
                arguments.policy,
                _read(arguments.before),
                _read(arguments.applied),
                current,
            )
            if result is MISSING:
                result = _empty_document_like(current)
        except (Conflict, json.JSONDecodeError, OSError, ValueError) as error:
            print(f"profile-state: {error}", file=os.sys.stderr)
            return 1
        _write(arguments.output, result)
        return 0
    if arguments.command == "adopt":
        try:
            current = _read(arguments.current)
            result = adopt(
                arguments.policy,
                _read(arguments.managed),
                current,
            )
            if result is MISSING:
                result = _empty_document_like(current)
        except (json.JSONDecodeError, OSError, ValueError) as error:
            print(f"profile-state: {error}", file=os.sys.stderr)
            return 1
        _write(arguments.output, result)
        return 0
    if arguments.command == "capture":
        try:
            current = _read(arguments.current)
            result = capture(
                arguments.policy,
                _read(arguments.before),
                _read(arguments.applied),
                current,
            )
            if result is MISSING:
                result = _empty_document_like(current)
        except (json.JSONDecodeError, OSError, ValueError) as error:
            print(f"profile-state: {error}", file=os.sys.stderr)
            return 1
        _write(arguments.output, result)
        return 0
    if arguments.command == "publish-in-place":
        try:
            publish_in_place(arguments.source, arguments.destination)
        except OSError as error:
            print(f"profile-state: {error}", file=os.sys.stderr)
            return 1
        return 0
    if arguments.command == "equal":
        try:
            return 0 if files_equal(arguments.left, arguments.right) else 1
        except OSError as error:
            print(f"profile-state: {error}", file=os.sys.stderr)
            return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
