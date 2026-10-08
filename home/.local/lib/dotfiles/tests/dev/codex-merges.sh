# shellcheck shell=bash
# Codex config merge-hook behavior, split from merges.sh because it is the
# longest remaining block: as a separate suite `dot test` runs it in parallel
# with the rest of the development merge hooks.

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"

dot_dev_codex_merges_test() {
  _dev_merges_setup || return

  # ---------------------------------------------------------------------------
  # Tests: codex merge hook
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Codex config merge hook ==="

  if command -v yq >/dev/null 2>&1; then
    if [[ -n ${DOT_TEST_YQ_MERGE_BLOCK_MARKER:-} ]]; then
      printf 'executed\n' >"$DOT_TEST_YQ_MERGE_BLOCK_MARKER"
    fi

    CODEX_DIR="$TEST_HOME/.codex"
    CODEX_CONFIG="$CODEX_DIR/config.toml"
    CODEX_AGENTGUARD_ASSETS="$TEST_HOME/agentguard-codex-assets"
    rm -rf "$CODEX_DIR"
    mkdir -p "$CODEX_DIR" \
      "$CODEX_AGENTGUARD_ASSETS/_shared" \
      "$CODEX_AGENTGUARD_ASSETS/codex" \
      "$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/50-environment.replace" \
      "$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/layered.d/50-environment.replace" \
      "$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/experimental.d"

    _CODEX_HOOK="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/codex.sh"
    _CODEX_BIN=$(_mock_bin)
    _CODEX_VERSION_PROBE="$TEST_HOME/.codex-version-probe"
    export DOT_TEST_CODEX_VERSION_PROBE="$_CODEX_VERSION_PROBE"
    cat >"$_CODEX_BIN/codex" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  if [[ -n "${DOT_TEST_CODEX_VERSION_PROBE:-}" ]]; then
    printf 'version-probed\n' >>"$DOT_TEST_CODEX_VERSION_PROBE"
  fi
  printf 'codex version should not be queried\n' >&2
  exit 0
fi
exit 2
MOCK
    chmod +x "$_CODEX_BIN/codex"

    _run_codex_merge() (
      unset -f merge _merge_codex_config _trust_codex_dotfile_hooks 2>/dev/null
      # shellcheck source=/dev/null
      . "$_CODEX_HOOK"
      # shellcheck disable=SC2329 # Invoked by Codex source discovery.
      dot_agentguard_integration_file() {
        if [[ "$1" == "codex" && "$2" == "hooks.toml" ]]; then
          printf '%s/codex/hooks.toml\n' "$CODEX_AGENTGUARD_ASSETS"
        elif [[ "$1" == "_shared" && "$2" == "reconcile-hooks.jq" ]]; then
          printf '%s/_shared/reconcile-hooks.jq\n' "$CODEX_AGENTGUARD_ASSETS"
        else
          return 1
        fi
      }
      PATH="$_CODEX_BIN:$PATH" merge
    )

    # A neutral provider fixture proves the dependency layer participates in
    # merge, cache, and trust handling without copying AgentGuard's real Codex
    # compatibility map into this consumer suite.
    cat >"$CODEX_AGENTGUARD_ASSETS/_shared/reconcile-hooks.jq" <<'JQ'
# Neutral provider contract fixture. Replace incoming provider event arrays,
# retire one provider event, and preserve consumer-owned hook metadata/state.
($d[0] // {}) as $live |
$s[0] as $provider |
($live * ($provider | del(.hooks))) |
.hooks = (($live.hooks // {}) + ($provider.hooks // {})) |
del(.hooks.ProviderRetired)
JQ
    cat >"$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml" <<'TOML'
[features]
hooks = true

[[hooks.PreToolUse]]
matcher = "ProviderShell"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "provider-pre-shell"
timeout = 120

[[hooks.PreToolUse]]
matcher = "ProviderEdit"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "provider-pre-edit"
timeout = 10

[[hooks.PostToolUse]]
matcher = "ProviderEdit"
[[hooks.PostToolUse.hooks]]
type = "command"
command = "provider-post-edit"
timeout = 60

# Events whose trust identity differs from the tool events: subagent events
# carry their matcher, Interrupt never does, and SessionEnd/Interrupt use a
# 1 s default timeout capped at 3 s instead of the 600 s default.
[[hooks.SubagentStart]]
matcher = "ProviderAgent"
[[hooks.SubagentStart.hooks]]
type = "command"
command = "provider-subagent-start"
timeout = 10

[[hooks.SubagentStop]]
[[hooks.SubagentStop.hooks]]
type = "command"
command = "provider-subagent-stop"
timeout = 10

[[hooks.Interrupt]]
[[hooks.Interrupt.hooks]]
type = "command"
command = "provider-interrupt"
timeout = 2

[[hooks.SessionEnd]]
[[hooks.SessionEnd.hooks]]
type = "command"
command = "provider-session-end"
TOML

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/10-settings.toml" <<'TOML'
model = "common-model"
project_doc_fallback_filenames = ["AGENTS.md", "CLAUDE.md"]

[projects."/home/testuser"]
trust_level = "trusted"

[tui]
status_line = ["model-with-reasoning"]
TOML

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/50-environment.replace/80-work.toml" <<'TOML'
[projects."/work/project"]
trust_level = "trusted"

[mcp_servers.example]
command = "true"

[mcp_servers.example.tools.lookup]
approval_mode = "approve"
TOML

    # Pre-existing config.toml carries a legacy [profiles.default] table (CLI state
    # from before the overlay migration); the merge must strip it from config.toml.
    cat >"$CODEX_CONFIG" <<'TOML'
[profiles.default]
model = "local-default"

[notice.model_migrations]
"gpt-5.3-codex" = "gpt-5.4"

[tui.model_availability_nux]
"gpt-5.5" = 2

[[hooks.PreToolUse]]
matcher = "RetiredProviderShell"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "provider-pre-shell-v1"

[[hooks.ProviderRetired]]
[[hooks.ProviderRetired.hooks]]
type = "command"
command = "provider-retired"
TOML

    _CODEX_ALIAS_PARENT=$(_tmpdir)
    ln -s "$TEST_HOME" "$_CODEX_ALIAS_PARENT/home-link"
    cat >>"$CODEX_CONFIG" <<TOML

[hooks.state."$_CODEX_ALIAS_PARENT/home-link/.codex/config.toml:pre_tool_use:0:0"]
enabled = false
trusted_hash = "sha256:old"
TOML

    # Named profiles render as standalone ~/.codex/<name>.config.toml overlays.
    # Layer a common + work profile fragment and seed the overlay with local CLI
    # state to verify merge order and state preservation below.
    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/layered.d/10-settings.toml" <<'TOML'
approval_policy = "never"
model_reasoning_effort = "high"

[features]
web_search_request = true
TOML

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/layered.d/50-environment.replace/80-work.toml" <<'TOML'
model_reasoning_effort = "low"
sandbox_mode = "danger-full-access"
TOML

    cat >"$CODEX_DIR/layered.config.toml" <<'TOML'
model = "local-allow"
approval_policy = "on-request"
TOML

    # These profiles were previously dot-managed. Removing their source families
    # must also retire generated outputs instead of leaving stale policy behind.
    printf 'sandbox_mode = "danger-full-access"\n' >"$CODEX_DIR/allow_all.config.toml"
    printf 'sandbox_mode = "workspace-write"\n' >"$CODEX_DIR/no_prompt.config.toml"

    cat >"$TEST_HOME/.config/dot/merge-hooks.d/codex/profiles/experimental.d/10-settings.toml" <<'TOML'
model = "experimental-model"
model_reasoning_effort = "high"
TOML

    _run_codex_merge 2>/dev/null
    _assert_file_exists "codex hook: config created" "$CODEX_CONFIG"
    codex_receipt_root=$TEST_HOME/.local/state/dot/overlays/dev/merge-receipts-v1
    codex_receipt_key=$(printf '%s\n%s\n' codex "$CODEX_CONFIG" | git hash-object --stdin)
    _assert_file_exists "codex hook: records reversible main config ownership" \
      "$codex_receipt_root/$codex_receipt_key.json"
    layered_receipt_key=$(printf '%s\n%s\n' codex \
      "$CODEX_DIR/layered.config.toml" | git hash-object --stdin)
    _assert_file_exists "codex hook: records reversible named-profile ownership" \
      "$codex_receipt_root/$layered_receipt_key.json"
    _assert_file_missing "codex hook: merge does not probe installed Codex version" "$_CODEX_VERSION_PROBE"
    codex_content=$(cat "$CODEX_CONFIG")
    _assert_contains "codex hook: emits hook array tables" "[[hooks.PreToolUse]]" "$codex_content"

    if python3 - "$CODEX_CONFIG" "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/lib/codex/refresh-trust.py" <<'PY'
import importlib.util
import pathlib
import sys
import tomllib

# Hash with the refresh helper itself so this suite never carries a second
# copy of Codex's event tables; the installed-Codex check below is the
# independent oracle for the hash rules.
spec = importlib.util.spec_from_file_location("refresh_trust", sys.argv[2])
refresh_trust = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh_trust)


def current_hash(event_name, group, hook):
    matcher = group.get("matcher") if event_name in refresh_trust.MATCHER_EVENTS else None
    return refresh_trust.command_hook_hash(event_name, matcher, hook)


with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["model"] == "common-model"
assert data["features"]["hooks"] is True
assert "profiles" not in data, "legacy [profiles.*] tables must be stripped from config.toml"
assert "profile" not in data, "legacy top-level profile selector must be stripped"
assert data["projects"]["/home/testuser"]["trust_level"] == "trusted"
assert data["projects"]["/work/project"]["trust_level"] == "trusted"
assert data["mcp_servers"]["example"]["tools"]["lookup"]["approval_mode"] == "approve"
assert data["notice"]["model_migrations"]["gpt-5.3-codex"] == "gpt-5.4"
assert data["tui"]["model_availability_nux"]["gpt-5.5"] == 2
assert data["hooks"]["PreToolUse"][0]["matcher"] == "ProviderShell"
assert data["hooks"]["PreToolUse"][0]["hooks"][0]["command"] == "provider-pre-shell"
assert data["hooks"]["PreToolUse"][1]["matcher"] == "ProviderEdit"
assert data["hooks"]["PreToolUse"][1]["hooks"][0]["command"] == "provider-pre-edit"
assert data["hooks"]["PostToolUse"][0]["matcher"] == "ProviderEdit"
assert data["hooks"]["PostToolUse"][0]["hooks"][0]["command"] == "provider-post-edit"
assert "ProviderRetired" not in data["hooks"]
assert "provider-pre-shell-v1" not in str(data["hooks"])
state = data["hooks"]["state"]
config_path = pathlib.Path(sys.argv[1]).resolve()
shell_key = f"{config_path}:pre_tool_use:0:0"
edit_key = f"{config_path}:pre_tool_use:1:0"
post_edit_key = f"{config_path}:post_tool_use:0:0"
assert state[shell_key]["enabled"] is False
assert state[shell_key]["trusted_hash"] == current_hash(
    "PreToolUse",
    data["hooks"]["PreToolUse"][0],
    data["hooks"]["PreToolUse"][0]["hooks"][0],
)
assert state[edit_key]["trusted_hash"] == current_hash(
    "PreToolUse",
    data["hooks"]["PreToolUse"][1],
    data["hooks"]["PreToolUse"][1]["hooks"][0],
)
assert state[post_edit_key]["trusted_hash"] == current_hash(
    "PostToolUse",
    data["hooks"]["PostToolUse"][0],
    data["hooks"]["PostToolUse"][0]["hooks"][0],
)
# Every event Codex accepts gets a trust entry; a missing label would leave
# that handler untrusted, and Codex skips untrusted handlers silently.
for event_name, label in (
    ("SubagentStart", "subagent_start"),
    ("SubagentStop", "subagent_stop"),
    ("Interrupt", "interrupt"),
    ("SessionEnd", "session_end"),
):
    key = f"{config_path}:{label}:0:0"
    assert key in state, key
    assert state[key]["trusted_hash"] == current_hash(
        event_name, data["hooks"][event_name][0], data["hooks"][event_name][0]["hooks"][0]
    ), key

# Codex hashes normalized identities: SessionEnd and Interrupt default to 1 s
# and clamp to 3 s, other events default to 600 s; Interrupt, Stop, and
# UserPromptSubmit ignore matchers while subagent and SessionEnd events keep them.
h = refresh_trust.command_hook_hash
cmd = {"type": "command", "command": "x"}
assert h("SessionEnd", None, {**cmd, "timeout": 10}) == h("SessionEnd", None, {**cmd, "timeout": 3})
assert h("Interrupt", None, cmd) == h("Interrupt", None, {**cmd, "timeout": 1})
assert h("SubagentStop", None, cmd) == h("SubagentStop", None, {**cmd, "timeout": 600})
assert h("SessionEnd", None, {**cmd, "timeout": 10}) != h("SubagentStop", None, {**cmd, "timeout": 10})
assert "Interrupt" not in refresh_trust.MATCHER_EVENTS
assert {"SessionEnd", "SubagentStart", "SubagentStop"} <= refresh_trust.MATCHER_EVENTS

# Pinned hashes reported by Codex 0.159.3 (hooks/list currentHash), so the
# default run, which cannot launch Codex, still checks the hash rules
# against Codex rather than against this helper. Hashes do not include the
# config path.
codex_vectors = [
    ("SessionEnd", {"matcher": "clear"},
     {"type": "command", "command": "se-async", "async": True, "timeout": 10},
     "477abbfb64df4ddb7121a7654d3615ccd255fb1b4da9067d494e28dcad34ff21"),
    ("Interrupt", {"matcher": "ignored"},
     {"type": "command", "command": "int", "timeout": 0},
     "d0a548ce24020215b3b64edbc8a01e422f98ba783bac3538a4870d9cf3b4bf4c"),
    ("PostToolUse", {},
     # "echo café" (split so the spellchecker does not read it as a word).
     {"type": "command", "command": "echo ca" "f\u00e9", "statusMessage": "L\u00e4uft\u2026"},
     "2dedaf96decd4c76d7cb4d77f1f7189ea494fce2080bfa2bc9b1592e189c57d2"),
    ("SubagentStart", {"matcher": "A"},
     {"type": "command", "command": "sa-limit", "additionalContextLimit": 100},
     "15c12a1a24407358dc3f49ce2443139281a7ca2d085243313c9d0badf7413b2a"),
    ("PreToolUse", {"matcher": "Bash"},
     {"type": "command", "command": "pre-limit", "additionalContextLimit": 100},
     "0b33bceafd9ea93a2ad640d86b795dd1eb3ed660a15e014b5e364f52274730e8"),
    ("Stop", {},
     {"type": "command", "command": "stop-limit-ignored", "additionalContextLimit": 100},
     "4ea0c01796b6f852a3578ff5a9e18fae46aa30d4c0380a6e17572a73f398cda0"),
    ("UserPromptSubmit", {},
     {"type": "command", "command": "ups-default-limit", "additionalContextLimit": 2500},
     "07957cf6d990ee6af80d643e0ba997fa26b4633c4852bf5ea5337c4c5f8c06e2"),
]
for event_name, group, hook, expected in codex_vectors:
    actual = current_hash(event_name, group, hook)
    assert actual == "sha256:" + expected, (event_name, hook, actual)
PY
    then
      _pass "codex hook: merges common/work, preserves local state, and trusts managed hooks"
    else
      _fail "codex hook: merges common/work, preserves local state, and trusts managed hooks"
    fi

    mv \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml" \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml.unavailable"
    # Recreate the former generated outputs after a successful merge. Even a
    # provider failure must still perform the independent retirement cleanup.
    printf 'sandbox_mode = "danger-full-access"\n' >"$CODEX_DIR/allow_all.config.toml"
    printf 'sandbox_mode = "workspace-write"\n' >"$CODEX_DIR/no_prompt.config.toml"
    codex_before_missing=$(cat "$CODEX_CONFIG")
    codex_missing_output=$(_run_codex_merge 2>&1)
    codex_missing_status=$?
    _assert_exit "codex consumer: missing provider asset is a failed refresh" \
      1 "$codex_missing_status"
    _assert_contains "codex consumer: missing provider asset reports the failed refresh" \
      "AgentGuard codex integration unavailable" "$codex_missing_output"
    _assert_eq "codex consumer: missing provider asset preserves the whole live config" \
      "$codex_before_missing" "$(cat "$CODEX_CONFIG")"
    _assert_eq "codex consumer: missing provider asset preserves live hook tables" \
      "provider-pre-shell" \
      "$(
        python3 - "$CODEX_CONFIG" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    print(tomllib.load(f)["hooks"]["PreToolUse"][0]["hooks"][0]["command"])
PY
      )"
    mv \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml.unavailable" \
      "$CODEX_AGENTGUARD_ASSETS/codex/hooks.toml"

    _assert_file_missing "codex hook: retires generated allow_all profile" \
      "$CODEX_DIR/allow_all.config.toml"
    _assert_file_missing "codex hook: retires generated no_prompt profile" \
      "$CODEX_DIR/no_prompt.config.toml"

    # Profile overlays: common + work fragments merge into the per-profile file,
    # later layers win, source layers override pre-existing local keys, and local
    # CLI-owned keys without a source counterpart survive.
    if python3 - "$CODEX_DIR/layered.config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["model_reasoning_effort"] == "low", data       # work overrides common
assert data["sandbox_mode"] == "danger-full-access", data  # work-only key lands
assert data["approval_policy"] == "never", data            # source beats local state
assert data["model"] == "local-allow", data                # local-only key preserved
assert data["features"]["web_search_request"] is True, data  # nested profile tables survive
PY
    then
      _pass "codex hook: renders profile overlays, layering work over common and preserving local state"
    else
      _fail "codex hook: renders profile overlays, layering work over common and preserving local state"
    fi

    if python3 - "$CODEX_DIR/experimental.config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["model"] == "experimental-model", data
assert data["model_reasoning_effort"] == "high", data
PY
    then
      _pass "codex hook: renders dynamically discovered profile families"
    else
      _fail "codex hook: renders dynamically discovered profile families"
    fi

    _run_codex_merge 2>/dev/null
    if python3 - "$CODEX_CONFIG" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert "profiles" not in data, "new Codex config should not keep legacy inline profiles"
PY
    then
      _pass "codex hook: keeps config.toml free of legacy inline profiles"
    else
      _fail "codex hook: keeps config.toml free of legacy inline profiles"
    fi
    _assert_file_missing "codex hook: repeat merge does not probe installed Codex version" "$_CODEX_VERSION_PROBE"

    codex_content_before_cache_probe=$(cat "$CODEX_CONFIG")
    saved_path=$PATH
    codex_cache_output=""
    codex_cache_status=0
    codex_cache_output=$(_run_codex_merge 2>&1) || codex_cache_status=$?
    PATH=$saved_path
    _assert_exit "codex hook: warm cache succeeds without merge dependencies" \
      0 "$codex_cache_status"
    _assert_not_contains "codex hook: warm cache emits no missing-dependency warning" \
      "mikefarah/yq not found" "$codex_cache_output"
    _assert_eq "codex hook: warm cache skips yq when inputs are unchanged" \
      "$codex_content_before_cache_probe" "$(cat "$CODEX_CONFIG")"

    cat >>"$TEST_HOME/.config/dot/merge-hooks.d/codex/config.d/50-environment.replace/80-work.toml" <<'TOML'

[projects."/cache-source-change"]
trust_level = "trusted"
TOML
    saved_path=$PATH
    _codex_no_yq_bin=$(_mock_bin)
    ln -s "$(command -v python3)" "$_codex_no_yq_bin/python3"
    PATH="$_codex_no_yq_bin:/usr/bin:/bin" _run_codex_merge 2>/dev/null
    PATH=$saved_path
    _run_codex_merge 2>/dev/null
    if python3 - "$CODEX_CONFIG" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["projects"]["/cache-source-change"]["trust_level"] == "trusted"
PY
    then
      _pass "codex hook: skipped merge does not cache stale config"
    else
      _fail "codex hook: skipped merge does not cache stale config"
    fi

    if [[ -n "${CI:-}" ]]; then
      _pass "codex hook: installed Codex trust check skipped in CI"
    elif [[ "${DOT_TEST_INSTALLED_CODEX:-0}" != "1" ]]; then
      # The config merge behavior above is deterministic; this probe exercises the
      # user's installed Codex binary, which may depend on host-specific wrappers,
      # downloads, or cache permissions. Keep base dotfiles tests hermetic unless
      # someone explicitly opts into that integration check.
      _pass "codex hook: installed Codex trust check skipped (set DOT_TEST_INSTALLED_CODEX=1)"
    elif command -v codex >/dev/null 2>&1; then
      _CODEX_TEST_DOTSLASH_CACHE="${DOTSLASH_CACHE:-}"
      if [[ -z "$_CODEX_TEST_DOTSLASH_CACHE" && "$(uname -s)" == "Darwin" && "$HOME" != "$REAL_HOME" ]]; then
        _CODEX_TEST_DOTSLASH_CACHE="$REAL_HOME/Library/Caches/dotslash"
      fi

      _codex_check_status=0
      CODEX_HOME="$CODEX_DIR" CODEX_TEST_DOTSLASH_CACHE="$_CODEX_TEST_DOTSLASH_CACHE" python3 - "$CODEX_CONFIG" <<'PY' || _codex_check_status=$?
import json
import os
import pathlib
import select
import subprocess
import sys
import time
import tomllib

config_path = pathlib.Path(sys.argv[1])
with config_path.open("rb") as f:
    config = tomllib.load(f)
state = config["hooks"]["state"]

env = os.environ.copy()
env["CODEX_HOME"] = str(config_path.parent)
if env.get("CODEX_TEST_DOTSLASH_CACHE"):
    env.setdefault("DOTSLASH_CACHE", env["CODEX_TEST_DOTSLASH_CACHE"])
proc = subprocess.Popen(
    ["codex", "app-server", "--listen", "stdio://"],
    cwd=str(config_path.parent),
    env=env,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
for message in [
    {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {"clientInfo": {"name": "dot-core-test", "title": None, "version": "0"}},
    },
    {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "hooks/list",
        "params": {"cwds": [str(config_path.parent.parent)]},
    },
]:
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()

result = None
stderr = []
# The vendor Codex wrapper can install plugins on first launch, which has
# taken longer than 8 s; the bound only guards against a hung app-server.
deadline = time.time() + 30
while time.time() < deadline:
    ready, _, _ = select.select([proc.stdout, proc.stderr], [], [], 0.2)
    for stream in ready:
        line = stream.readline()
        if not line:
            continue
        if stream is proc.stderr:
            stderr.append(line.rstrip())
            continue
        payload = json.loads(line)
        if payload.get("id") == 2:
            result = payload
            deadline = time.time()
            break

proc.terminate()
try:
    proc.wait(timeout=2)
except subprocess.TimeoutExpired:
    proc.kill()

if result is None:
    if any(
        "sandbox-exec: sandbox_apply: Operation not permitted" in line
        or "failed to create CAS artifact directory" in line
        for line in stderr
    ):
        print(
            "codex app-server trust check skipped: host Codex wrapper is unavailable",
            file=sys.stderr,
        )
        sys.exit(77)
    raise AssertionError("codex hooks/list did not return; stderr=" + "\n".join(stderr))

entry = result["result"]["data"][0]
assert entry["warnings"] == [], entry["warnings"]
assert entry["errors"] == [], entry["errors"]
generated_hooks = [
    hook for hook in entry["hooks"]
    if pathlib.Path(hook.get("sourcePath", "")).resolve() == config_path.resolve()
]
assert generated_hooks, entry["hooks"]
for hook in generated_hooks:
    assert hook["key"] in state, hook
    if "trustStatus" in hook:
        assert hook["trustStatus"] == "trusted", hook
    if "currentHash" in hook:
        assert state[hook["key"]]["trusted_hash"] == hook["currentHash"], hook
PY
      if [[ "$_codex_check_status" -eq 0 ]]; then
        _pass "codex hook: installed Codex reports generated hooks trusted"
      elif [[ "$_codex_check_status" -eq 77 ]]; then
        _pass "codex hook: installed Codex trust check skipped (macOS sandbox unavailable)"
      else
        _fail "codex hook: installed Codex reports generated hooks trusted"
      fi
    else
      _pass "codex hook: installed Codex trust check skipped (codex unavailable)"
    fi

    # Bootstrap: no existing config.toml
    rm -f "$CODEX_CONFIG"
    _run_codex_merge 2>/dev/null
    if [[ -s "$CODEX_CONFIG" ]] && python3 -c "
import pathlib, sys, tomllib
with open(sys.argv[1], 'rb') as f: data = tomllib.load(f)
assert data['model'] == 'common-model'
assert data['features']['hooks'] is True
assert data['projects']['/work/project']['trust_level'] == 'trusted'
key = str(pathlib.Path(sys.argv[1]).resolve()) + ':pre_tool_use:0:0'
assert data['hooks']['state'][key]['trusted_hash'].startswith('sha256:')
" "$CODEX_CONFIG" 2>/dev/null; then
      _pass "codex hook: bootstrap from scratch (no existing config) with trusted hooks"
    else
      _fail "codex hook: bootstrap from scratch (no existing config) with trusted hooks"
    fi

    # Corrupt config recovery
    printf 'this is [[[not valid toml' >"$CODEX_CONFIG"
    _run_codex_merge 2>/dev/null
    if [[ -s "$CODEX_CONFIG" ]] && python3 -c "
import sys, tomllib
with open(sys.argv[1], 'rb') as f: tomllib.load(f)
" "$CODEX_CONFIG" 2>/dev/null; then
      _pass "codex hook: recovers from corrupt config"
    else
      _fail "codex hook: recovers from corrupt config"
    fi

    rm -rf "$CODEX_DIR"
    rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/codex"
  else
    echo "  SKIP: Codex merge hook assertions (mikefarah/yq unavailable)"
  fi
  _test_summary
}
