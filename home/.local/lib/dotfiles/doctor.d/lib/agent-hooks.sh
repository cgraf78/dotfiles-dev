# shellcheck shell=bash
# dot doctor: Agent tooling checks: AgentGuard registration and smoke probes,
# Grok's Claude-compat switches, Hive Memory, and leftover temporaries in the
# agent config folders the dev merge hooks write.

# Per-probe deadline in seconds. A healthy hook answers in well under one;
# a hung one would otherwise hold the whole section.
_DR_AGENT_HOOK_DEADLINE=10

# What the probes set for every hook run: a neutral agent name, and the
# hook's side effects (memory hooks, process detection, the commit gate)
# switched off. The reproduction hints print the same settings.
_DR_AGENT_HOOK_ENV=(
  AGENTGUARD_NAME=agent
  AGENTGUARD_HIVE_MEMORY_HOOKS=0
  AGENTGUARD_PROCESS_DETECT=0
  AGENTGUARD_SLEY_GATE=0
)
# The probe payloads: an ordinary command, one policy forbids, and the stop
# hook's empty event.
_DR_AGENT_PROBE_BENIGN='{"tool_input":{"command":"dot status"}}'
_DR_AGENT_PROBE_FORBIDDEN='{"tool_input":{"command":"git status -uall"}}'
_DR_AGENT_PROBE_STOP='{}'

# Run one hook the way agents do. Every command AgentGuard's integration
# fragments register starts with `env -u BASH_ENV -u ENV`, so the hook never
# inherits a startup file; a probe that set BASH_ENV instead could pass while
# the real hook fails. _DR_AGENT_HOOK_ENV names a neutral agent and turns off
# the hook's side effects, and TMPDIR keeps its scratch files in a private
# directory.
_dr_run_agent_hook() {
  local hook="$1" payload="$2"
  local tmp out_file err_file rc=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-agent-hook) || return 1
  out_file="$tmp/out"
  err_file="$tmp/err"

  # The hook opens its payload itself, through a bare Bash that execs it: a
  # pipe into the bounded command would not reach it under base's builtin
  # watchdog (hosts without a coreutils timeout), which starts the command
  # as a background job, and Bash gives those /dev/null for stdin.
  printf '%s' "$payload" >"$tmp/payload" || {
    rm -rf "$tmp" 2>/dev/null || true
    return 1
  }
  (
    cd "$HOME" || exit 1
    # shellcheck disable=SC2016  # $1 and $2 expand in the exec shell.
    _dr_dev_bounded "$_DR_AGENT_HOOK_DEADLINE" \
      env -u BASH_ENV -u ENV \
      "${_DR_AGENT_HOOK_ENV[@]}" \
      AGENTGUARD_SESSION_ID="dot-doctor-$$" \
      TMPDIR="$tmp" \
      "$BASH" --noprofile --norc -c 'exec "$1" <"$2"' dot-doctor "$hook" "$tmp/payload" \
      >"$out_file" 2>"$err_file" </dev/null
  ) || rc=$?

  _DR_AGENT_HOOK_STDOUT=$(cat "$out_file" 2>/dev/null || true)
  _DR_AGENT_HOOK_STDERR=$(cat "$err_file" 2>/dev/null || true)
  rm -f "$out_file" "$err_file" "$tmp/payload"
  rmdir "$tmp" 2>/dev/null || true
  return "$rc"
}

# Launch one smoke probe in the background. $1=result prefix, $2=hook,
# $3=payload. Each probe runs the same _dr_run_agent_hook primitive with its
# own scratch dir, so its environment, payload, and captures are identical to
# a sequential run; only the wall-clock overlap differs. The hook probes are
# independent (separate payloads, separate scratch dirs, no shared hook-side
# state), so overlapping them changes neither records nor side effects.
# Results land in $1.{rc,stdout,stderr} for _dr_probe_ok to collect.
_dr_run_agent_hook_async() {
  local prefix="$1" hook="$2" payload="$3"
  (
    # Start from unset captures so a probe that never runs (e.g. mktemp
    # failure) reports empty output instead of leaking a sibling's results.
    unset _DR_AGENT_HOOK_STDOUT _DR_AGENT_HOOK_STDERR
    # Plain assignment, no `local`: this fork cannot leak into the parent.
    # The `||` guard keeps `set -e` callers from aborting before results land.
    rc=0
    _dr_run_agent_hook "$hook" "$payload" || rc=$?
    printf '%s' "$rc" >"$prefix.rc"
    printf '%s' "${_DR_AGENT_HOOK_STDOUT-}" >"$prefix.stdout"
    printf '%s' "${_DR_AGENT_HOOK_STDERR-}" >"$prefix.stderr"
  ) &
}

