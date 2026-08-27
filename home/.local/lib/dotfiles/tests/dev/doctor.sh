# shellcheck shell=bash

dot_dev_doctor_test() {
  local result_file current_module sections failures extension_home path
  local doctor_home doctor_bin result drift expected health_log direct_tool
  local -a modules=(
    20-dev-tools.sh
    30-dev-shell-integrations.sh
    31-git-hooks.sh
    40-agent-hooks.sh
    50-hive-memory.sh
    75-nvim-dev.sh
  )

  extension_home=${DOT_TEST_DOCTOR_EXTENSION_HOME:-}
  DOT_DOCTOR_RESULT_FILE=$(_tmpdir)/doctor-results.tsv
  export DOT_DOCTOR_RESULT_FILE
  if [[ -z $extension_home ]]; then
    extension_home=$(_tmpdir)/api-home
    mkdir -p "$extension_home/.local/lib/dotfiles/doctor.d/lib"
    for path in "${modules[@]}"; do
      cp "$HOME/.local/lib/dotfiles/doctor.d/$path" \
        "$extension_home/.local/lib/dotfiles/doctor.d/$path"
    done
    for path in "$HOME"/.local/lib/dotfiles/doctor.d/lib/*.sh; do
      cp "$path" "$extension_home/.local/lib/dotfiles/doctor.d/lib/${path##*/}"
    done
  fi

  _test_load_dot_doctor_api "$extension_home" || {
    _fail 'Standalone Dot doctor API loads for the dev overlay'
    return
  }
  result_file=$DOT_DOCTOR_RESULT_FILE

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
  _assert_eq 'All six dev doctor wrappers publish a section' 6 "$sections"
  _assert_eq 'Dev doctor wrappers publish no failures in the fixture' 0 "$failures"

  _doctor_records() {
    local status=0
    : >"$result_file"
    "$@" || status=$?
    cat "$result_file"
    return "$status"
  }

  doctor_home=$(_tmpdir)
  doctor_bin=$(_mock_bin)
  mkdir -p "$doctor_home/.config/opencode/plugins" "$doctor_home/.local/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$doctor_bin/opencode"
  chmod +x "$doctor_bin/opencode"

  result=$(HOME="$doctor_home" PATH="$doctor_bin:$PATH" DOT_OPENCODE_COMMAND=opencode \
    _doctor_records _dr_check_opencode_agentguard)
  _assert_contains 'Doctor warns when the OpenCode AgentGuard plugin is absent' \
    'OpenCode AgentGuard plugin missing' "$result"
  printf '%s\n' 'export const userOwned = true' \
    >"$doctor_home/.config/opencode/plugins/dotfiles-agentguard.js"
  result=$(HOME="$doctor_home" PATH="$doctor_bin:$PATH" DOT_OPENCODE_COMMAND=opencode \
    _doctor_records _dr_check_opencode_agentguard)
  _assert_contains 'Doctor preserves an unmanaged OpenCode plugin' \
    'OpenCode AgentGuard plugin unmanaged' "$result"
  cat >"$doctor_home/.config/opencode/plugins/dotfiles-agentguard.js" <<'PLUGIN'
// agentguard-managed:opencode-plugin
export const AgentGuardPlugin = async () => ({});
PLUGIN
  result=$(HOME="$doctor_home" PATH="$doctor_bin:$PATH" DOT_OPENCODE_COMMAND=opencode \
    _doctor_records _dr_check_opencode_agentguard)
  _assert_contains 'Doctor accepts the managed OpenCode plugin' \
    'OpenCode AgentGuard plugin installed' "$result"

  drift=$(_dr_lsp_policy_diff 'bashls neocmake vtsls' 'bashls neocmake vtsls')
  expected=$(printf 'missing=\nstale=')
  _assert_eq 'Doctor reports no LSP policy drift for equal sets' "$expected" "$drift"
  drift=$(_dr_lsp_policy_diff 'bashls neocmake pyright vtsls' 'bashls jsonls neocmake')
  expected=$(printf 'missing=pyright,vtsls\nstale=jsonls')
  _assert_eq 'Doctor sorts missing and stale LSP policy entries' "$expected" "$drift"

  health_log=$(_tmpdir)/health.txt
  cat >"$health_log" <<'HEALTH'
