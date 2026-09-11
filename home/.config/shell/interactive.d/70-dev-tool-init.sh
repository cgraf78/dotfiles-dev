# shellcheck shell=bash
# Adapter used by dev integrations; `_tool_init` is inherited from base.

# Upward `.envrc` probe for the direnv hook gate (see 80-dev-integrations.*).
# Status 0 means an `.envrc` exists upward (the hook must run); status 1
# means none exists (skipping the hook is safe when no environment is loaded).
# direnv resolves the upward chain physically, so when the logical chain holds
# no symlink it is scanned alone (it IS the physical chain), otherwise both
# chains are scanned: skipping needs both clean, which keeps symlinked
# directories, `.env`-only directories (direnv ignores `.env`), unreadable
# files, and vanished working directories behavior-identical to the raw hook
# (all of those either match `-e` or take the run-the-hook default below).
_dot_upward_envrc() {
  local _dir=${PWD:-} _phys="" _saw_link=0
  [[ -n $_dir ]] || return 0
  [[ -d $_dir ]] || return 0
  _dir=${_dir%/}
  [[ -n $_dir ]] || _dir=/
  while :; do
    [[ -e "$_dir/.envrc" || -L "$_dir/.envrc" ]] && return 0
    [[ -L "$_dir" ]] && _saw_link=1
    [[ $_dir == / ]] && break
    _dir=${_dir%/*}
    [[ -n $_dir ]] || _dir=/
  done
  ((_saw_link)) || return 1
  _phys=$(pwd -P 2>/dev/null) || return 0
  [[ -n $_phys && $_phys != "${PWD:-}" ]] || return 1
  _dir=${_phys%/}
  [[ -n $_dir ]] || _dir=/
  while :; do
    [[ -e "$_dir/.envrc" || -L "$_dir/.envrc" ]] && return 0
    [[ $_dir == / ]] && return 1
    _dir=${_dir%/*}
    [[ -n $_dir ]] || _dir=/
  done
  return 1
}

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
