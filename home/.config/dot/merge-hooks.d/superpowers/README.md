# Superpowers Merge Hook

This directory declares dotfiles' `superpowers` activation policy. It has no
declarative source fragments: every `dot update` asks the tracked
`superpowers-muse-sync` provider to reconcile the shdeps-managed
`obra/superpowers` checkout with the Muse skills store.

The ownership boundary is intentionally narrow:

- `superpowers-muse-sync` owns skill enumeration, the `superpowers-` install
  prefix, store writes, and cleanup;
- dotfiles owns the `obra/superpowers` dependency declaration and activation
  timing; and
- the upstream superpowers shdeps hook runs the same provider after checkout
  changes, while this merge hook also catches skill-store drift and Muse
  installs that happened since the last upstream update.

The executable merge adapter lives at
`~/.local/lib/dotfiles/merge-hooks.d/superpowers.sh`. It deliberately contains
no sync fallback: if a partial install or isolated merge-hook run lacks Muse
or the provider, it is a no-op.
