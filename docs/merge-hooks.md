# Development merge hooks

This overlay contributes merge hooks for development applications including
Git, GitHub CLI, agent tools, Mise, Sapling, and VS Code. The standalone Dot
client discovers these hooks only when the selected overlay is eligible for
automatic extensions; isolated repository tests invoke their public interfaces
explicitly.

The `zz-codex-trust-prune` serial barrier prunes stale Codex project-trust
entries from `~/.codex/config.toml` after the `codex` hook has merged that
file; its `zz-` name and barrier scheduling keep it from racing that merge.
