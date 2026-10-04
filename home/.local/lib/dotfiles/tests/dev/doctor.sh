# shellcheck shell=bash

dot_dev_doctor_test() {
  local result_file current_module sections failures extension_home path
  local doctor_home doctor_bin result drift expected status
  local hm_home hm_bin hm_store hm_healthy hm_old integ_home integ_bin
  local integ_call integ_name integ_emitter integ_dep integ_asset
  local probe_root tooling_home temps_lib temps_saved temps_def temps_log
  local agent_home installed_config installed_config_before installed_doctor_output
  local installed_section fixture_health=false owner_root source_doctor host_doctor
  local grok_compat_path reg_home reg_bin reg_path reg_count python_bin hook
  local hooks_home nvim_dev_home module_path
  local registration_def real_nvim nvim_head marker_def
  local nvim_home nvim_calls started real_home real_bin real_tmp git_log
  local before_snapshot
  local permissive_home no_pre_home no_stop_home multiline_home _checkout_def
  local base_hint_def repro_cmd repro_out
  local -a modules=(
    31-dev-shell-integrations.sh
    32-git-hooks.sh
    40-agent-hooks.sh
    75-nvim-dev.sh
  )

  owner_root=$(_dev_repo_root)
  source_doctor=$owner_root/home/.local/lib/dotfiles/doctor.d
  host_doctor=${DOT_TEST_HOST_HOME:-$HOME}/.local/lib/dotfiles/doctor.d
  extension_home=${DOT_TEST_DOCTOR_EXTENSION_HOME:-}
  [[ -z $extension_home ]] || fixture_health=true
  DOT_DOCTOR_RESULT_FILE=$(_tmpdir)/doctor-results.tsv
  export DOT_DOCTOR_RESULT_FILE
  if [[ -z $extension_home ]]; then
    extension_home=$(_tmpdir)/api-home
    mkdir -p "$extension_home/.local/lib/dotfiles/doctor.d/lib"
    for path in "${modules[@]}"; do
      if [[ -f $source_doctor/$path ]]; then
        cp "$source_doctor/$path" \
          "$extension_home/.local/lib/dotfiles/doctor.d/$path"
      else
        cp "$host_doctor/$path" \
          "$extension_home/.local/lib/dotfiles/doctor.d/$path"
      fi
    done
    # Base-owned doctor helpers are not in this overlay checkout. Seed them
    # from the composed host home, then overlay-owned libs win on name clash.
    for path in "$host_doctor"/lib/*.sh; do
      [[ -f $path ]] || continue
      cp "$path" "$extension_home/.local/lib/dotfiles/doctor.d/lib/${path##*/}"
    done
    for path in "$source_doctor"/lib/*.sh; do
      cp "$path" "$extension_home/.local/lib/dotfiles/doctor.d/lib/${path##*/}"
    done
  fi

  _test_load_dot_doctor_api "$extension_home" || {
    _fail 'Standalone Dot doctor API loads for the dev overlay'
    return
  }
  result_file=$DOT_DOCTOR_RESULT_FILE
  # The hint helper is newer than some Dot releases (and _dr_hint_row newer
  # than some bases) this suite runs against: default to the older API,
  # where each next step joins its row's detail, and opt in per case.
  unset -f dot_doctor_item dot_doctor_hint

  for current_module in "${modules[@]}"; do
    unset -f doctor 2>/dev/null || true
    if ! dot_doctor_source "doctor.d/$current_module"; then
      _fail "Doctor wrapper loads through the public API: $current_module"
      continue
    fi
    if declare -F doctor >/dev/null; then
      doctor
      _pass "Doctor wrapper runs through the public API: $current_module"
    else
      _fail "Doctor wrapper exports its entry point: $current_module"
    fi
  done

  sections=$(awk -F '\t' '$1 == "section" { count++ } END { print count+0 }' "$result_file")
  failures=$(awk -F '\t' '$1 == "fail" { count++ } END { print count+0 }' "$result_file")
  _assert_eq 'All four dev doctor wrappers publish a section' 4 "$sections"
  _assert_not_contains 'Dev doctor publishes no hand-picked Development tools section' \
    $'section\tDevelopment tools' "$(<"$result_file")"
  if $fixture_health; then
    _assert_eq 'Dev doctor wrappers publish no failures in the fixture' 0 "$failures"
  fi

  _doctor_records() {
    local status=0
    : >"$result_file"
    "$@" || status=$?
    # Builtin read: some checks run under a fixture PATH without coreutils.
    printf '%s\n' "$(<"$result_file")"
    return "$status"
  }

  # _dr_dev_row: base's _dr_hint_row when the base has it; otherwise the
  # same rule here, for an older base. Asserts run in this shell so they
  # count; the base helper is set aside and restored around the cases.
  base_hint_def=$(declare -f _dr_hint_row 2>/dev/null || true)
  unset -f _dr_hint_row
  result=$(_doctor_records _dr_dev_row warn 'row' 'the cause' 'do this')
  _assert_eq 'Dev row without base helper or hint API joins the step' \
    $'warn\trow\tthe cause; do this' "$result"
  result=$(_doctor_records _dr_dev_row fail 'row' '' 'do this')
  _assert_eq 'Dev row with only a step makes it the detail' $'fail\trow\tdo this' "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the helper under test.
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    _doctor_records _dr_dev_row warn 'row' $'the\tcause' 'do this'
  )
  _assert_eq 'Dev row without base helper uses the hint API when present' \
    "$(printf '%s\n' $'warn\trow\tthe cause' $'hint\tdo this\t')" "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the helper under test.
    _dr_hint_row() { printf 'base\t%s\n' "$*" >>"$result_file"; }
    _doctor_records _dr_dev_row warn 'row' 'the cause' 'do this'
  )
  _assert_eq 'Dev row defers to base _dr_hint_row' \
    $'base\twarn row the cause do this' "$result"
  status=0
  _dr_dev_row warn 'row' 'detail' 2>/dev/null || status=$?
  _assert_eq 'Dev row refuses a missing hint argument, as base does' 2 "$status"
  status=0
  _dr_dev_row bogus 'row' '' '' 2>/dev/null || status=$?
  _assert_eq 'Dev row refuses an unknown level, as base does' 2 "$status"
  [[ -z $base_hint_def ]] || eval "$base_hint_def"

  doctor_home=$(_tmpdir)
  doctor_bin=$(_mock_bin)
  mkdir -p "$doctor_home/.local/bin"

  # AgentGuard registration table: one row per installed agent. The fixture
  # PATH holds only the agent stubs, the hook commands, and a counting python3
  # wrapper, so host-installed agents never leak into the result.
  # The interpreter itself, not a shim: shims need tools the fixture PATH
  # deliberately omits.
  python_bin=$(python3 -c 'import sys; print(sys.executable)')
  reg_home=$(_tmpdir)
  reg_bin=$(_mock_bin)
  mkdir -p "$reg_home/.local/bin"
  cat >"$reg_bin/python3" <<SH
#!/bin/sh
printf 'x\n' >>"$reg_home/python-calls"
exec "$python_bin" "\$@"
SH
  chmod +x "$reg_bin/python3"
  for hook in agent-hook-pre-bash agent-hook-stop; do
    printf '#!/bin/sh\nexit 0\n' >"$reg_home/.local/bin/$hook"
    chmod +x "$reg_home/.local/bin/$hook"
  done
  reg_path="$reg_home/.local/bin:$reg_bin"
  _reg_records() {
    HOME="$reg_home" PATH="$reg_path" _doctor_records _dr_check_agentguard_registrations
  }
  _reg_agent() {
    printf '#!/bin/sh\nexit 0\n' >"$reg_bin/$1"
    chmod +x "$reg_bin/$1"
  }
  _reg_hooks_json() {
    mkdir -p "${1%/*}"
    cat >"$1" <<'JSON'
{"model": "x", "hooks": {
  "PreToolUse": [{"matcher": "Bash", "hooks": [
    {"type": "command", "command": "env -u BASH_ENV AGENTGUARD_NAME=a agent-hook-pre-bash"}]}],
  "Stop": [{"hooks": [
    {"type": "command", "command": "env AGENTGUARD_NAME=a agent-hook-stop"},
    {"type": "command", "command": "my-own-stop-hook"}]}]}}
JSON
  }

  result=$(_reg_records)
  _assert_not_contains 'Registration table skips agents that are not installed' \
    'AgentGuard' "$result"

  _reg_agent claude
  result=$(_reg_records)
  _assert_contains 'Registration table warns when an installed agent has no config' \
    $'warn\tClaude Code AgentGuard hooks missing\t~/.claude/settings.json' "$result"
  _reg_hooks_json "$reg_home/.claude/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table accepts registered, executable hook commands' \
    $'ok\tClaude Code AgentGuard hooks\t2 command(s) in ~/.claude/settings.json' "$result"
  printf '{"hooks": {"Stop": [{"hooks": [{"command": "my-own-stop-hook"}]}]}}\n' \
    >"$reg_home/.claude/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table warns when a config registers no AgentGuard hooks' \
    $'warn\tClaude Code AgentGuard hooks missing\tno agent-hook-* commands' "$result"
  printf '{"hooks": {"Stop": [}\n' >"$reg_home/.claude/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table fails a config that does not parse' \
    $'fail\tClaude Code AgentGuard config invalid\t~/.claude/settings.json: ' "$result"
  printf '[]\n' >"$reg_home/.claude/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table fails a config whose top level is not an object' \
    $'fail\tClaude Code AgentGuard config invalid' "$result"
  printf '{"hooks": {"PreToolUse": [{"hooks": [{"command": "agent-hook-pre-bash"}, {"command": "agent-hook-pre-edit"}, {"command": "agent-hook-pre-mcp"}]}]}}\n' \
    >"$reg_home/.claude/settings.json"
  printf '#!/bin/sh\nexit 0\n' >"$reg_home/.local/bin/agent-hook-pre-mcp"
  result=$(_reg_records)
  _assert_contains 'Registration table fails when a referenced hook command is missing' \
    $'fail\tClaude Code AgentGuard hook commands missing\tnot executable on PATH or in ~/.local/bin: agent-hook-pre-edit agent-hook-pre-mcp' \
    "$result"
  rm -f "$reg_home/.local/bin/agent-hook-pre-mcp"
  printf '{"hooks": {"Stop": [{"hooks": [{"command": "agent-hook-pre-bash"}, {"command": "agent-hook-stop"}, {"command": "/opt/own/agent-hook-custom"}]}]}}\n' \
    >"$reg_home/.claude/settings.json"
  result=$(HOME="$reg_home" PATH="$reg_bin" \
    _doctor_records _dr_check_agentguard_registrations)
  _assert_contains 'Registration table finds hook commands in ~/.local/bin off PATH' \
    $'ok\tClaude Code AgentGuard hooks\t2 command(s)' "$result"
  _assert_not_contains 'Registration table ignores hooks configured by absolute path' \
    'agent-hook-custom' "$result"
  # A dangling config link reads as missing, as the merge hooks treat it.
  mv "$reg_home/.claude/settings.json" "$reg_home/settings.json"
  ln -s "$reg_home/gone.json" "$reg_home/.claude/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table reports a dangling config link as missing' \
    $'warn\tClaude Code AgentGuard hooks missing\t~/.claude/settings.json is a broken link' \
    "$result"
  rm "$reg_home/.claude/settings.json"
  mv "$reg_home/settings.json" "$reg_home/.claude/settings.json"
  # Partial registration: lifecycle hooks without the pre-bash guard.
  printf '{"hooks": {"Stop": [{"hooks": [{"command": "agent-hook-stop"}]}]}}\n' \
    >"$reg_home/.claude/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table warns when the pre-bash guard is not registered' \
    $'warn\tClaude Code AgentGuard pre-bash guard not registered' "$result"
  _reg_hooks_json "$reg_home/.claude/settings.json"
  sed 's/{"model": "x",/{"disableAllHooks": true,/' "$reg_home/.claude/settings.json" \
    >"$reg_home/settings.json"
  mv "$reg_home/settings.json" "$reg_home/.claude/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table warns when the runtime disables every hook' \
    $'warn\tClaude Code AgentGuard hooks disabled\tdisableAllHooks is true in ~/.claude/settings.json' \
    "$result"
  _reg_hooks_json "$reg_home/.claude/settings.json"
  result=$(HOME="$reg_home" PATH="$reg_home/.local/bin" \
    _doctor_records _dr_check_agentguard_registrations)
  _assert_eq 'Registration table skips agents without their command on PATH' \
    '' "$result"
  # Inspector failures degrade to one warning instead of misattributed rows.
  mkdir -p "$reg_home/no-python"
  ln -s "$reg_bin/claude" "$reg_home/no-python/claude"
  result=$(HOME="$reg_home" PATH="$reg_home/no-python" \
    _doctor_records _dr_check_agentguard_registrations)
  _assert_contains 'Registration table warns when python3 is unavailable' \
    $'warn\tClaude Code AgentGuard hooks unchecked\tpython3 is required' "$result"
  printf '#!/bin/sh\nexit 3\n' >"$reg_home/no-python/python3"
  chmod +x "$reg_home/no-python/python3"
  result=$(HOME="$reg_home" PATH="$reg_home/no-python" \
    _doctor_records _dr_check_agentguard_registrations)
  _assert_contains 'Registration table reports an inspector crash once' \
    $'warn\tAgentGuard hook registration unchecked\tpython3 exited 3' "$result"
  printf '#!/bin/sh\nwhile read -r _; do :; done\nexit 0\n' >"$reg_home/no-python/python3"
  result=$(HOME="$reg_home" PATH="$reg_home/no-python:$reg_bin" \
    _doctor_records _dr_check_agentguard_registrations)
  _assert_contains 'Registration table rejects inspector output it cannot attribute' \
    $'warn\tAgentGuard hook registration unchecked\tunexpected inspector output' "$result"
  rm -rf "$reg_home/no-python"
  rm -f "$reg_bin/claude"

  # Every other runtime the merge hooks register, at the path its hook writes.
  _reg_agent codex
  _reg_agent muse
  _reg_agent gemini
  _reg_agent grok
  mkdir -p "$reg_home/.codex"
  cat >"$reg_home/.codex/config.toml" <<'TOML'
