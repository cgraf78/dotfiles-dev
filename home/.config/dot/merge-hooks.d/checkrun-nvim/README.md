# Checkrun Neovim Metadata Merge Hook

This directory declares the `checkrun-nvim` merge-hook instance. It has no
declarative source fragments: the hook regenerates Neovim's Checkrun editor
metadata with `checkrun editor-metadata --json` whenever `checkrun` is
installed.

Neovim reads that one JSON projection at startup for Checkrun capabilities and
schema associations, so it never starts Checkrun's Python while loading. The
projection is derived from the live association policy
(`~/.config/checkrun/associations.json`) and the installed Checkrun, so it is
generated on every `dot update` rather than tracked; a tracked copy went stale
whenever either input changed without a manual regeneration.

The hook writes `dot/overlays/dev/checkrun-editor-metadata.json` under the XDG
state directory (an absolute `XDG_STATE_HOME`, otherwise `~/.local/state`)
through Dot's atomic commit, which replaces only a regular file. It leaves the
file untouched when the output is unchanged, and keeps the previous projection
and warns with the cause when Checkrun fails, exceeds
`DOT_CHECKRUN_NVIM_TIMEOUT_SECONDS` (default 60), or emits a document whose shape
Neovim's adapter would ignore. `~/.config/nvim/lua/config/checkrun-nvim.lua`
reads the same path, and dev profile deactivation removes it.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/checkrun-nvim.sh`.
