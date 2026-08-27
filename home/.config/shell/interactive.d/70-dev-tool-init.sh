# shellcheck shell=bash
# Adapter used by dev integrations; `_tool_init` is inherited from base.

_tool_shdeps_source_emit() {
  local dep=$1 asset_path=$2 asset
  local shdeps_assets="$HOME/.local/lib/dotfiles/shdeps-assets.sh"

  [[ -r $shdeps_assets ]] || return 1
  # shellcheck disable=SC1090  # stable dotfiles helper path
  . "$shdeps_assets"
  asset=$(dot_shdeps_dep_file "$dep" "$asset_path" 2>/dev/null) || return 1
  [[ -r $asset ]] || return 1
  cat "$asset"
}
