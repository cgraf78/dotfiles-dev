# shellcheck shell=bash
# Strip the Grok vendor installer block after grok/agent return. The installer
# and its auto-update append to the base thin loaders (~/.zshrc, ~/.bashrc),
# and `agent` shares the same binary, so argv sniffing is the wrong trigger.
# Base owns those loaders and the strip helper; this overlay owns Grok, so it
# owns the wrappers that call the helper after each launch.

_grok_rc_lib="$HOME/.local/lib/dotfiles/shell-grok-rc.sh"
# Keep a recovery shell if the base helper is absent; grok still runs from
# PATH, and the base grok-rc merge hook strips during `dot update`.
if [[ ! -r "$_grok_rc_lib" ]]; then
  unset _grok_rc_lib
  return 0
fi
# shellcheck disable=SC1090  # stable path under $HOME, deployed by base
. "$_grok_rc_lib"
unset _grok_rc_lib

_grok_run() {
  local cmd=$1
  shift
  command "$cmd" "$@"
  local st=$?
  dot_grok_strip_installer_rc
  return "$st"
}

grok() { _grok_run grok "$@"; }
agent() { _grok_run agent "$@"; }
