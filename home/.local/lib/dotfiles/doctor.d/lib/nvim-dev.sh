# shellcheck shell=bash
# dot doctor: development-only Nvim policy.

_dr_check_nvim_dev() {
  local missing=0 path
  _dr_section 'Nvim development tooling'

  for path in \
    "$HOME/.config/nvim/lua/config/mason-policy.lua" \
    "$HOME/.config/nvim/lua/plugins/zz-dev-extras.lua" \
    "$HOME/.config/nvim/lua/plugins/formatting.lua" \
    "$HOME/.config/nvim/lua/plugins/linting.lua"; do
    if [[ -r $path ]]; then
      _dr_ok "${path##*/}" 'configured'
    else
      _dr_fail "${path##*/} missing" "$(_dr_tilde "$path")"
      missing=$((missing + 1))
    fi
  done

  ((missing == 0)) || return 0
}