model = "x"
[[hooks.PreToolUse]]
matcher = "Bash"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "env AGENTGUARD_NAME=codex agent-hook-pre-bash"
TOML
  _reg_hooks_json "$reg_home/.config/muse/settings.json"
  _reg_hooks_json "$reg_home/.gemini/settings.json"
  result=$(_reg_records)
  _assert_contains 'Registration table checks Codex TOML hooks' \
    $'ok\tCodex AgentGuard hooks\t1 command(s) in ~/.codex/config.toml' "$result"
  _assert_contains 'Registration table checks Muse settings' \
    $'ok\tMuse AgentGuard hooks\t2 command(s) in ~/.config/muse/settings.json' "$result"
  _assert_contains 'Registration table checks Gemini settings' \
    $'ok\tGemini CLI AgentGuard hooks\t2 command(s) in ~/.gemini/settings.json' "$result"
  _assert_contains 'Registration table warns when the Grok hooks fragment is absent' \
    $'warn\tGrok AgentGuard hooks missing\t~/.grok/hooks/agentguard.json' "$result"
  _reg_hooks_json "$reg_home/.grok/hooks/agentguard.json"
  : >"$reg_home/python-calls"
  result=$(_reg_records)
  _assert_contains 'Registration table checks the Grok hooks fragment' \
    $'ok\tGrok AgentGuard hooks\t2 command(s) in ~/.grok/hooks/agentguard.json' "$result"
  reg_count=$(wc -l <"$reg_home/python-calls")
  _assert_eq 'Registration table inspects every installed agent in one python3 process' \
    1 "${reg_count//[[:space:]]/}"
  # Holds with or without tomllib: the fallback line-matches this switch.
  printf '[features]\nhooks = false\n' >>"$reg_home/.codex/config.toml"
  result=$(_reg_records)
  _assert_contains 'Registration table warns when Codex hooks are switched off' \
    $'warn\tCodex AgentGuard hooks disabled\tfeatures.hooks is false in ~/.codex/config.toml' \
    "$result"
  if "$python_bin" -c 'import tomllib' 2>/dev/null; then
    printf '[[hooks.PreToolUse]\n' >"$reg_home/.codex/config.toml"
    result=$(_reg_records)
    _assert_contains 'Registration table fails Codex TOML that does not parse' \
      $'fail\tCodex AgentGuard config invalid\t~/.codex/config.toml: ' "$result"
    _assert_contains 'One invalid config does not hide the other agents' \
      $'ok\tGemini CLI AgentGuard hooks' "$result"
  else
    _pass 'Registration table TOML syntax check needs Python 3.11 tomllib (skipped)'
  fi
  # Simulate a Python without tomllib (3.9 on CentOS Stream 9, macOS CLT):
  # only `command =` assignments count, never comments.
  cat >"$reg_home/no-tomllib-python3" <<SH
#!/bin/sh
# Drop the inspector's "-I -" and replay its stdin program with tomllib
# blocked, which makes "import tomllib" raise ImportError.
shift 2
exec "$python_bin" -I -c 'import sys; sys.modules["tomllib"] = None; exec(compile(sys.stdin.read(), "<stdin>", "exec"), {"__name__": "__main__"})' "\$@"
SH
  chmod +x "$reg_home/no-tomllib-python3"
  cat >"$reg_home/.codex/config.toml" <<'TOML'
# agent-hook-pre-search is mentioned only in this comment
[[hooks.PreToolUse.hooks]]
command = "env AGENTGUARD_NAME=codex agent-hook-pre-bash" # not agent-hook-pre-edit
TOML
  mv "$reg_bin/python3" "$reg_bin/python3.counting"
  cp "$reg_home/no-tomllib-python3" "$reg_bin/python3"
  result=$(_reg_records)
  mv "$reg_bin/python3.counting" "$reg_bin/python3"
  _assert_contains 'Registration table reads Codex commands without tomllib' \
    $'ok\tCodex AgentGuard hooks\t1 command(s) in ~/.codex/config.toml; TOML syntax unchecked' \
    "$result"
  # Without tomllib the hooks switch is still read, in both plain forms, and
  # an enabled switch or another table's `hooks` key does not trip it.
  _reg_no_tomllib() {
    mv "$reg_bin/python3" "$reg_bin/python3.counting"
    cp "$reg_home/no-tomllib-python3" "$reg_bin/python3"
    _reg_records
    mv "$reg_bin/python3.counting" "$reg_bin/python3"
  }
  printf '[features]\nhooks = false # off for now\n' >>"$reg_home/.codex/config.toml"
  result=$(_reg_no_tomllib)
  _assert_contains 'Registration table reads [features] hooks = false without tomllib' \
    $'warn\tCodex AgentGuard hooks disabled\tfeatures.hooks is false in ~/.codex/config.toml' \
    "$result"
  printf 'features.hooks = false\n[[hooks.PreToolUse.hooks]]\ncommand = "agent-hook-pre-bash"\n' \
    >"$reg_home/.codex/config.toml"
  result=$(_reg_no_tomllib)
  _assert_contains 'Registration table reads dotted features.hooks = false without tomllib' \
    $'warn\tCodex AgentGuard hooks disabled' "$result"
  printf '[features]\nhooks = true\n[other]\nhooks = false\n[features]\n[[mcp.x]]\nhooks = false\n[[hooks.PreToolUse.hooks]]\ncommand = "agent-hook-pre-bash"\n' \
    >"$reg_home/.codex/config.toml"
  result=$(_reg_no_tomllib)
  _assert_contains 'Registration table ignores enabled or unrelated hooks keys without tomllib' \
    $'ok\tCodex AgentGuard hooks\t1 command(s)' "$result"
  rm -f "$reg_bin/codex" "$reg_bin/muse" "$reg_bin/gemini" "$reg_bin/grok"

  _reg_agent opencode
  result=$(_reg_records)
  _assert_contains 'Registration table warns when the OpenCode plugin is absent' \
    $'warn\tOpenCode AgentGuard hooks missing' "$result"
  mkdir -p "$reg_home/.config/opencode/plugins"
  printf '%s\n' 'export const userOwned = "agent-hook-stop"' \
    >"$reg_home/.config/opencode/plugins/dotfiles-agentguard.js"
  result=$(_reg_records)
  _assert_contains 'Registration table preserves an unmanaged OpenCode plugin' \
    $'warn\tOpenCode AgentGuard plugin unmanaged' "$result"
  cat >"$reg_home/.config/opencode/plugins/dotfiles-agentguard.js" <<'PLUGIN'
