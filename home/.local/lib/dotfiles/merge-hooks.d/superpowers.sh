# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Reconcile obra/superpowers skills into the Muse skills store on every
# dot update.
#
# The shdeps hook covers checkout changes; this second activation point covers
# skill-store drift and Muse installs that happened since the last upstream
# update. All reusable behavior belongs to the provider, leaving this consumer
# intentionally thin.

# Keep the executable provider below the validated extension root, resolved
# from this hook's location so the wiring survives verification checkouts.
_dot_superpowers_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
_dot_superpowers_muse_sync="${SUPERPOWERS_MUSE_SYNC:-$_dot_superpowers_hook_dir/lib/superpowers-muse-sync}"

merge() {
  _dot_tool_present muse || return 0
  [[ -x $_dot_superpowers_muse_sync ]] || return 0

  "$_dot_superpowers_muse_sync" sync
}
