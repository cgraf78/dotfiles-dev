# dotfiles-dev

[![Tests](https://github.com/cgraf78/dotfiles-dev/actions/workflows/test.yml/badge.svg)](https://github.com/cgraf78/dotfiles-dev/actions/workflows/test.yml)

Public development capability overlay for the top-level
[`cgraf78/dotfiles`](https://github.com/cgraf78/dotfiles) environment.

Only files below `home/` are linked into a user's home directory. The
top-level dotfiles profile selects this repository; this overlay never defines
or changes profile selection. Installation declarations, configuration,
runtime hooks, focused tests, doctor checks, and component documentation move
together under the capability that owns them.

Configuration here may use only tools owned by this overlay or inherited from
a lower profile. Private, employer-specific, host-specific, and user-specific
material is forbidden.

The overlay owns global Git configuration and advanced Git tooling,
development toolchains and checks, public agent tooling, VS Code policy, and
additive development Neovim modules. Public agent rules and
`agent-rules-sync` remain in the base `dotfiles` repository.

The tracked overlay payload is roughly 5 MiB. A clean cumulative `dev` profile
is expected to use about 2.5–4.5 GiB after its declared tools are installed;
language package caches and project build outputs are excluded from that
estimate.

## Repository maintenance

The schema and Mise-lock refresh workflows require a newly generated deploy key
scoped only to this repository. Provisioning that key and configuring its
private half as the `DOTFILES_DEV_MAINTENANCE_DEPLOY_KEY` Actions secret is a
Phase B pre-merge prerequisite; no key or credential is copied from another
repository.

Run both public-boundary scans with this repository's allowlist:

```bash
gitleaks dir . --config home/.gitleaks.toml --redact --no-banner
gitleaks git . --config home/.gitleaks.toml --redact --no-banner
```