// agentguard-managed:opencode-plugin
const TIMEOUTS = new Map([["agent-hook-pre-bash", 600_000]]);
const hook = (phase, kind) => `agent-hook-${phase}-${kind}`;
// A comment naming agent-hook-pre-search is not a registration.
export const AgentGuardPlugin = async () => run("agent-hook-stop");
PLUGIN
  result=$(_reg_records)
  _assert_contains 'Registration table checks the managed OpenCode plugin commands' \
    $'ok\tOpenCode AgentGuard hooks\t2 command(s) in ~/.config/opencode/plugins/dotfiles-agentguard.js' \
    "$result"
  mv "$reg_home/.config/opencode/plugins/dotfiles-agentguard.js" "$reg_home/plugin.js"
  ln -s "$reg_home/plugin.js" "$reg_home/.config/opencode/plugins/dotfiles-agentguard.js"
  result=$(_reg_records)
  _assert_contains 'Registration table treats a symlinked OpenCode plugin as unmanaged' \
    $'warn\tOpenCode AgentGuard plugin unmanaged' "$result"
  rm "$reg_home/.config/opencode/plugins/dotfiles-agentguard.js"
  mv "$reg_home/plugin.js" "$reg_home/.config/opencode/plugins/dotfiles-agentguard.js"
  marker_def=$(declare -f dot_agentguard_opencode_marker || true)
  unset -f dot_agentguard_opencode_marker
  result=$(_reg_records)
  [[ -z $marker_def ]] || eval "$marker_def"
  _assert_contains 'Registration table says so when base lacks the plugin marker helper' \
    $'warn\tOpenCode AgentGuard plugin unchecked\tbase lacks dot_agentguard_opencode_marker' \
    "$result"
  rm -f "$reg_bin/opencode"

  printf '#!/usr/bin/env bash\nexit 0\n' >"$doctor_bin/grok"
  chmod +x "$doctor_bin/grok"
  grok_compat_path="$doctor_bin:/usr/bin:/bin"
  # The gate is `grok` on PATH, as for the registration table and the merge
  # hooks; the retired DOT_GROK_COMMAND override no longer moves it.
  mkdir -p "$doctor_home/.grok/hooks" "$doctor_home/.grok/rules"
  printf '{"hooks":{}}\n' >"$doctor_home/.grok/hooks/agentguard.json"
  printf '# grok rules\n' >"$doctor_home/.grok/rules/agent-rules.md"
  result=$(HOME="$doctor_home" PATH="$doctor_bin:/usr/bin:/bin" \
    DOT_GROK_COMMAND=missing-grok-binary \
    _doctor_records _dr_check_grok_compat)
  _assert_contains 'Doctor gates Grok Claude-compat on grok, not DOT_GROK_COMMAND' \
    'Grok Claude-compat cells missing' "$result"
  mv "$doctor_bin/grok" "$doctor_bin/grok-renamed"
  result=$(HOME="$doctor_home" PATH="$doctor_bin:/usr/bin:/bin" \
    DOT_GROK_COMMAND=grok-renamed \
    _doctor_records _dr_check_grok_compat)
  mv "$doctor_bin/grok-renamed" "$doctor_bin/grok"
  _assert_not_contains 'Doctor skips Grok Claude-compat when grok is absent' \
    'Grok Claude-compat' "$result"
  rm -rf "$doctor_home/.grok"
  result=$(HOME="$doctor_home" PATH="$grok_compat_path" \
    _doctor_records _dr_check_grok_compat)
  _assert_not_contains \
    'Doctor skips Grok Claude-compat when native replacements are absent' \
    'Grok Claude-compat' "$result"
  mkdir -p "$doctor_home/.grok/hooks" "$doctor_home/.grok/rules"
  printf '{"hooks":{}}\n' >"$doctor_home/.grok/hooks/agentguard.json"
  printf '# grok rules\n' >"$doctor_home/.grok/rules/agent-rules.md"
  result=$(HOME="$doctor_home" PATH="$grok_compat_path" \
    _doctor_records _dr_check_grok_compat)
  _assert_contains 'Doctor warns when Grok Claude-compat cells are absent' \
    $'warn\tGrok Claude-compat cells missing' "$result"
  cat >"$doctor_home/.grok/config.toml" <<'TOML'
[compat.claude]
hooks = true
rules = true
agents = true
TOML
  result=$(HOME="$doctor_home" PATH="$grok_compat_path" \
    _doctor_records _dr_check_grok_compat)
  _assert_contains 'Doctor warns when Grok Claude-compat cells stay enabled' \
    $'warn\tGrok Claude-compat discovery still enabled' "$result"
  cat >"$doctor_home/.grok/config.toml" <<'TOML'
[compat.claude]
hooks = false
rules = true
agents = true
skills = false
mcps = false
TOML
  result=$(HOME="$doctor_home" PATH="$grok_compat_path" \
    _doctor_records _dr_check_grok_compat)
  _assert_contains 'Doctor warns when Grok Claude-compat cells are only partly disabled' \
    $'warn\tGrok Claude-compat discovery still enabled' "$result"
  cat >"$doctor_home/.grok/config.toml" <<'TOML'
[compat.claude]
hooks = false
rules = false
agents = false
skills = true
mcps = true
TOML
  result=$(HOME="$doctor_home" PATH="$grok_compat_path" \
    _doctor_records _dr_check_grok_compat)
  _assert_contains 'Doctor accepts Claude skills and MCPs while hooks/rules/agents are off' \
    $'ok\tGrok disables Claude-compat discovery' "$result"
  rm -f "$doctor_bin/grok"

  drift=$(_dr_lsp_policy_diff 'bashls neocmake vtsls' 'bashls neocmake vtsls')
  expected=$(printf 'missing=\nstale=')
  _assert_eq 'Doctor reports no LSP policy drift for equal sets' "$expected" "$drift"
  drift=$(_dr_lsp_policy_diff 'bashls neocmake pyright vtsls' 'bashls jsonls neocmake')
  expected=$(printf 'missing=pyright,vtsls\nstale=jsonls')
  _assert_eq 'Doctor sorts missing and stale LSP policy entries' "$expected" "$drift"
  _assert_eq 'Doctor parser preserves the first matching second field' alpha \
    "$(_dr_dev_value enabled $'noise\nenabled=alpha=diagnostic\nenabled=second')"
  _assert_eq 'Doctor parser returns empty for an absent key' '' \
    "$(_dr_dev_value covered $'noise\nenabled=bashls')"

  # The LSP policy query is a bounded probe: results come back through a
  # file, never Neovim's stdout. Stubs below answer through that file.
  #
  # The probe skips without timeout(1), and CI's controlled PATH (test/run)
  # has none, nor does macOS without coreutils. So probe tests bring their
  # own: stub tests use this shim, which really enforces the deadline, so they
  # behave the same everywhere; the real-Neovim test prefers the platform's
  # own timeout/gtimeout (BusyBox on Alpine) so its flags are exercised too.
  _timeout_shim() {
    cat >"$1/timeout" <<'SH'
#!/usr/bin/env bash
# Test stand-in for timeout(1): `timeout [-k KILL_AFTER] DURATION CMD...`.
# Job control gives CMD and the watcher their own process groups, so the
# deadline signals CMD's whole group, as GNU timeout does, and the watcher
# (with its sleep) is reaped as a group once CMD finishes first.
# Identify as coreutils: doctor bounded runners only trust a timeout whose
# status 124 means the deadline, and this shim keeps that contract.
if [[ ${1:-} == --version ]]; then
  printf 'timeout (GNU coreutils) test shim\n'
  exit 0
fi
kill_after=1
if [[ ${1:-} == -k ]]; then
  kill_after=$2
  shift 2
fi
duration=$1
shift
started=$SECONDS
# Under job control Bash reports a finished or killed job ("[2]+
# Terminated ...") on its own stderr, which is CMD's stderr as the caller
# captures it. Only CMD gets the caller's stderr (fd 3); the shim's own goes
# to /dev/null, as a real timeout(1) adds nothing to CMD's output.
exec 3>&2 2>/dev/null
set -m
"$@" 2>&3 3>&- &
cmd=$!
(
  sleep "$duration"
  kill -TERM -- "-$cmd" 2>/dev/null || exit 0
  sleep "$kill_after"
  kill -KILL -- "-$cmd" 2>/dev/null
) 3>&- &
watcher=$!
status=0
wait "$cmd" 2>/dev/null || status=$?
kill -TERM -- "-$watcher" 2>/dev/null
wait "$watcher" 2>/dev/null
# A signal death at or past the deadline is the deadline's doing.
if ((status > 128 && SECONDS - started >= duration)); then
  exit 124
fi
exit "$status"
SH
    chmod +x "$1/timeout"
  }
  _system_timeout() {
    local candidate
    for candidate in /usr/bin/timeout /bin/timeout \
      /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout \
      ${PREFIX:+"$PREFIX/bin/timeout"}; do
      [[ -x $candidate && ! -d $candidate ]] || continue
      ln -s "$candidate" "$1/${candidate##*/}"
      return 0
    done
    _timeout_shim "$1"
  }
  _timeout_shim "$doctor_bin"
  # Bounded runners resolve their timeout command once per worker. Deadline
  # cases run in a fresh resolution so they find this shim even when an
  # earlier check resolved under a PATH without it (CI has no timeout).
  _fresh_deadline() {
    unset _DR_DEV_TIMEOUT_BIN _DR_TIMEOUT_BIN
    "$@"
  }
  expected=
  for status in 124 137 0 1; do
    if _dr_dev_deadline_status "$status"; then expected+=y; else expected+=n; fi
  done
  _assert_eq 'A deadline status is 124 or 137' yynn "$expected"
  # Without base's runner, only a coreutils timeout bounds a run: BusyBox's
  # rejects -k on older releases.
  mkdir -p "$doctor_home/busybox-timeout"
  cat >"$doctor_home/busybox-timeout/timeout" <<SH
#!/bin/sh
[ "\$1" = --version ] && { echo 'BusyBox v1.36.1'; exit 0; }
echo used >>"$doctor_home/busybox-calls"
exit 2
SH
  chmod +x "$doctor_home/busybox-timeout/timeout"
  result=$(
    unset -f _dr_run_bounded
    unset _DR_DEV_TIMEOUT_BIN
    PATH="$doctor_home/busybox-timeout:$PATH" _dr_dev_bounded 5 printf ran
  )
  _assert_eq 'The fallback runner passes over a BusyBox timeout' ran "$result"
  _assert_eq 'The fallback runner never calls a BusyBox timeout' absent \
    "$([[ -e $doctor_home/busybox-calls ]] && printf present || printf absent)"
  started=$SECONDS
  status=0
  (
    unset -f _dr_run_bounded
    unset _DR_DEV_TIMEOUT_BIN
    PATH="$doctor_bin:$PATH" _dr_dev_bounded 1 sleep 30
  ) || status=$?
  _assert_eq 'The fallback runner bounds a run with a coreutils timeout' 124 "$status"
  _assert_eq 'The fallback runner returns within its deadline' yes \
    "$( ((SECONDS - started < 10)) && printf yes || printf no)"
  # A bounded runner must add nothing to the command's stderr: the hook
  # probes report the first stderr line as the hook's own message. Job
  # notices from a watcher are racy, so repeat a fast, silent failure.
  _bounded_stderr() {
    local i err
    for ((i = 0; i < 100; i++)); do
      err=$("$@" sh -c 'exit 6' 2>&1 >/dev/null) || true
      [[ -z $err ]] || {
        printf '%s' "$err"
        return 0
      }
    done
  }
  _assert_eq 'The timeout test shim adds nothing to stderr' '' \
    "$(_bounded_stderr "$doctor_bin/timeout" 5)"
  _assert_eq 'The fallback runner adds nothing to stderr' '' \
    "$(
      unset -f _dr_run_bounded
      unset _DR_DEV_TIMEOUT_BIN
      PATH="$doctor_bin:$PATH" _bounded_stderr _dr_dev_bounded 5
    )"
  if declare -F _dr_run_bounded >/dev/null; then
    _assert_eq "Base's bounded runner adds nothing to stderr" '' \
      "$(PATH="$doctor_bin:$PATH" _fresh_deadline _bounded_stderr _dr_dev_bounded 5)"
    _assert_eq "Base's builtin watchdog adds nothing to stderr" '' \
      "$(
        _DR_TIMEOUT_BIN=
        _bounded_stderr _dr_dev_bounded 5
      )"
  else
    _pass "Base's bounded runner stderr check needs _dr_run_bounded (skipped)"
  fi
  nvim_home=$(_tmpdir)
  mkdir -p "$nvim_home/.local/share/nvim/lazy/lazy.nvim"
  nvim_calls=$(_tmpdir)/nvim-calls
  _nvim_policy() {
    HOME="$nvim_home" XDG_DATA_HOME="$nvim_home/.local/share" \
      PATH="$doctor_bin:$PATH" _doctor_records _dr_check_nvim_lsp_policy
  }
  cat >"$doctor_bin/nvim" <<'NVIM'