Snacks.image ~
- WARNING setup {disabled}
- ERROR None of the tools found: 'magick', 'convert'
- ERROR Tool not found: 'gs'
Snacks.input ~
- ERROR `vim.ui.input` is not set to `Snacks.input`
Snacks.notifier ~
- ERROR is not ready
Snacks.picker ~
- ERROR picker broke
HEALTH
  _assert_eq 'Doctor filters only disabled/headless Snacks health noise' \
    '1 4' "$(_dr_nvim_health_error_counts "$health_log")"

  cat >"$doctor_bin/shdeps" <<'SHDEPS'
#!/usr/bin/env bash
case ${2:-} in
  cgraf78/empty) exit 0 ;;
  cgraf78/malformed) printf 'bad\trow\n' ;;
  cgraf78/direct) printf 'tool\t%s\t%s\n' "$DOCTOR_DIRECT_TOOL" "$DOCTOR_DIRECT_TOOL" ;;
  *) exit 1 ;;
esac
SHDEPS
  chmod +x "$doctor_bin/shdeps"
  direct_tool="$doctor_home/.local/bin/tool"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$direct_tool"
  chmod +x "$direct_tool"
  result=$(HOME="$doctor_home" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_dev_shdeps_bin_group warn empty)
  _assert_contains 'Doctor reports empty Shdeps link inventories' \
    'empty bin links missing' "$result"
  result=$(HOME="$doctor_home" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_dev_shdeps_bin_group warn malformed)
  _assert_contains 'Doctor reports malformed Shdeps link rows' \
    'malformed bin links malformed' "$result"
  result=$(HOME="$doctor_home" PATH="$doctor_bin:$PATH" \
    DOCTOR_DIRECT_TOOL="$direct_tool" \
    _doctor_records _dr_check_dev_shdeps_bin_group warn direct)
  _assert_contains 'Doctor accepts direct executable Shdeps targets' \
    'direct bin links' "$result"
  _assert_not_contains 'Doctor does not require a direct target to be a symlink' \
    'tool not linked' "$result"

  cat >"$doctor_bin/hm" <<'HM'
#!/usr/bin/env bash
[[ ${DOCTOR_HM_SKEW:-0} == 1 ]] &&
  printf 'warning: unknown config key: defaults.context_strategy\n' >&2
printf '[]\n'
HM
  chmod +x "$doctor_bin/hm"
  result=$(HOME="$doctor_home" DOCTOR_HM_SKEW=1 PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_hive_memory)
  _assert_contains 'Doctor reports Hive binary/config skew' \
    'hm binary behind configured keys' "$result"
  _assert_contains 'Doctor names the unsupported Hive config key' \
    'defaults.context_strategy' "$result"
  result=$(HOME="$doctor_home" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_hive_memory)
  _assert_contains 'Doctor accepts Hive config without skew' \
    'hm understands configured keys' "$result"

  mkdir -p "$doctor_home/.config/shell/interactive.d"
  cp "$HOME/.config/shell/interactive.d/80-dev-integrations.bash" \
    "$doctor_home/.config/shell/interactive.d/80-dev-integrations.bash"
  cp "$HOME/.config/shell/interactive.d/80-dev-integrations.zsh" \
    "$doctor_home/.config/shell/interactive.d/80-dev-integrations.zsh"
  result=$(HOME="$doctor_home" _doctor_records _dr_check_dev_integrations)
  _assert_contains 'Doctor accepts complete Bash dev integration policy' \
    $'ok\tbash dev integrations' "$result"
  _assert_contains 'Doctor accepts complete Zsh dev integration policy' \
    $'ok\tzsh dev integrations' "$result"
  awk '!/_tool_init sley/' \
    "$doctor_home/.config/shell/interactive.d/80-dev-integrations.bash" \
    >"$doctor_home/.config/shell/interactive.d/80-dev-integrations.bash.new"
  mv "$doctor_home/.config/shell/interactive.d/80-dev-integrations.bash.new" \
    "$doctor_home/.config/shell/interactive.d/80-dev-integrations.bash"
  result=$(HOME="$doctor_home" _doctor_records _dr_check_dev_integrations)
  _assert_contains 'Doctor reports incomplete shell integration policy' \
    'bash dev integrations incomplete' "$result"

}
