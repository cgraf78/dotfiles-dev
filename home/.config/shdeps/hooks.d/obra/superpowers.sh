# shellcheck shell=bash
# Keep Muse skill registration coupled to the upstream checkout lifecycle. The
# provider owns the skill enumeration and store writes; this hook owns only the
# decision to reconcile immediately after shdeps changes superpowers.
#
# The provider lives below the overlay's hook library root rather than on PATH
# because it is plumbing, not a user command. An isolated shdeps run without
# the overlay linked stays a quiet no-op.
_superpowers_muse_sync="${SUPERPOWERS_MUSE_SYNC:-$HOME/.local/lib/dotfiles/merge-hooks.d/lib/superpowers-muse-sync}"

post() {
  [[ -x $_superpowers_muse_sync ]] || return 0
  "$_superpowers_muse_sync" sync
}

uninstall() {
  [[ -x $_superpowers_muse_sync ]] || return 0
  "$_superpowers_muse_sync" uninstall
}
