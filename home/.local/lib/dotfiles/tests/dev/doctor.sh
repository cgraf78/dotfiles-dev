# shellcheck shell=bash

dot_dev_doctor_test() {
  local result_file current_module sections failures extension_home path
  local -a modules=(
    20-dev-tools.sh
    30-dev-shell-integrations.sh
    31-git-hooks.sh
    40-agent-hooks.sh
    50-hive-memory.sh
    75-nvim-dev.sh
  )

  extension_home=${DOT_TEST_DOCTOR_EXTENSION_HOME:-}
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
}
