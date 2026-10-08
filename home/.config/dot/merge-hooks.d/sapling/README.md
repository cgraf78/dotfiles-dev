# Sapling Merge Hook

This directory declares the `sapling` merge-hook instance. Its declarative
source is the ordered `hgrc.d/` family in this directory.

Fragments are native hgrc snippets, preferably named `*.ini` for editor
highlighting. The hook still accepts legacy `*.hgrc` fragments. The hook
expands `$HOME`, `${HOME}`, and `~` so fragments can stay portable across
machines. It also replaces each `${shdeps:<owner>/<repo>/<relative-path>}`
token (the `shdeps:` reference grammar the Checkrun editor metadata uses)
with the file shdeps resolves through `dot_shdeps_dep_file`, so fragments
never spell shdeps' install layout. A token that cannot be resolved
means the provider is absent, and the hook then leaves `~/.hgrc` untouched,
just as it does when a hook executable is missing.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/sapling.sh`.

`hgrc.d/10-sley.ini` directly activates Sley's provider-owned Sapling commit
gate at the path shdeps resolves during the merge. The hgrc entries are the
activation layer, so an additional dotfiles launcher would add indirection
without owning policy. Command classification, metadata-only skips, and
readiness execution remain reusable Sley behavior.