#!/usr/bin/env bash
printf 'enabled=bashls pyright\ncovered=bashls\ndot_doctor_query=complete\n' \
  >"$DOT_NVIM_PROBE_RESULT"
python3 - <<'PY'
print('diagnostic=' + ('x' * 262144))
PY
NVIM
  chmod +x "$doctor_bin/nvim"
  : >"$result_file"
  set +e
  (
    set -euo pipefail
    HOME="$nvim_home" XDG_DATA_HOME="$nvim_home/.local/share" \
      PATH="$doctor_bin:$PATH" _dr_check_nvim_lsp_policy
  ) 2>"$nvim_home/nvim-policy-stderr"
  status=$?
  set -e
  _assert_eq 'Doctor runs the LSP policy probe under the worker shell policy' 0 "$status"
  result=$(<"$result_file")
  _assert_contains 'Doctor reports parsed drift from the probe result file' \
    'missing fallback policy for enabled server(s): pyright' "$result"

  # A crash that leaves no result must not read as two matching (empty)
  # server lists.
  cat >"$doctor_bin/nvim" <<'NVIM'
#!/usr/bin/env bash
printf 'E5113: Lua chunk: module config.mason-policy not found\n' >&2
exit 0
NVIM
  chmod +x "$doctor_bin/nvim"
  result=$(_nvim_policy)
  _assert_contains 'Doctor does not report a crashed LSP policy query as in sync' \
    $'warn\tnvim LSP fallback policy check failed\tnvim exited with status 0: E5113: Lua chunk' \
    "$result"
  _assert_not_contains 'Doctor withholds the in-sync row without the query sentinel' \
    'in sync' "$result"
  cat >"$doctor_bin/nvim" <<'NVIM'
#!/usr/bin/env bash
printf 'dot_doctor_error=lua: bad = value\n' >"$DOT_NVIM_PROBE_RESULT"
NVIM
  result=$(_nvim_policy)
  _assert_contains 'Doctor reports the LSP policy query error in one line' \
    $'warn\tnvim LSP fallback policy check failed\tlua: bad = value' "$result"

  # Bounded: a Neovim that never answers costs the deadline, not doctor.
  cat >"$doctor_bin/nvim" <<'NVIM'
#!/usr/bin/env bash
exec sleep 30
NVIM
  started=$SECONDS
  result=$(_DR_DEV_NVIM_PROBE_TIMEOUT=1 _nvim_policy)
  _assert_contains 'Doctor bounds a hung LSP policy query' \
    $'warn\tnvim LSP fallback policy check timed out\tno result within 1s' "$result"
  _assert_eq 'Doctor returns within the probe deadline' yes \
    "$( ((SECONDS - started < 10)) && printf yes || printf no)"

  # Stat-level skips never start Neovim at all.
  cat >"$doctor_bin/nvim" <<NVIM
#!/usr/bin/env bash
printf 'called\n' >>"$nvim_calls"
NVIM
  : >"$nvim_calls"
  mkdir -p "$nvim_home/.local/share/nvim/lazy"
  : >"$nvim_home/.local/share/nvim/lazy/lazy.nvim.update.lock"
  result=$(_nvim_policy)
  _assert_contains 'Doctor skips the LSP policy query while a Lazy update runs' \
    $'skip\tnvim LSP fallback policy\ta Lazy plugin update is running' "$result"
  touch -t 200001010000 "$nvim_home/.local/share/nvim/lazy/lazy.nvim.update.lock"
  result=$(_nvim_policy)
  _assert_contains 'Doctor names a stale Lazy update lock as the skip reason' \
    $'skip\tnvim LSP fallback policy\tstale Lazy update lock' "$result"
  rm "$nvim_home/.local/share/nvim/lazy/lazy.nvim.update.lock"
  rmdir "$nvim_home/.local/share/nvim/lazy/lazy.nvim"
  result=$(_nvim_policy)
  _assert_contains 'Doctor skips the LSP policy query without lazy.nvim' \
    $'skip\tnvim LSP fallback policy\tlazy.nvim is not installed' "$result"
  _assert_eq 'Doctor never starts Neovim for a skipped LSP policy query' '' "$(<"$nvim_calls")"
  # Everything the probe and the stub need except timeout(1), so a regression
  # that ran user config without a deadline would actually log a call.
  mkdir -p "$nvim_home/no-timeout-bin"
  for hook in bash env mktemp mkdir rm cat; do
    ln -s "$(type -P "$hook")" "$nvim_home/no-timeout-bin/$hook"
  done
  cp "$doctor_bin/nvim" "$nvim_home/no-timeout-bin/nvim"
  mkdir -p "$nvim_home/.local/share/nvim/lazy/lazy.nvim"
  result=$(HOME="$nvim_home" XDG_DATA_HOME="$nvim_home/.local/share" \
    PATH="$nvim_home/no-timeout-bin" _doctor_records _dr_check_nvim_lsp_policy)
  _assert_contains 'Doctor skips the LSP policy query without a timeout command' \
    $'skip\tnvim LSP fallback policy\ttimeout command not available' "$result"
  _assert_eq 'Doctor never runs user config without a deadline' '' "$(<"$nvim_calls")"

  # Real Neovim (not the dotfiles launcher) on a fixture config: the query
  # must answer, leave the fixture HOME byte-for-byte unchanged, and never
  # reach the network.
  real_nvim=${DOT_TEST_HOST_HOME:-$HOME}/.local/share/neovim/neovim/bin/nvim
  if [[ ! -x $real_nvim ]]; then
    real_nvim=$(type -P nvim || true)
    nvim_head=
    [[ -z $real_nvim ]] || IFS= read -r -n 2 nvim_head <"$real_nvim" || true
    [[ $nvim_head != '#!' ]] || real_nvim=
  fi
  # The fixture config calls vim.loader, which Nvim before 0.9 lacks, so an
  # unsupported editor (CentOS EPEL ships 0.8) would fail for that reason
  # alone; test/run decides support once, from the same minimum as nvim-dev.
  if [[ -n $real_nvim && ${DOT_TEST_NVIM_SUPPORTED:-true} != true ]]; then
    _pass 'Real Nvim LSP policy query needs Neovim 0.11.2 or newer (skipped)'
  elif [[ -n $real_nvim ]]; then
    real_home=$(_tmpdir)
    real_bin=$(_tmpdir)
    real_tmp=$(_tmpdir)
    git_log=$(_tmpdir)/git-calls
    ln -s "$real_nvim" "$real_bin/nvim"
    _system_timeout "$real_bin"
    cat >"$real_bin/git" <<SH
#!/bin/sh
printf '%s|%s\n' "\${GIT_ALLOW_PROTOCOL-unset}" "\$*" >>"$git_log"
exit 128
SH
    chmod +x "$real_bin/git"
    mkdir -p "$real_home/.config/nvim/lua/config" \
      "$real_home/.local/share/nvim/lazy/lazy.nvim/lua/lazy" \
      "$real_home/.local/share/nvim/lazy/lazy.nvim/lua/lazyvim" \
      "$real_home/.local/state" "$real_home/.cache"
    # Shaped like the editor overlay's config.lazy: bytecode caching on, and
    # a bootstrap clone unless plugin installs are disabled.
    cat >"$real_home/.config/nvim/init.lua" <<'LUA'
vim.loader.enable()
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.g.plugin_install_disabled then
  vim.fn.system({ "git", "clone", "https://github.com/folke/lazy.nvim.git", lazypath })
end
if vim.env.DOCTOR_CONFIG_FETCHES == "1" then
  vim.fn.system({ "git", "fetch", "https://github.com/folke/lazy.nvim.git" })
