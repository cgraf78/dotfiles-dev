# Mise Merge Hook

This directory declares the `mise` merge-hook instance. It has no declarative
source fragments: the hook synchronizes the tracked global mise config and lock
file by running `mise install --locked` during `dot update`. After a successful
install it runs `mise prune`, ignoring configs under `~/.dot-backup` and
`~/.dotfiles-backup`, so superseded and backup-pinned versions are removed.

Every mise call in the hook runs with `MISE_LOCKFILE_MODE=merge`. Merge mode
only adds missing lock entries rather than rebuilding the file, and
`--locked` refuses to add any, so `dot update` leaves a complete committed
`mise.lock` unchanged. The lockfile changes only through the scheduled
lock-refresh pull request.

Termux skips this hook because the tracked global toolset targets Linux and
macOS release assets. Android-supported dependencies come from Termux packages
instead.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/mise.sh`.
