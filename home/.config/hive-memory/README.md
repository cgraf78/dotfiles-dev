# Hive Memory Config

This directory owns the portable configuration for the standalone Hive Memory
tool. The tool implementation lives in the `cgraf78/hive-memory` dependency
repo. Hive automatically layers an optional sibling `config.local.toml` over
the tracked `config.toml`; private overlays may intentionally track that local
file when an override is durable across their machines.

## Boundaries

- Keep portable store defaults, scopes, agent permissions, privacy policy, and
  offline behavior in this profile's `config.toml`.
- Keep private or machine-specific store roots in `config.local.toml`. Tables
  merge recursively; scalars and arrays replace the base value.
- Keep startup context on the relevance strategy by default so durable
  preferences and project facts are automatic while incidents, references, and
  raw notes remain searchable instead of being injected into every session.
- Keep command implementation and schema behavior in the Hive Memory repo.
- Keep agent-runtime detection in the tracked dotfiles launcher
  [`.local/bin/hm`](../../.local/bin/hm).

The `cgraf78/hive-memory` entry in
[`30-dev.conf`](../shdeps/30-dev.conf) installs the upstream binary at
`~/.local/share/cgraf78/hive-memory/hm`. The tracked launcher is the
PATH-visible `hm` command and delegates to that fixed path.

The old `~/.local/share/hive-memory/bin/hm-core` copy is a legacy layout. The
`hive-memory` merge hook deletes it only when
`DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION=1` is exported, `~/.local/bin/hm` is
a regular file (not a symlink) carrying the launcher's ownership marker, and
that launcher runs `--version` against the stable payload. Neither Dot nor the
base dotfiles export that variable, and overlay links install the launcher as
a symlink, so ordinary `dot update` runs leave any legacy copy in place.