# Collect one background probe launched by _dr_run_agent_hook_async: restore
# _DR_AGENT_HOOK_STDOUT/_DR_AGENT_HOOK_STDERR exactly as _dr_run_agent_hook
# would have set them (command substitution strips trailing newlines the same
# way), then return the recorded exit status. A missing result (the probe fork
# died before reporting) fails closed as rc 1 with empty captures.
_dr_probe_ok() {
  local prefix="$1" rc=1
  if [[ -f $prefix.rc ]]; then
    rc=$(<"$prefix.rc")
    [[ $rc =~ ^[0-9]+$ ]] || rc=1
  fi
  _DR_AGENT_HOOK_STDOUT=$(cat "$prefix.stdout" 2>/dev/null || true)
  _DR_AGENT_HOOK_STDERR=$(cat "$prefix.stderr" 2>/dev/null || true)
  return "$rc"
}

# Every agent runtime the dev merge hooks register AgentGuard for, as
# command|display name|config format|config path relative to HOME. Keep this
# aligned with merge-hooks.d/{claude,codex,muse,gemini,grok,opencode}.sh: the
# command is the presence probe those hooks use, and the path is the file they
# write. A merge that fails only warns and leaves the agent's last config in
# place, so this table is what notices an agent running without its guards.
_DR_AGENTGUARD_REGISTRATIONS=(
  'claude|Claude Code|json|.claude/settings.json'
  'codex|Codex|toml|.codex/config.toml'
  'muse|Muse|json|.config/muse/settings.json'
  'gemini|Gemini CLI|json|.gemini/settings.json'
  'grok|Grok|json|.grok/hooks/agentguard.json'
  'opencode|OpenCode|plugin|.config/opencode/plugins/dotfiles-agentguard.js'
)
# Agent config folders the dev merge hooks also write, beyond the folder of
# each registration above: grok-config.sh writes ~/.grok/config.toml.
_DR_AGENT_CONFIG_EXTRA_DIRS=(.grok)

