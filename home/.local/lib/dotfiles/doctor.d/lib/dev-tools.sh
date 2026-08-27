# shellcheck shell=bash
# dot doctor: development command checks.

_dr_check_dev_tools() {
  local command_name
  _dr_section 'Development tools'

  for command_name in gh delta difft gitleaks lazygit sley checkrun agentguard; do
    if command -v "$command_name" >/dev/null 2>&1; then
      _dr_ok "$command_name" 'available'
    else
      _dr_warn "$command_name missing" "run 'dot update' with the dev profile"
    fi
  done

  if [[ -f "$HOME/.config/git/config" ]]; then
    _dr_ok 'global Git configuration' "$(_dr_tilde "$HOME/.config/git/config")"
  else
    _dr_fail 'global Git configuration missing' 'select the dev profile and run dot update'
  fi
}
