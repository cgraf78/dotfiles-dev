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

Dotfiles installs the PATH-visible `hm` command through a shdeps hook. That
hook points `hm` at the dotfiles launcher, while the upstream binary remains
available behind an internal `hm-core` path.