end
vim.opt.rtp:prepend(lazypath)
LUA
    printf '%s\n' 'return { lsp_server_packages = function() return { bashls = "bash-language-server" } end }' \
      >"$real_home/.config/nvim/lua/config/mason-policy.lua"
    printf '%s\n' 'return { load = function() end }' \
      >"$real_home/.local/share/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
    printf '%s\n' 'return { opts = function() return { servers = { bashls = {}, ["*"] = {} } } end }' \
      >"$real_home/.local/share/nvim/lazy/lazy.nvim/lua/lazyvim/util.lua"
    _real_home_snapshot() (
      shopt -s globstar dotglob nullglob
      for entry in "$real_home"/**; do
        printf '%s %s\n' "$entry" "$(stat -c '%s %Y' "$entry" 2>/dev/null || stat -f '%z %m' "$entry")"
      done
    )
    _real_policy() {
      HOME="$real_home" XDG_CONFIG_HOME="$real_home/.config" \
        XDG_DATA_HOME="$real_home/.local/share" XDG_STATE_HOME="$real_home/.local/state" \
        XDG_CACHE_HOME="$real_home/.cache" TMPDIR="$real_tmp" \
        PATH="$real_bin:$PATH" _doctor_records _dr_check_nvim_lsp_policy
    }
    before_snapshot=$(_real_home_snapshot)
    : >"$git_log"
    result=$(_real_policy)
    _assert_contains 'Doctor runs the real LSP policy query to completion' \
      $'ok\tnvim LSP fallback policy in sync' "$result"
    _assert_eq 'The LSP policy probe writes nothing under HOME' \
      "$before_snapshot" "$(_real_home_snapshot)"
    _assert_eq 'The LSP policy probe removes its private temp directory' '' \
      "$(
        shopt -s dotglob nullglob
        printf '%s' "$real_tmp"/*
      )"
    _assert_eq 'The LSP policy probe disables plugin bootstrap clones' '' "$(<"$git_log")"
    result=$(DOCTOR_CONFIG_FETCHES=1 _real_policy)
    _assert_contains 'A config that fetches anyway gets only file-protocol git' \
      'file|fetch https://github.com/folke/lazy.nvim.git' "$(<"$git_log")"
    _assert_not_contains 'No git call escapes the file-protocol restriction' \
      'unset|' "$(<"$git_log")"
    rm "$real_home/.config/nvim/lua/config/mason-policy.lua"
    result=$(_real_policy)
    _assert_contains 'Doctor reports a real Nvim query failure instead of in sync' \
      $'warn\tnvim LSP fallback policy check failed\t' "$result"
    _assert_contains 'Doctor names the failing module from the real query' \
      'config.mason-policy' "$result"
  else
    _pass 'Real Nvim LSP policy query needs an nvim binary (skipped)'
  fi

  # Only absent Nvim modules produce rows; healthy files were noise.
  nvim_dev_home=$(_tmpdir)
  for module_path in \
    lua/config/mason-policy.lua \
    lua/dotfiles/lazyvim_extras/dev.lua \
    lua/dotfiles/plugin_overrides/dev-tools.lua \
    lua/dotfiles/plugin_overrides/workspace-dev.lua \
    lua/dotfiles/final_policy/mason.lua \
    lua/plugins/formatting.lua \
    lua/plugins/linting.lua; do
    mkdir -p "$nvim_dev_home/.config/nvim/${module_path%/*}"
    : >"$nvim_dev_home/.config/nvim/$module_path"
  done
  result=$(HOME="$nvim_dev_home" PATH="$reg_bin" _doctor_records _dr_check_nvim_dev)
  _assert_not_contains 'Nvim dev doctor publishes no per-file configured rows' \
    'configured' "$result"
  _assert_contains 'Nvim dev doctor skips the policy query without nvim' \
    $'skip\tnvim LSP fallback policy\tnvim not installed' "$result"
  rm "$nvim_dev_home/.config/nvim/lua/plugins/linting.lua"
  result=$(HOME="$nvim_dev_home" PATH="$reg_bin" _doctor_records _dr_check_nvim_dev)
  _assert_contains 'Nvim dev doctor warns about a missing module, as core does' \
    $'warn\tlinting.lua missing\t~/.config/nvim/lua/plugins/linting.lua; run \'dot update\'' "$result"
  _assert_not_contains 'Nvim dev doctor never fails a module the next update relinks' \
    $'fail\t' "$result"

  # Git hooks: report the scope git itself resolves (includes count) and check
  # every shipped hook, not only pre-commit.
  hooks_home=$(_tmpdir)
  mkdir -p "$hooks_home/.local/lib/dotfiles/git-hooks" "$hooks_home/.config/git"
  for hook in pre-commit commit-msg sley-provider-hook; do
    printf '#!/bin/sh\nexit 0\n' >"$hooks_home/.local/lib/dotfiles/git-hooks/$hook"
    chmod +x "$hooks_home/.local/lib/dotfiles/git-hooks/$hook"
  done
  printf '# Git Hooks\n' >"$hooks_home/.local/lib/dotfiles/git-hooks/README.md"
  printf 'old\n' >"$hooks_home/.local/lib/dotfiles/git-hooks/pre-push.sample"
  printf '[include]\n\tpath = ~/.config/git/hooks.inc\n' >"$hooks_home/.gitconfig"
  printf '[core]\n\thooksPath = ~/.local/lib/dotfiles/git-hooks\n' \
    >"$hooks_home/.config/git/hooks.inc"
  # Every git call goes through a system Git, never the dotfiles launcher.
  # $1 optionally names a wrapper that stands in front of it as `git`.
  _hooks_records() {
    (
      local git_path
      _test_prefer_system_git >/dev/null
      git_path=$(type -P git)
      if [[ -n ${1:-} ]]; then
        DOCTOR_REAL_GIT=$git_path
        export DOCTOR_REAL_GIT
        mkdir -p "$hooks_home/wrapper"
        cp "$1" "$hooks_home/wrapper/git"
        chmod +x "$hooks_home/wrapper/git"
        git_path=$hooks_home/wrapper/git
      fi
      mkdir -p "$hooks_home/selected-git"
      ln -sf "$git_path" "$hooks_home/selected-git/git"
      PATH="$hooks_home/selected-git:/usr/bin:/bin" \
        HOME="$hooks_home" XDG_CONFIG_HOME="$hooks_home/.config" \
        GIT_CONFIG_GLOBAL="$hooks_home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
        DOTFILES="${DOCTOR_DOTFILES-$hooks_home/.dotfiles}" \
        GIT="git --git-dir=$hooks_home/.dotfiles --work-tree=$hooks_home" \
        _doctor_records _dr_check_git_hooks
    )
  }
  _hooks_git() (
    _test_prefer_system_git >/dev/null
    GIT_CONFIG_NOSYSTEM=1 git --git-dir="$hooks_home/.dotfiles" "$@"
  )
  (
    _test_prefer_system_git >/dev/null
    git init -q --bare "$hooks_home/.dotfiles"
  )
  result=$(_hooks_records)
  _assert_contains 'Git hooks doctor labels an included global hooksPath as global' \
    $'ok\tcore.hooksPath\t~/.local/lib/dotfiles/git-hooks (global)' "$result"
  _assert_contains 'Git hooks doctor checks every shipped hook' \
    $'ok\tGit hooks executable\t3 hook(s)' "$result"
  _hooks_git config core.hooksPath /elsewhere
  result=$(_hooks_records)
  _assert_contains 'Git hooks doctor names the scope of an overriding hooksPath' \
    $'warn\tcore.hooksPath points elsewhere\tgot /elsewhere (local)' "$result"
  _assert_contains 'Git hooks doctor points at the override in the repository it checked' \
    "find the override with 'git --git-dir ~/.dotfiles config --show-origin --get-all core.hooksPath' and remove it" \
    "$result"
  # A base whose compat does not set DOTFILES still resolves the client.
  result=$(DOCTOR_DOTFILES='' DOT_CLIENT_GIT_DIR="$hooks_home/.dotfiles" _hooks_records)
  _assert_contains 'Git hooks doctor derives the client git dir without DOTFILES' \
    $'warn\tcore.hooksPath points elsewhere\tgot /elsewhere (local)' "$result"
  _hooks_git config --unset core.hooksPath
  chmod -x "$hooks_home/.local/lib/dotfiles/git-hooks/commit-msg"
  ln -s "$hooks_home/missing" "$hooks_home/.local/lib/dotfiles/git-hooks/pre-merge-commit"
  result=$(_hooks_records)
  _assert_contains 'Git hooks doctor fails a non-executable hook other than pre-commit' \
    $'fail\tcommit-msg hook not executable' "$result"
  _assert_contains 'Git hooks doctor fails a dangling hook link' \
    $'fail\tpre-merge-commit hook link broken' "$result"
  _assert_not_contains 'Git hooks doctor treats README files as documentation' \
    'README.md' "$result"
  _assert_not_contains 'Git hooks doctor ignores dotted non-hook files' \
    'pre-push.sample' "$result"
  # Git before 2.26 rejects --show-scope with a usage error (exit 129).
  cat >"$hooks_home/old-git" <<'SH'
#!/bin/sh
for arg do
  [ "$arg" != --show-scope ] || exit 129
done
exec "$DOCTOR_REAL_GIT" "$@"
SH
  result=$(_hooks_records "$hooks_home/old-git")
  _assert_contains 'Git hooks doctor keeps the value on Git without --show-scope' \
    $'ok\tcore.hooksPath\t~/.local/lib/dotfiles/git-hooks (scope unknown)' "$result"
  printf '#!/bin/sh\nexit 128\n' >"$hooks_home/broken-git"
  result=$(_hooks_records "$hooks_home/broken-git")
  _assert_contains 'Git hooks doctor reports a failing git config lookup' \
    $'warn\tcore.hooksPath unchecked\tgit config exited 128' "$result"
  _assert_not_contains 'Git hooks doctor does not call a failed lookup unset' \
    'core.hooksPath not set' "$result"
  : >"$hooks_home/.config/git/hooks.inc"
  result=$(_hooks_records)
  _assert_contains 'Git hooks doctor warns when hooksPath is unset' \
    $'warn\tcore.hooksPath not set' "$result"

  # Hive Memory: one bounded `hm sync-status --json`; stdout is the JSON
  # report and stderr stays apart. The stub answers from DOCTOR_HM_*.
  hm_home=$(_tmpdir)
  hm_bin=$(_tmpdir)
  cat >"$hm_bin/hm" <<'HM'
#!/usr/bin/env bash
if [[ "$*" != 'sync-status --json' ]]; then
  printf 'unexpected arguments: %s\n' "$*" >&2
  exit 9
fi
[[ -z ${DOCTOR_HM_SLEEP:-} ]] || exec sleep "$DOCTOR_HM_SLEEP"
[[ -z ${DOCTOR_HM_STDERR:-} ]] || printf '%s\n' "$DOCTOR_HM_STDERR" >&2
[[ -z ${DOCTOR_HM_JSON:-} ]] || printf '%s\n' "$DOCTOR_HM_JSON"
exit "${DOCTOR_HM_EXIT:-0}"
HM
  chmod +x "$hm_bin/hm"
  # shellcheck disable=SC2329  # _doctor_records invokes this.
  _hm_probe() {
    _dr_hive_memory_start "$1"
    _dr_hive_memory_finish "$1"
  }
  _hm_records() {
    # Pin XDG_CONFIG_HOME too: CI exports one under the runner's HOME, and the
    # config-path hint follows it rather than this fixture HOME.
    HOME="$hm_home" XDG_CONFIG_HOME="$hm_home/.config" PATH="$hm_bin:$doctor_bin:$PATH" \
      _doctor_records _hm_probe "$(_tmpdir)"
  }
  hm_store=$hm_home/store
  hm_healthy='{"store":"personal","root":"'$hm_store'","reachable":true,"manifest_error":null,"store_error":null,"index_stale":true,"cloud_conflict_files":0,"unknown_config_keys":[]}'
  result=$(DOCTOR_HM_JSON=$hm_healthy _hm_records)
  _assert_contains 'Hive Memory reports a reachable store with every key understood' \
    $'ok\tHive Memory store reachable\t~/store; every config key understood' "$result"
  _assert_not_contains 'Hive Memory files no row for an index hm rebuilds on the next read' \
    'index' "$result"
  result=$(DOCTOR_HM_JSON=${hm_healthy/'"unknown_config_keys":[]'/'"unknown_config_keys":["defaults.context_strategy","stores.work.extra"]'} \
    DOCTOR_HM_STDERR='warning: unknown config key: defaults.context_strategy' _hm_records)
  _assert_contains 'Hive Memory names unknown config keys from the structured field' \
    $'warn\thm binary behind configured keys\tunknown key(s): defaults.context_strategy, stores.work.extra; run \'dot update\' to update hive-memory, or drop the key(s) from ~/.config/hive-memory/config.toml' \
    "$result"
  _assert_not_contains 'Hive Memory withholds the ok row when a key is unknown' \
    'store reachable' "$result"
  result=$(DOCTOR_HM_JSON='{"root":"'$hm_store'","reachable":false,"manifest_error":null,"store_error":"read '$hm_store'/inbox: Transport endpoint is not connected (os error 107)","cloud_conflict_files":3,"unknown_config_keys":[]}' \
    _hm_records)
  _assert_contains 'Hive Memory warns when the store scan fails' \
    $'warn\tHive Memory store unreachable\tread '"$hm_store"$'/inbox: Transport endpoint is not connected (os error 107); check that' \
    "$result"
  _assert_not_contains 'Hive Memory ignores scan counts from an unreachable store' \
    'conflict' "$result"
  result=$(DOCTOR_HM_JSON='{"root":"'$hm_store'","reachable":false,"manifest_error":"store manifest missing","store_error":null,"unknown_config_keys":[]}' \
    _hm_records)
  _assert_contains 'Hive Memory names a manifest error when the store is unreachable' \
    $'warn\tHive Memory store unreachable\tstore manifest missing; ' "$result"
  result=$(DOCTOR_HM_JSON=${hm_healthy/'"cloud_conflict_files":0'/'"cloud_conflict_files":2'} _hm_records)
  _assert_contains 'Hive Memory warns about cloud conflict copies' \
    $'warn\tHive Memory store has 2 cloud conflict file(s)\trun \'hm doctor --fix\' to quarantine them' \
    "$result"
  # An hm before the structured fields: no unknown_config_keys and no
  # store_error, and a conflict count that still included quarantined copies.
  hm_old='{"store":"personal","root":"'$hm_store'","reachable":true,"manifest_error":null,"index_stale":false,"cloud_conflict_files":4}'
  result=$(DOCTOR_HM_JSON=$hm_old _hm_records)
  _assert_contains 'Hive Memory accepts an older hm report' \
    $'ok\tHive Memory store reachable\t~/store' "$result"
  _assert_not_contains 'Hive Memory never claims keys an older hm cannot list' \
    'understood' "$result"
  _assert_not_contains 'Hive Memory ignores the conflict count of an older hm' \
    'conflict' "$result"
  result=$(DOCTOR_HM_JSON=$hm_old \
    DOCTOR_HM_STDERR=$'warning: unknown config key: defaults.context_strategy\nwarning: unknown config key: x.y' \
    _hm_records)
  _assert_contains 'Hive Memory reads unknown keys from an older hm stderr' \
    $'warn\thm binary behind configured keys\tunknown key(s): defaults.context_strategy, x.y; ' \
    "$result"
  result=$(DOCTOR_HM_EXIT=1 DOCTOR_HM_STDERR='error: scan '"$hm_store"': Input/output error' \
    _hm_records)
  _assert_contains 'Hive Memory leaves the store unchecked without a report' \
    $'warn\tHive Memory unchecked\terror: scan '"$hm_store"$': Input/output error; run \'hm sync-status\'' \
    "$result"
  # With --json, hm reports a failure as a JSON object on stderr, sometimes
  # after warning lines.
  result=$(DOCTOR_HM_EXIT=3 DOCTOR_HM_STDERR=$'warning: unknown config key: x.y\n{\n  "ok": false,\n  "error": {\n    "code": "config_error",\n    "message": "failed to read config: denied"\n  }\n}' \
    _hm_records)
  _assert_contains 'Hive Memory names the error hm reports as JSON' \
    $'warn\tHive Memory unchecked\tfailed to read config: denied; run \'hm sync-status\'' "$result"
  result=$(DOCTOR_HM_EXIT=127 DOCTOR_HM_STDERR='hm launcher: real hm not found at /x/hm; run dot update' \
    _hm_records)
  _assert_contains 'Hive Memory skips when the launcher finds no real hm' \
    $'skip\tHive Memory\thm launcher: real hm not found at /x/hm; run dot update' "$result"
  result=$(DOCTOR_HM_JSON='not json' _hm_records)
  _assert_contains 'Hive Memory leaves the store unchecked on output that is not JSON' \
    $'warn\tHive Memory unchecked\thm sync-status exited 0 without a report' "$result"
  started=$SECONDS
  result=$(DOCTOR_HM_SLEEP=30 _DR_HM_DEADLINE=1 _fresh_deadline _hm_records)
  _assert_contains 'Hive Memory bounds a hung hm' \
    $'warn\tHive Memory unchecked\thm sync-status gave no answer within 1s' "$result"
  _assert_eq 'Hive Memory returns within its deadline' yes \
    "$( ((SECONDS - started < 10)) && printf yes || printf no)"
  result=$(HOME="$hm_home" PATH="$doctor_bin:/usr/bin:/bin" \
    _doctor_records _hm_probe "$(_tmpdir)")
  _assert_contains 'Hive Memory skips when hm is not installed' \
    $'skip\tHive Memory\thm not installed' "$result"
  mkdir -p "$hm_home/no-jq"
  ln -s "$hm_bin/hm" "$hm_home/no-jq/hm"
  ln -s "$(type -P bash)" "$hm_home/no-jq/bash"
  result=$(HOME="$hm_home" PATH="$hm_home/no-jq" DOCTOR_HM_JSON=$hm_healthy \
    _doctor_records _hm_probe "$(_tmpdir)")
  _assert_contains 'Hive Memory skips without jq' \
    $'skip\tHive Memory\tjq is required to read hm sync-status' "$result"

  # Development shell integrations: resolve each provider asset through the
  # overlay's own adapter in a bare Bash, as a new interactive shell does.
  # The base helper is stubbed: it resolves cgraf78/NAME to assets/NAME.sh
  # unless DOCTOR_UNRESOLVED names it, and logs what it saw.
  integ_home=$(_tmpdir)
  integ_bin=$(_tmpdir)
  mkdir -p "$integ_home/.config/shell/interactive.d" \
    "$integ_home/.local/lib/dotfiles" "$integ_home/assets" "$integ_home/tmp"
  cp "$owner_root/home/.config/shell/interactive.d/70-dev-tool-init.sh" \
    "$integ_home/.config/shell/interactive.d/70-dev-tool-init.sh"
  : >"$integ_home/assets/sley.sh"
  : >"$integ_home/assets/git-tools.sh"
  cat >"$integ_home/.local/lib/dotfiles/shdeps-assets.sh" <<'SH'
dot_shdeps_dep_file() {
  printf '%s|%s|%s|%s\n' "$1 $2" "${XDG_CACHE_HOME-unset}" "${BASH_ENV-unset}" \
    "${ENV-unset}" >>"$HOME/resolutions"
  [[ -z ${DOCTOR_RESOLVE_SLEEP:-} ]] || sleep "$DOCTOR_RESOLVE_SLEEP"
  case " ${DOCTOR_UNRESOLVED:-} " in *" ${1#cgraf78/} "*) return 1 ;; esac
  printf '%s\n' "$HOME/assets/${1#cgraf78/}.sh"
}
SH
  printf '#!/bin/sh\nexit 0\n' >"$integ_bin/direnv"
  chmod +x "$integ_bin/direnv"
  : >"$integ_home/startup.sh"
  _integ_records() {
    HOME="$integ_home" PATH="$integ_bin:$doctor_bin:$PATH" \
      XDG_CACHE_HOME="$integ_home/.cache" TMPDIR="$integ_home/tmp" \
      _doctor_records _dr_check_dev_integrations
  }
  : >"$integ_home/resolutions"
  result=$(BASH_ENV="$integ_home/startup.sh" ENV="$integ_home/startup.sh" _integ_records)
  _assert_contains 'Dev shell integrations pass when every asset resolves' \
    $'ok\tdev shell integrations\tsley, git-tools, direnv' "$result"
  _assert_contains 'Dev shell integrations resolve the sley asset through shdeps' \
    'cgraf78/sley share/sley/shell.sh|' "$(<"$integ_home/resolutions")"
  _assert_contains 'Dev shell integrations resolve the git-tools asset through shdeps' \
    'cgraf78/git-tools share/git-tools/shell.sh|' "$(<"$integ_home/resolutions")"
  _assert_not_contains 'Dev shell integrations resolve with a private cache' \
    "|$integ_home/.cache|" "$(<"$integ_home/resolutions")"
  _assert_contains 'Dev shell integrations probe without startup files' \
    '|unset|unset' "$(<"$integ_home/resolutions")"
  _assert_eq 'Dev shell integrations remove their private cache' '' \
    "$(
      shopt -s dotglob nullglob
      printf '%s' "$integ_home/tmp"/*
    )"
  result=$(DOCTOR_UNRESOLVED=git-tools _integ_records)
  _assert_contains 'Dev shell integrations warn about an asset that does not resolve' \
    $'warn\tgit-tools shell integration unavailable\tcgraf78/git-tools share/git-tools/shell.sh does not resolve, so new shells skip it; run \'dot update\'' \
    "$result"
  _assert_not_contains 'Dev shell integrations withhold the ok row on a problem' \
    $'ok\tdev shell integrations' "$result"
  rm "$integ_home/assets/sley.sh"
  result=$(_integ_records)
  _assert_contains 'Dev shell integrations warn about an asset path that is unreadable' \
    $'warn\tsley shell integration unavailable' "$result"
  : >"$integ_home/assets/sley.sh"
  # direnv absent: a PATH with only what the probe itself needs.
  mkdir -p "$integ_home/no-direnv"
  for hook in cat env mkfifo mktemp rm; do
    ln -s "$(type -P "$hook")" "$integ_home/no-direnv/$hook"
  done
  result=$(HOME="$integ_home" PATH="$integ_home/no-direnv" TMPDIR="$integ_home/tmp" \
    _doctor_records _dr_check_dev_integrations)
  _assert_contains 'Dev shell integrations warn when direnv is not on PATH' \
    $'warn\tdirenv shell integration unavailable\tdirenv is not on PATH, so new shells skip its hook; run \'dot update\'' \
    "$result"
  _assert_not_contains 'Dev shell integrations still resolve assets without direnv' \
    'sley shell integration' "$result"
  printf 'return 1\n' >"$integ_home/broken-adapter"
  mv "$integ_home/.config/shell/interactive.d/70-dev-tool-init.sh" "$integ_home/adapter"
  cp "$integ_home/broken-adapter" "$integ_home/.config/shell/interactive.d/70-dev-tool-init.sh"
  result=$(_integ_records)
  _assert_contains 'Dev shell integrations report an adapter that does not load' \
    $'warn\tsley shell integration unchecked\tthe asset probe exited 3; source ~/.config/shell/interactive.d/70-dev-tool-init.sh in a new bash to see the error, then run \'dot update\'' \
    "$result"
  rm "$integ_home/.config/shell/interactive.d/70-dev-tool-init.sh"
  result=$(_integ_records)
  _assert_contains 'Dev shell integrations warn when the adapter is missing' \
    $'warn\tdev shell integration adapter missing\t~/.config/shell/interactive.d/70-dev-tool-init.sh; run \'dot update\'' \
    "$result"
  mv "$integ_home/adapter" "$integ_home/.config/shell/interactive.d/70-dev-tool-init.sh"
  started=$SECONDS
  result=$(DOCTOR_RESOLVE_SLEEP=30 _DR_DEV_SHELL_DEADLINE=1 _fresh_deadline _integ_records)
  _assert_contains 'Dev shell integrations bound a hung asset resolution' \
    $'warn\tdev shell integrations unchecked\tresolving their shell assets took longer than 1s; run \'shdeps health\'' \
    "$result"
  _assert_eq 'Dev shell integrations return within their deadline' yes \
    "$( ((SECONDS - started < 10)) && printf yes || printf no)"
  : >"$result_file"
  set +e
  (
    set -euo pipefail
    DOCTOR_UNRESOLVED='sley git-tools' HOME="$integ_home" PATH="$integ_bin:$doctor_bin:$PATH" \
      TMPDIR="$integ_home/tmp" _dr_check_dev_integrations
  )
  status=$?
  set -e
  _assert_eq 'Dev shell integrations run under the worker shell policy' 0 "$status"
  # The probe's asset list must be what the interactive files load.
  for path in 80-dev-integrations.bash 80-dev-integrations.zsh; do
    expected=
    while read -r integ_call integ_name integ_emitter integ_dep integ_asset _; do
      [[ $integ_call == _tool_init && $integ_emitter == _tool_shdeps_source_emit ]] || continue
      expected+=${expected:+ }"$integ_name $integ_dep $integ_asset"
    done <"$owner_root/home/.config/shell/interactive.d/$path"
    _assert_eq "Doctor probes every provider asset $path loads" \
      "$expected" "${_DR_DEV_SHELL_ASSETS[*]}"
  done

  # Smoke probes, one fresh result directory per run.
  probe_root=$(_tmpdir)
  _probe_records() {
    _doctor_records _dr_check_agent_hook_probes "$(mktemp -d "$probe_root/run.XXXXXX")"
  }
  agent_home=$(_tmpdir)
  mkdir -p "$agent_home/.local/bin" "$agent_home/.config/shell"
  : >"$agent_home/.config/shell/env-noninteractive.sh"
  cat >"$agent_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
input=$(cat)
case $input in
  *'"dot status"'*) printf '{}\n' ;;
  *'"git status -uall"'*) printf 'use dot status instead\n' >&2; exit 2 ;;
  *) exit 3 ;;
esac
SH
  cat >"$agent_home/.local/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '{}\n'
SH
  chmod +x "$agent_home/.local/bin/agent-hook-pre-bash" \
    "$agent_home/.local/bin/agent-hook-stop"
  result=$(HOME="$agent_home" PATH="$doctor_bin:$PATH" \
    _probe_records)
  _assert_contains 'Agent Hooks doctor accepts the allowed benign command' \
    $'ok\tagent pre-bash allows a benign command\tdot status' "$result"
  _assert_contains 'Agent Hooks doctor accepts the policy denial path' \
    $'ok\tagent pre-bash enforces policy\tblocks raw dotfiles git status' "$result"
  _assert_contains 'Agent Hooks doctor accepts the stop-hook path' \
    'agent stop hook runs' "$result"

  cat >"$agent_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf 'broken pre-bash\n' >&2
exit 7
SH
  cat >"$agent_home/.local/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf 'broken stop\n' >&2
exit 9
SH
  result=$(HOME="$agent_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor reports pre-bash failures' \
    $'fail\tagent pre-bash rejects a benign command\tbroken pre-bash' "$result"
  _assert_contains 'Agent Hooks doctor reports unexpected policy probe results' \
    $'fail\tagent pre-bash policy probe failed\texit 7: broken pre-bash' "$result"
  _assert_contains 'Agent Hooks doctor reports stop-hook failures' \
    'agent stop hook failed' "$result"
  # Every failing probe says how to rerun it by hand: the reinstall first,
  # then the command, last, so it can be pasted on its own.
  _assert_contains 'Agent Hooks doctor: a rejected benign command says how to reproduce it' \
    $'fail\tagent pre-bash rejects a benign command\tbroken pre-bash; reinstall AgentGuard with \'dot update\'; to see the failure first, run: (cd ~ && t=$(mktemp -d) && echo \'{"tool_input":{"command":"dot status"}}\' | env -u BASH_ENV -u ENV AGENTGUARD_NAME=agent AGENTGUARD_HIVE_MEMORY_HOOKS=0 AGENTGUARD_PROCESS_DETECT=0 AGENTGUARD_SLEY_GATE=0 AGENTGUARD_SESSION_ID=dot-doctor-repro TMPDIR="$t" "$HOME/.local/bin/agent-hook-pre-bash"; rc=$?; rm -rf "$t"; exit $rc)' \
    "$result"
  _assert_contains 'Agent Hooks doctor: a failed policy probe says how to reproduce it' \
    $'exit 7: broken pre-bash; reinstall AgentGuard with \'dot update\'; to see the failure first, run (a block exits 2 with a reason): (cd ~ && t=$(mktemp -d) && echo \'{"tool_input":{"command":"git status -uall"}}\' | env -u BASH_ENV -u ENV AGENTGUARD_NAME=agent AGENTGUARD_HIVE_MEMORY_HOOKS=0 AGENTGUARD_PROCESS_DETECT=0 AGENTGUARD_SLEY_GATE=0 AGENTGUARD_SESSION_ID=dot-doctor-repro TMPDIR="$t" "$HOME/.local/bin/agent-hook-pre-bash"; rc=$?; rm -rf "$t"; exit $rc)' \
    "$result"
  _assert_contains 'Agent Hooks doctor: a failed stop hook says how to reproduce it' \
    $'fail\tagent stop hook failed\tbroken stop; reinstall AgentGuard with \'dot update\'; to see the failure first, run: (cd ~ && t=$(mktemp -d) && echo \'{}\' | env -u BASH_ENV -u ENV AGENTGUARD_NAME=agent AGENTGUARD_HIVE_MEMORY_HOOKS=0 AGENTGUARD_PROCESS_DETECT=0 AGENTGUARD_SLEY_GATE=0 AGENTGUARD_SESSION_ID=dot-doctor-repro TMPDIR="$t" "$HOME/.local/bin/agent-hook-stop"; rc=$?; rm -rf "$t"; exit $rc)' \
    "$result"
  # The printed command runs as printed: from any directory, without moving
  # the caller's shell, under the throwaway session ID, with the hook's own
  # output and exit status.
  repro_cmd=$(sed -n 's/^fail\tagent stop hook failed\t.*, run: //p' <<<"$result")
  cat >"$agent_home/.local/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf 'broken stop for %s in %s\n' "${AGENTGUARD_SESSION_ID:-}" "$PWD" >&2
exit 9
SH
  repro_out=$(cd "$probe_root" && HOME="$agent_home" bash -c "$repro_cmd; echo \"rc=\$? pwd=\$PWD\"" 2>&1)
  _assert_eq 'Agent Hooks doctor: the printed rerun command reproduces the probe' \
    "broken stop for dot-doctor-repro in $agent_home"$'\n'"rc=9 pwd=$probe_root" "$repro_out"
  # A Dot with the hint helper gets the step as its own line.
  result=$(
    # shellcheck disable=SC2329 # Probed by the checks under test.
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    HOME="$agent_home" PATH="$doctor_bin:$PATH" _probe_records || true
  )
  _assert_contains 'Agent Hooks doctor: a newer Dot keeps the probe detail on the row' \
    $'\nfail\tagent stop hook failed\tbroken stop for dot-doctor-' "$result"
  _assert_contains 'Agent Hooks doctor: a newer Dot gets the probe step as a hint' \
    $'hint\treinstall AgentGuard with \'dot update\'; to see the failure first, run: (cd ~ && t=$(mktemp -d) && echo \'{}\' | env -u BASH_ENV -u ENV AGENTGUARD_NAME=agent AGENTGUARD_HIVE_MEMORY_HOOKS=0 AGENTGUARD_PROCESS_DETECT=0 AGENTGUARD_SLEY_GATE=0 AGENTGUARD_SESSION_ID=dot-doctor-repro TMPDIR="$t" "$HOME/.local/bin/agent-hook-stop"; rc=$?; rm -rf "$t"; exit $rc)\t' "$result"

  permissive_home=$(_tmpdir)
  mkdir -p "$permissive_home/.local/bin" "$permissive_home/.config/shell"
  : >"$permissive_home/.config/shell/env-noninteractive.sh"
  cat >"$permissive_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '{}\n'
SH
  cat >"$permissive_home/.local/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '{}\n'
SH
  chmod +x "$permissive_home/.local/bin/agent-hook-pre-bash" \
    "$permissive_home/.local/bin/agent-hook-stop"
  result=$(HOME="$permissive_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor rejects raw Git outside a checkout' \
    $'fail\tagent pre-bash does not enforce policy' "$result"
  # test/run stubs _dr_is_dotfiles_checkout to always fail (the capability
  # fixture must not contain a git repo), so a real `git init` fixture can
  # never observe the inside-checkout branch in CI. Drive the predicate
  # directly instead: the lib's inside/outside branching is what's under
  # test here, not real git discovery (base-owned, tested elsewhere).
  _checkout_def=$(declare -f _dr_is_dotfiles_checkout)
  # shellcheck disable=SC2329  # _dr_check_agent_hook_probes invokes this predicate.
  _dr_is_dotfiles_checkout() { return 0; }
  result=$(HOME="$permissive_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor allows raw Git inside a checkout' \
    $'ok\tagent pre-bash enforces policy\traw git status is allowed: HOME is a Git checkout' \
    "$result"
  eval "$_checkout_def"

  # Exit 2 is the block signal; the hook's stderr wording is display text.
  cat >"$permissive_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
input=$(cat)
case $input in
  *'"dot status"'*) printf '{}\n' ;;
  *) printf 'blocked by policy\n' >&2; exit 2 ;;
esac
SH
  result=$(HOME="$permissive_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor keys policy enforcement on exit 2, not stderr text' \
    $'ok\tagent pre-bash enforces policy' "$result"
  cat >"$permissive_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
input=$(cat)
case $input in
  *'"dot status"'*) printf '{}\n' ;;
  *) exit 2 ;;
esac
SH
  result=$(HOME="$permissive_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor does not take a bare exit 2 as a block' \
    $'fail\tagent pre-bash policy probe failed\texited 2 without a message' "$result"

  no_pre_home=$(_tmpdir)
  mkdir -p "$no_pre_home/.local/bin" "$no_pre_home/.config/shell"
  : >"$no_pre_home/.config/shell/env-noninteractive.sh"
  cat >"$no_pre_home/.local/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
: >"$HOME/.stop-ran"
printf '{}\n'
SH
  chmod +x "$no_pre_home/.local/bin/agent-hook-stop"
  result=$(HOME="$no_pre_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor warns when pre-bash is absent' \
    'agent pre-bash hook unavailable' "$result"
  _assert_not_contains 'Agent Hooks doctor skips every probe without pre-bash' \
    'agent stop hook' "$result"
  _assert_eq 'Agent Hooks doctor never executes stop without pre-bash' \
    'absent' "$([[ -f $no_pre_home/.stop-ran ]] && printf present || printf absent)"

  no_stop_home=$(_tmpdir)
  mkdir -p "$no_stop_home/.local/bin" "$no_stop_home/.config/shell"
  : >"$no_stop_home/.config/shell/env-noninteractive.sh"
  cat >"$no_stop_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
input=$(cat)
case $input in
  *'"dot status"'*) printf '{}\n' ;;
  *'"git status -uall"'*) printf 'use dot status instead\n' >&2; exit 2 ;;
  *) exit 3 ;;
esac
SH
  chmod +x "$no_stop_home/.local/bin/agent-hook-pre-bash"
  result=$(HOME="$no_stop_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor warns when the stop hook is absent' \
    'agent stop hook unavailable' "$result"

  multiline_home=$(_tmpdir)
  mkdir -p "$multiline_home/.local/bin" "$multiline_home/.config/shell"
  : >"$multiline_home/.config/shell/env-noninteractive.sh"
  cat >"$multiline_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
input=$(cat)
case $input in
  *'"dot status"'*) printf 'first\nsecond\nthird\n' >&2; exit 5 ;;
  *) printf 'e1\ne2\n' >&2; exit 3 ;;
esac
SH
  chmod +x "$multiline_home/.local/bin/agent-hook-pre-bash"
  result=$(HOME="$multiline_home" PATH="$doctor_bin:$PATH" \
    _probe_records || true)
  _assert_contains 'Agent Hooks doctor keeps only the first stderr line' \
    $'fail\tagent pre-bash rejects a benign command\tfirst' "$result"
  _assert_not_contains 'Agent Hooks doctor drops later stderr lines' \
    'second' "$result"

  # Hook stderr is display text; a tab or carriage return in it must become
  # record text instead of failing the worker.
  cat >"$multiline_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf 'bad\tline\r\n' >&2
exit 5
SH
  : >"$result_file"
  set +e
  (
    set -euo pipefail
    HOME="$multiline_home" PATH="$doctor_bin:$PATH" \
      _dr_check_agent_hook_probes "$(mktemp -d "$probe_root/run.XXXXXX")"
  )
  status=$?
  set -e
  _assert_eq 'Agent hook probes survive control characters in hook stderr' 0 "$status"
  _assert_contains 'Agent hook probes turn hook stderr into record text' \
    $'fail\tagent pre-bash policy probe failed\texit 5: bad line' "$(<"$result_file")"
  cat >"$multiline_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
exit 6
SH
  result=$(HOME="$multiline_home" PATH="$doctor_bin:$PATH" _probe_records || true)
  _assert_contains 'Agent hook probes name the status of a silent failure' \
    $'fail\tagent pre-bash rejects a benign command\texited 6 without a message' "$result"

  # Probes run hooks the way agents do: every registered command starts with
  # `env -u BASH_ENV -u ENV`, so a startup file must not reach the hook.
  cat >"$multiline_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '%s|%s\n' "${BASH_ENV-unset}" "${ENV-unset}" >>"$HOME/hook-env"
exit 0
SH
  : >"$multiline_home/startup.sh"
  : >"$multiline_home/hook-env"
  result=$(HOME="$multiline_home" PATH="$doctor_bin:$PATH" \
    BASH_ENV="$multiline_home/startup.sh" ENV="$multiline_home/startup.sh" \
    _probe_records || true)
  _assert_eq 'Agent hook probes unset BASH_ENV and ENV like the registered commands' \
    $'unset|unset\nunset|unset' "$(<"$multiline_home/hook-env")"
  # Bounded: a hung hook costs the probe deadline, not the whole section.
  cat >"$multiline_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
exec sleep 30
SH
  cat >"$multiline_home/.local/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
exec sleep 30
SH
  chmod +x "$multiline_home/.local/bin/agent-hook-stop"
  started=$SECONDS
  result=$(HOME="$multiline_home" PATH="$doctor_bin:$PATH" _DR_AGENT_HOOK_DEADLINE=1 \
    _fresh_deadline _probe_records || true)
  _assert_contains 'Agent hook probes bound a hung pre-bash hook' \
    $'fail\tagent pre-bash rejects a benign command\tno answer within 1s' "$result"
  _assert_contains 'Agent hook probes bound a hung policy probe' \
    $'fail\tagent pre-bash policy probe failed\tno answer within 1s' "$result"
  _assert_contains 'Agent hook probes bound a hung stop hook' \
    $'fail\tagent stop hook failed\tno answer within 1s' "$result"
  _assert_eq 'Agent hook probes return within their deadline' yes \
    "$( ((SECONDS - started < 10)) && printf yes || printf no)"

  # Agent tooling is one section: AgentGuard, Grok, Hive Memory, and the
  # agent config folders handed to base's leftover-temporary check. The
  # registration table is covered above; keep host-installed agents out.
  registration_def=$(declare -f _dr_check_agentguard_registrations)
  # shellcheck disable=SC2329  # _dr_check_agent_tooling invokes this.
  _dr_check_agentguard_registrations() { :; }
  tooling_home=$(_tmpdir)
  mkdir -p "$tooling_home/.local/bin"
  temps_lib=$DOT_EXTENSIONS_DIR/doctor.d/lib/config-temporaries.sh
  temps_saved=
  if [[ -e $temps_lib ]]; then
    temps_saved=$(_tmpdir)/config-temporaries.sh
    mv "$temps_lib" "$temps_saved"
  fi
  temps_def=$(declare -f _dr_check_config_temporaries || true)
  unset -f _dr_check_config_temporaries
  : >"$result_file"
  set +e
  (
    set -euo pipefail
    HOME="$tooling_home" PATH="$hm_bin:$doctor_bin:$PATH" DOCTOR_HM_JSON=$hm_healthy \
      _dr_check_agent_tooling
  )
  status=$?
  set -e
  result=$(<"$result_file")
  _assert_eq 'Agent tooling runs under the worker shell policy on a base without the temporaries module' \
    0 "$status"
  _assert_contains 'Agent tooling publishes one section' $'section\tAgent tooling' "$result"
  _assert_eq 'Agent tooling replaces the separate Hive Memory section' 1 \
    "$(awk -F '\t' '$1 == "section" { count++ } END { print count+0 }' "$result_file")"
  _assert_contains 'Agent tooling reports Hive Memory' \
    $'ok\tHive Memory store reachable' "$result"
  _assert_contains 'Agent tooling still smoke-probes the hooks' \
    'agent pre-bash hook unavailable' "$result"
  temps_log=$(_tmpdir)/temporaries
  cat >"$temps_lib" <<SH
# shellcheck shell=bash
_dr_check_config_temporaries() {
  printf '%s\\n' "\$@" >"$temps_log"
  _dr_warn 'leftover config temporaries stub'
}
SH
  chmod 600 "$temps_lib"
  result=$(HOME="$tooling_home" PATH="$hm_bin:$doctor_bin:$PATH" DOCTOR_HM_JSON=$hm_healthy \
    _doctor_records _dr_check_agent_tooling)
  _assert_eq 'Agent tooling passes every agent config folder its merge hooks write' \
    $'.claude\n.codex\n.config/muse\n.gemini\n.grok/hooks\n.config/opencode/plugins\n.grok' \
    "$(<"$temps_log")"
  _assert_contains 'Agent tooling files the temporaries row in its own section' \
    $'warn\tleftover config temporaries stub' "$result"
  rm -f "$temps_lib"
  unset -f _dr_check_config_temporaries
  [[ -z $temps_saved ]] || mv "$temps_saved" "$temps_lib"
  [[ -z $temps_def ]] || eval "$temps_def"
  eval "$registration_def"

  # No temporary directory for the probes: a warning with a next step, not a
  # bare extension failure.
  printf '#!/bin/sh\nexit 1\n' >"$tooling_home/.local/bin/mktemp"
  chmod +x "$tooling_home/.local/bin/mktemp"
  result=$(HOME="$tooling_home" PATH="$tooling_home/.local/bin:$hm_bin:$doctor_bin:$PATH" \
    _doctor_records _dr_check_agent_tooling)
  _assert_contains 'Agent tooling without a temporary directory warns with a next step' \
    $'warn\tAgent tooling unchecked\tcould not create a temporary directory; ' \
    "$result"
  rm -f "$tooling_home/.local/bin/mktemp"

  if [[ -n ${DOT_TEST_DOCTOR_EXTENSION_HOME:-} ]]; then
    installed_config=$HOME/.config/dot/config
    installed_config_before=$(<"$installed_config")
    printf 'version=1\nextension_api=1\nextensions_dir=%s\ndependency_provider=none\n' \
      "$DOT_TEST_DOCTOR_EXTENSION_HOME/.local/lib/dotfiles" >"$installed_config"
    installed_doctor_output=$(dot doctor 2>&1 || true)
    printf '%s\n' "$installed_config_before" >"$installed_config"
    for installed_section in \
      'Development shell integrations' \
      'Git hooks' \
      'Agent tooling' \
      'Nvim development tooling'; do
      _assert_contains "Installed dot doctor discovers $installed_section" \
        "$installed_section" "$installed_doctor_output"
    done
    # Hive Memory rows live on inside Agent tooling, so only these names are
    # unique to retired sections.
    for installed_section in 'Development tools' 'Agent hooks'; do
      _assert_not_contains "Installed dot doctor no longer shows $installed_section" \
        "$installed_section" "$installed_doctor_output"
    done
  fi

}