# Merge hooks rewrite agent configs through sibling temporaries, and an
# update killed mid-write leaves one behind. Base owns the check and its
# naming rules; this overlay owns the list of folders its hooks write, which
# is this table, so the two cannot drift. The module is newer than some
# bases, and doctor workers run under `set -e`, so a base without it skips
# the check rather than failing the section.
_dr_check_agent_config_temporaries() {
  local entry relative
  local -a dirs=()
  for entry in "${_DR_AGENTGUARD_REGISTRATIONS[@]}"; do
    relative=${entry##*|}
    dirs+=("${relative%/*}")
  done
  dirs+=("${_DR_AGENT_CONFIG_EXTRA_DIRS[@]}")
  if dot_doctor_source doctor.d/lib/config-temporaries.sh &&
    declare -F _dr_check_config_temporaries >/dev/null; then
    _dr_check_config_temporaries "${dirs[@]}"
  fi
}

# Parse every queued agent config in one Python process (doctor's per-check
# budget is a handful of processes) and print one line per config, fields
# separated by US (\x1f) because read collapses runs of whitespace IFS and
# would shift an empty field:
# agent, status (ok|invalid|disabled|unmanaged|unverified), detail, and the sorted
# agent-hook-* command names its hook entries reference. Python's json and
# tomllib parse exactly what the agents parse; tomllib needs Python 3.11, so an
# older interpreter still lists Codex's commands (and line-matches the
# features.hooks switch) but reports the TOML syntax as unverified instead of
# guessing. Args: plugin marker, then agent/kind/path triples.
_dr_agentguard_inspect() {
  # -I: ignore PYTHONPATH and the cwd (the worker runs in HOME), so a stray
  # ~/json.py cannot shadow the standard library.
  python3 -I - "$@" <<'PY'
import json
import re
import sys

# Bare names only: AgentGuard registers PATH-resolved commands, and a hook
# configured by absolute path is the user's own.
NAME = re.compile(r"(?<![A-Za-z0-9_/-])agent-hook-[a-z0-9]+(?:-[a-z0-9]+)*")
# Without tomllib, read only the quoted value of `command = ...` assignments,
# never comments (whole-line or trailing).
TOML_COMMAND = re.compile(
    r"""^\s*command\s*=\s*("(?:[^"\\\n]|\\.)*"|'[^'\n]*')""", re.MULTILINE
)
# Without tomllib, a line match for the switch that turns Codex hooks off:
# `hooks = false` under a `[features]` header, or a top-level
# `features.hooks = false`. Comments and quoted keys are out of scope; this
# only has to catch the plain form Codex and AgentGuard write.
# Array-of-tables headers ([[x]]) end the [features] table too.
TOML_HEADER = re.compile(r"^\s*\[\[?([^\[\]]+)\]\]?\s*(?:#.*)?$")
TOML_HOOKS_OFF = re.compile(r"^\s*hooks\s*=\s*false\s*(?:#.*)?$")
TOML_DOTTED_HOOKS_OFF = re.compile(r"^\s*features\s*\.\s*hooks\s*=\s*false\s*(?:#.*)?$")


def toml_hooks_off(text):
    table = ""
    for line in text.splitlines():
        header = TOML_HEADER.match(line)
        if header:
            table = header.group(1).strip()
        elif table == "features" and TOML_HOOKS_OFF.match(line):
            return True
        elif table == "" and TOML_DOTTED_HOOKS_OFF.match(line):
            return True
    return False


# In the JavaScript plugin, only whole quoted literals name a command; a
# template such as `agent-hook-${phase}` or a comment does not.
JS_LITERAL = re.compile(r"""["'`](agent-hook-[a-z0-9]+(?:-[a-z0-9]+)*)["'`]""")


def commands(node):
    """Yield every hook command string below a native hooks table."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "command" and isinstance(value, str):
                yield value
            else:
                yield from commands(value)
    elif isinstance(node, list):
        for item in node:
            yield from commands(item)


def one_line(text):
    return " ".join(str(text).replace("\x1f", " ").split())


def hook_table(document):
    if not isinstance(document, dict):
        raise ValueError("top level is not a table")
    return document.get("hooks", {})


def disabled_reason(document):
    """Name a runtime switch that turns every registered hook off."""
    if document.get("disableAllHooks") is True:
        return "disableAllHooks is true"
    features = document.get("features")
    # Only an explicit false: a runtime that later enables hooks by default
    # may drop the flag from AgentGuard's fragment altogether.
    if isinstance(features, dict) and features.get("hooks") is False:
        return "features.hooks is false"
    return ""


marker, triples = sys.argv[1], sys.argv[2:]
for index in range(0, len(triples), 3):
    agent, kind, path = triples[index : index + 3]
    status, detail, sources, document = "ok", "", [], None
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if kind == "json":
            document = json.loads(text)
        elif kind == "toml":
            try:
                import tomllib
            except ImportError:
                status, sources = "unverified", TOML_COMMAND.findall(text)
                if toml_hooks_off(text):
                    status, detail = "disabled", "features.hooks is false"
            else:
                document = tomllib.loads(text)
        else:
            # The plugin is JavaScript: its command names are string literals,
            # and the provider's first-line marker is what proves ownership.
            if text.split("\n", 1)[0] != marker:
                status = "unmanaged"
            sources = [f'"{name}"' for name in JS_LITERAL.findall(text)]
        if document is not None:
            sources = list(commands(hook_table(document)))
            detail = disabled_reason(document)
            if detail:
                status = "disabled"
    except (OSError, UnicodeDecodeError, ValueError, RecursionError) as error:
        # JSONDecodeError and TOMLDecodeError both derive from ValueError.
        print(agent, "invalid", one_line(error), "", sep="\x1f")
        continue
    names = sorted({name for source in sources for name in NAME.findall(source)})
    print(agent, status, detail, " ".join(names), sep="\x1f")
PY
}

# Succeed when NAME is an executable file on PATH or in ~/.local/bin, where
# shdeps links AgentGuard's commands; doctor may run with a narrower PATH
# (ssh, launchd) than the agents do. Not `type -P`: when only a
# non-executable match exists it still prints that path, and walking PATH in
# the shell costs no subprocess per command.
_dr_executable_on_path() {
  local name=$1 dir
  local -a dirs=()
  IFS=: read -r -a dirs <<<"$PATH"
  for dir in "${dirs[@]}" "$HOME/.local/bin"; do
    [[ -n $dir ]] || dir=.
    [[ -f $dir/$name && -x $dir/$name ]] && return 0
  done
  return 1
}

# Next steps shared by several registration rows.
_DR_AGENTGUARD_UNMANAGED_HINT="dotfiles do not own what is there: move it aside, then run 'dot update' to install the managed plugin"
_DR_AGENTGUARD_INSPECTOR_HINT="rerun 'dot doctor'; if it persists, check that each installed agent's config file parses (an unexpected shape can stop the inspector), then run 'dot update'"

# Report one row per installed agent: its config parses, it registers
# AgentGuard at all, and every agent-hook-* command it names resolves to an
# executable on PATH, the same lookup the agent's `env ... agent-hook-*` hook
# command performs. Agents that are not installed get no row, matching the
# merge hooks, which skip them too.
_dr_check_agentguard_registrations() {
  local entry agent label kind relative config marker='' output status=0
  local result_agent result detail names name display index=0
  local -a queued=() queued_labels=() queued_configs=() missing=() name_list=()

  for entry in "${_DR_AGENTGUARD_REGISTRATIONS[@]}"; do
    IFS='|' read -r agent label kind relative <<<"$entry"
    command -v "$agent" >/dev/null 2>&1 || continue
    config=$HOME/$relative
    display=$(_dr_tilde "$config")
    if [[ ! -e $config ]]; then
      # The merge hooks rebuild a dangling config link like a missing file.
      [[ ! -L $config ]] || display+=' is a broken link'
      _dr_dev_row warn "$label AgentGuard hooks missing" "$display" "run 'dot update'"
      continue
    fi
    if [[ $kind == plugin ]]; then
      # Dotfiles install the plugin as a regular file and never replace a
      # user's symlink or directory there, so anything else is user-owned.
      if [[ ! -f $config || -L $config ]]; then
        _dr_dev_row warn "$label AgentGuard plugin unmanaged" "$display" \
          "$_DR_AGENTGUARD_UNMANAGED_HINT"
        continue
      fi
      marker=$(dot_agentguard_opencode_marker)
    fi
    queued+=("$agent" "$kind" "$config")
    queued_labels+=("$label")
    queued_configs+=("$display")
  done
  ((${#queued[@]} > 0)) || return 0

  if ! command -v python3 >/dev/null 2>&1; then
    for label in "${queued_labels[@]}"; do
      _dr_dev_row warn "$label AgentGuard hooks unchecked" 'python3 is required' \
        'install python3 to check them'
    done
    return 0
  fi
  # Keep stderr out of the protocol stream: an interpreter warning there would
  # otherwise misalign every result line.
  output=$(_dr_agentguard_inspect "$marker" "${queued[@]}" 2>/dev/null) || status=$?
  if ((status != 0)); then
    _dr_dev_row warn 'AgentGuard hook registration unchecked' "python3 exited $status" \
      "$_DR_AGENTGUARD_INSPECTOR_HINT"
    return 0
  fi

  while IFS=$'\x1f' read -r result_agent result detail names; do
    label=${queued_labels[index]:-}
    display=${queued_configs[index]:-}
    agent=${queued[index * 3]:-}
    index=$((index + 1))
    # The inspector answers in queue order; a mismatch means its output was
    # not the protocol above, so say so rather than misattribute a result.
    if [[ -z $label || $result_agent != "$agent" ]]; then
      _dr_dev_row warn 'AgentGuard hook registration unchecked' 'unexpected inspector output' \
        "$_DR_AGENTGUARD_INSPECTOR_HINT"
      return 0
    fi
    case $result in
      invalid)
        _dr_dev_row fail "$label AgentGuard config invalid" "$display: $detail" \
          "fix the file, then run 'dot update'"
        continue
        ;;
      unmanaged)
        _dr_dev_row warn "$label AgentGuard plugin unmanaged" "$display" \
          "$_DR_AGENTGUARD_UNMANAGED_HINT"
        continue
        ;;
      disabled)
        _dr_dev_row warn "$label AgentGuard hooks disabled" "$detail in $display" \
          'remove that setting to turn the hooks back on'
        continue
        ;;
    esac
    if [[ -z $names ]]; then
      _dr_dev_row warn "$label AgentGuard hooks missing" \
        "no agent-hook-* commands in $display" "run 'dot update'"
      continue
    fi
    # Every AgentGuard fragment registers the pre-bash guard. Without it the
    # remaining lifecycle hooks still look registered while shell commands
    # run unguarded, e.g. after a user layer replaced that one entry.
    if [[ " $names " != *' agent-hook-pre-bash '* ]]; then
      _dr_dev_row warn "$label AgentGuard pre-bash guard not registered" \
        "$display" "run 'dot update'"
      continue
    fi
    read -r -a name_list <<<"$names"
    missing=()
    for name in "${name_list[@]}"; do
      _dr_executable_on_path "$name" || missing+=("$name")
    done
    if ((${#missing[@]} > 0)); then
      _dr_dev_row fail "$label AgentGuard hook commands missing" \
        "not executable on PATH or in ~/.local/bin: ${missing[*]}" \
        "run 'dot update' to reinstall AgentGuard"
      continue
    fi
    detail="${#name_list[@]} command(s) in $display"
    [[ $result != unverified ]] ||
      detail+='; TOML syntax unchecked (python3 lacks tomllib)'
    _dr_ok "$label AgentGuard hooks" "$detail"
  done <<<"$output"
  ((index == ${#queued_labels[@]})) ||
    _dr_dev_row warn 'AgentGuard hook registration unchecked' 'inspector output was truncated' \
      "$_DR_AGENTGUARD_INSPECTOR_HINT"
}

_dr_check_grok_compat() {
  # The same presence gate as the registration table and the grok merge
  # hooks (`_dot_tool_present grok`).
  command -v grok >/dev/null 2>&1 || return 0

  local cfg="$HOME/.grok/config.toml"
  local hooks="$HOME/.grok/hooks/agentguard.json"
  local rules="$HOME/.grok/rules/agent-rules.md"
  local expect_hooks=0 expect_rules=0 status

  [[ -f $hooks && ! -L $hooks ]] && expect_hooks=1
  [[ -f $rules && ! -L $rules ]] && expect_rules=1
  # Native replacements are what make disable safe. Before they exist, Claude
  # compat is still the live Grok coverage and this overlay must not nag.
  # skills and mcps stay on. Only hooks/rules/agents are gated.
  [[ $expect_hooks -eq 1 || $expect_rules -eq 1 ]] || return 0

  if [[ ! -f $cfg ]]; then
    _dr_dev_row warn "Grok Claude-compat cells missing" "$(_dr_tilde "$cfg")" "run 'dot update'"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    _dr_dev_row warn "Grok Claude-compat cells unverified" "python3 is required" \
      'install python3 to check them'
    return 0
  fi

  # Structured keys, not display text. Avoid tomllib: CentOS Stream 9 and some
  # macOS CI Pythons are 3.9. Parse only [compat.claude] boolean assignments.
  status=0
  python3 - "$cfg" "$expect_hooks" "$expect_rules" <<'PY' || status=$?
import sys
from pathlib import Path

claude = {}
in_section = False
for raw in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("["):
        in_section = line == "[compat.claude]"
        continue
    if not in_section or "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if value in ("true", "false"):
        claude[key] = value == "true"

expect_hooks = sys.argv[2] == "1"
expect_rules = sys.argv[3] == "1"
ok = True
if expect_hooks and claude.get("hooks") is not False:
    ok = False
if expect_rules and (
    claude.get("rules") is not False or claude.get("agents") is not False
):
    ok = False
sys.exit(0 if ok else 1)
PY
  if [[ $status -eq 0 ]]; then
    _dr_ok "Grok disables Claude-compat discovery" \
      "$(_dr_tilde "$cfg")"
  else
    _dr_dev_row warn "Grok Claude-compat discovery still enabled" \
      "$(_dr_tilde "$cfg")" "run 'dot update'"
  fi
}

# Report via REPLY the next step for a failed probe: the reinstall, then
# (after NOTE, if any) the command that reruns HOOK (a path) on PAYLOAD by
# hand the way the probe ran it. The command comes last, so it can be
# pasted from "(" to the end; it runs in a subshell, from ~, without the
# shell's startup files, under a throwaway session ID and a private TMPDIR
# it removes. The directory is made before the `cd`, so `t` is always the
# subshell's own (empty if mktemp failed) and a failed `cd` removes only
# what the command created, never a `t` the caller's shell set. Without
# that session ID the hook would fall back to the calling agent's own
# session and could, for one, use up that session's completion bell. The hook path is quoted: under HOME as "$HOME/...",
# elsewhere in single quotes.
_dr_agent_repro_hint() {
  local hook=$1 payload=$2 note=${3:-} shown
  case $hook in
    "$HOME"/*) shown="\"\$HOME/${hook#"$HOME"/}\"" ;;
    *\'*) shown='<hook>' ;;
    *) shown="'$hook'" ;;
  esac
  REPLY="reinstall AgentGuard with 'dot update'; to see the failure first, run${note:+ ($note)}:"
  REPLY+=" (t=\$(mktemp -d) && cd ~ && echo '$payload' | env -u BASH_ENV -u ENV"
  REPLY+=" ${_DR_AGENT_HOOK_ENV[*]} AGENTGUARD_SESSION_ID=dot-doctor-repro TMPDIR=\"\$t\" $shown;"
  REPLY+=" rc=\$?; rm -rf \"\$t\"; exit \$rc)"
}

# Smoke-probe the installed pre-bash and stop hooks; results go to DIR.
_dr_check_agent_hook_probes() {
  local results=$1
  local pre_bash="$HOME/.local/bin/agent-hook-pre-bash"
  local stop_hook="$HOME/.local/bin/agent-hook-stop"
  local -a probe_pids=()

  if [[ ! -x "$pre_bash" ]]; then
    _dr_dev_row warn "agent pre-bash hook unavailable" "$(_dr_tilde "$pre_bash")" \
      "run 'dot update' to reinstall AgentGuard"
    return 0
  fi

  # The three smoke probes need three hook executions (two binaries, two
  # pre-bash payloads), so run them as one combined background batch: wall
  # time drops from the sum to roughly the slowest probe. Launch conditions
  # are the same file tests as before, so a missing pre-bash still returns
  # before any hook runs, and results are applied below in the original
  # order, so records are unchanged.
  _dr_run_agent_hook_async "$results/dot-status" "$pre_bash" "$_DR_AGENT_PROBE_BENIGN"
  probe_pids+=("$!")
  _dr_run_agent_hook_async "$results/raw-git" "$pre_bash" "$_DR_AGENT_PROBE_FORBIDDEN"
  probe_pids+=("$!")
  if [[ -x "$stop_hook" ]]; then
    _dr_run_agent_hook_async "$results/stop" "$stop_hook" "$_DR_AGENT_PROBE_STOP"
    probe_pids+=("$!")
  fi
  # probe_pids always holds at least the two pre-bash probes here. Under
  # `set -e` a failing wait would abort before records publish; the probes
  # report pass/fail through their result files, not through wait.
  wait "${probe_pids[@]}" || true

  # Generic smoke rows: one probe proves the hook lets an ordinary command
  # through, the other proves it blocks one that policy forbids. Exit status 2
  # is the hook protocol's block signal; the stderr wording is display text for
  # the agent and is deliberately not matched here. Exit status 124 (or 137
  # after a SIGKILL) is the probe deadline.
  local rc=0
  _dr_probe_ok "$results/dot-status" || rc=$?
  if ((rc == 0)); then
    _dr_ok "agent pre-bash allows a benign command" 'dot status'
  else
    _dr_agent_repro_hint "$pre_bash" "$_DR_AGENT_PROBE_BENIGN"
    _dr_dev_row fail "agent pre-bash rejects a benign command" "$(_dr_probe_reason "$rc")" "$REPLY"
  fi

  rc=0
  _dr_probe_ok "$results/raw-git" || rc=$?
  if ((rc == 0)); then
    if _dr_is_dotfiles_checkout; then
      _dr_ok "agent pre-bash enforces policy" \
        'raw git status is allowed: HOME is a Git checkout'
    else
      _dr_agent_repro_hint "$pre_bash" "$_DR_AGENT_PROBE_FORBIDDEN" 'a block exits 2 with a reason'
      _dr_dev_row fail "agent pre-bash does not enforce policy" \
        "raw dotfiles git status was allowed; expected a block (exit 2)" "$REPLY"
    fi
  elif ((rc == 2)) && [[ -n "$_DR_AGENT_HOOK_STDERR" ]]; then
    # The protocol pairs exit 2 with a reason on stderr for the agent; a bare
    # exit 2 is more likely a shell or jq usage error than a block.
    _dr_ok "agent pre-bash enforces policy" 'blocks raw dotfiles git status'
  elif _dr_dev_deadline_status "$rc" || [[ -z $_DR_AGENT_HOOK_STDERR ]]; then
    _dr_agent_repro_hint "$pre_bash" "$_DR_AGENT_PROBE_FORBIDDEN" 'a block exits 2 with a reason'
    _dr_dev_row fail "agent pre-bash policy probe failed" "$(_dr_probe_reason "$rc")" "$REPLY"
  else
    _dr_agent_repro_hint "$pre_bash" "$_DR_AGENT_PROBE_FORBIDDEN" 'a block exits 2 with a reason'
    _dr_dev_row fail "agent pre-bash policy probe failed" "exit $rc: $(_dr_probe_reason "$rc")" \
      "$REPLY"
  fi

  if [[ -x "$stop_hook" ]]; then
    rc=0
    _dr_probe_ok "$results/stop" || rc=$?
    if ((rc == 0)); then
      _dr_ok "agent stop hook runs"
    else
      _dr_agent_repro_hint "$stop_hook" "$_DR_AGENT_PROBE_STOP"
      _dr_dev_row fail "agent stop hook failed" "$(_dr_probe_reason "$rc")" "$REPLY"
    fi
  else
    _dr_dev_row warn "agent stop hook unavailable" "$(_dr_tilde "$stop_hook")" \
      "run 'dot update' to reinstall AgentGuard"
  fi
}

# Print why a collected probe failed with status $1: the deadline, or the
# first line the hook wrote to stderr, as record text (a tab or carriage
# return would make the record helper fail the worker), or its bare status.
_dr_probe_reason() {
  local line
  if _dr_dev_deadline_status "$1"; then
    printf 'no answer within %ss' "$_DR_AGENT_HOOK_DEADLINE"
  else
    line=${_DR_AGENT_HOOK_STDERR%%$'\n'*}
    line=${line//[$'\t\r']/ }
    printf '%s' "${line:-exited $1 without a message}"
  fi
}

_dr_check_agent_tooling() {
  local results
  _dr_section "Agent tooling"

  if ! results=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-agent-hooks); then
    _dr_dev_row warn 'Agent tooling unchecked' 'could not create a temporary directory' \
      "$_DR_DEV_TMPDIR_HINT"
    return 0
  fi
  # hm may wait on a network mount, so it runs alongside everything else.
  _dr_hive_memory_start "$results"
  _dr_check_agentguard_registrations
  _dr_check_grok_compat
  _dr_check_agent_hook_probes "$results"
  _dr_hive_memory_finish "$results"
  _dr_check_agent_config_temporaries
  rm -rf "$results" 2>/dev/null || true
}
