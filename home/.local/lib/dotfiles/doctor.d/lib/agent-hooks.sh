# shellcheck shell=bash
# dot doctor: Agent Hooks checks.

_dr_run_agent_hook() {
  local hook="$1" payload="$2"
  local tmp out_file err_file rc=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-agent-hook) || return 1
  out_file="$tmp/out"
  err_file="$tmp/err"

  (
    cd "$HOME" || exit 1
    printf '%s' "$payload" |
      AGENTGUARD_NAME=agent \
        AGENTGUARD_SESSION_ID="dot-doctor-$$" \
        AGENTGUARD_HIVE_MEMORY_HOOKS=0 \
        AGENTGUARD_PROCESS_DETECT=0 \
        AGENTGUARD_SLEY_GATE=0 \
        TMPDIR="$tmp" \
        _SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS='' \
        BASH_ENV="$HOME/.config/shell/env-noninteractive.sh" \
        "$hook" >"$out_file" 2>"$err_file"
  ) || rc=$?

  _DR_AGENT_HOOK_STDOUT=$(cat "$out_file" 2>/dev/null || true)
  _DR_AGENT_HOOK_STDERR=$(cat "$err_file" 2>/dev/null || true)
  rm -f "$out_file" "$err_file"
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

_dr_check_opencode_agentguard() {
  command -v "${DOT_OPENCODE_COMMAND:-opencode}" >/dev/null 2>&1 || return 0

  local plugin="$HOME/.config/opencode/plugins/dotfiles-agentguard.js"
  local first_line=""

  if [[ ! -e "$plugin" && ! -L "$plugin" ]]; then
    _dr_warn "OpenCode AgentGuard plugin missing" "run 'dot update'"
    return 0
  fi
  if [[ ! -f "$plugin" || -L "$plugin" ]]; then
    _dr_warn "OpenCode AgentGuard plugin unmanaged" "$(_dr_tilde "$plugin")"
    return 0
  fi

  IFS= read -r first_line <"$plugin" || true
  if [[ "$first_line" == "$(dot_agentguard_opencode_marker)" ]]; then
    _dr_ok "OpenCode AgentGuard plugin installed" "$(_dr_tilde "$plugin")"
  else
    _dr_warn "OpenCode AgentGuard plugin unmanaged" "$(_dr_tilde "$plugin")"
  fi
}

_dr_check_grok_agentguard() {
  command -v "${DOT_GROK_COMMAND:-grok}" >/dev/null 2>&1 || return 0

  local hooks="$HOME/.grok/hooks/agentguard.json"

  if [[ -f "$hooks" ]]; then
    _dr_ok "Grok AgentGuard hooks installed" "$(_dr_tilde "$hooks")"
  else
    _dr_warn "Grok AgentGuard hooks missing" "run 'dot update'"
  fi
}

_dr_check_grok_compat() {
  command -v "${DOT_GROK_COMMAND:-grok}" >/dev/null 2>&1 || return 0

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
    _dr_warn "Grok Claude-compat cells missing" "run 'dot update'"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    _dr_warn "Grok Claude-compat cells unverified" "python3 is required"
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
    _dr_warn "Grok Claude-compat discovery still enabled" \
      "run 'dot update'"
  fi
}

_dr_check_agent_hooks() {
  _dr_section "Agent hooks"

  local pre_bash="$HOME/.local/bin/agent-hook-pre-bash"
  local stop_hook="$HOME/.local/bin/agent-hook-stop"

  _dr_check_opencode_agentguard
  _dr_check_grok_agentguard
  _dr_check_grok_compat

  if [[ ! -x "$pre_bash" ]]; then
    _dr_warn "agent pre-bash hook unavailable" "$(_dr_tilde "$pre_bash")"
    return 0
  fi

  # The three smoke probes need three hook executions (two binaries, two
  # pre-bash payloads), so run them as one combined background batch: wall
  # time drops from the sum to roughly the slowest probe. Launch conditions
  # are the same file tests as before, so a missing pre-bash still returns
  # before any hook runs, and results are applied below in the original
  # order, so records are unchanged.
  local results
  local -a probe_pids
  probe_pids=()
  results=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-agent-hooks) || return 1
  _dr_run_agent_hook_async "$results/dot-status" "$pre_bash" '{"tool_input":{"command":"dot status"}}'
  probe_pids+=("$!")
  _dr_run_agent_hook_async "$results/raw-git" "$pre_bash" '{"tool_input":{"command":"git status -uall"}}'
  probe_pids+=("$!")
  if [[ -x "$stop_hook" ]]; then
    _dr_run_agent_hook_async "$results/stop" "$stop_hook" '{}'
    probe_pids+=("$!")
  fi
  # probe_pids always holds at least the two pre-bash probes here. Under
  # `set -e` a failing wait would abort before records publish; the probes
  # report pass/fail through their result files, not through wait.
  wait "${probe_pids[@]}" || true

  if _dr_probe_ok "$results/dot-status"; then
    _dr_ok "agent pre-bash allows dot status"
  else
    _dr_fail "agent pre-bash failed dot status smoke" \
      "${_DR_AGENT_HOOK_STDERR%%$'\n'*}"
  fi

  local raw_git_rc=0
  _dr_probe_ok "$results/raw-git" || raw_git_rc=$?
  if [[ "$raw_git_rc" -eq 0 ]]; then
    if _dr_is_dotfiles_checkout; then
      _dr_ok "agent pre-bash allows raw git status in checkout"
    else
      _dr_fail "agent pre-bash allows raw dotfiles git status" \
        "expected the hook to steer agents to 'dot status'"
    fi
  elif [[ "$raw_git_rc" -eq 2 && "$_DR_AGENT_HOOK_STDERR" == *"dot status"* ]]; then
    _dr_ok "agent pre-bash guards raw dotfiles git status"
  else
    _dr_fail "agent pre-bash raw git smoke returned unexpected result" \
      "${_DR_AGENT_HOOK_STDERR%%$'\n'*}"
  fi

  if [[ -x "$stop_hook" ]]; then
    if _dr_probe_ok "$results/stop"; then
      _dr_ok "agent stop hook runs"
    else
      _dr_fail "agent stop hook failed" "${_DR_AGENT_HOOK_STDERR%%$'\n'*}"
    fi
  else
    _dr_warn "agent stop hook unavailable" "$(_dr_tilde "$stop_hook")"
  fi
  local check_rc=$?
  rm -rf "$results" 2>/dev/null || true
  return "$check_rc"
}
