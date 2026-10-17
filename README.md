# dotfiles-dev

[![Tests](https://github.com/cgraf78/dotfiles-dev/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/cgraf78/dotfiles-dev/actions/workflows/test.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-MIT-67ac09)](LICENSE)

The development layer of my [dotfiles](https://github.com/cgraf78/dotfiles):
global Git config, hooks, and workflow tools
([git-tools](https://github.com/cgraf78/git-tools),
[sley](https://github.com/cgraf78/sley)), Rust, Go, and Python toolchains,
mise-managed linters, formatters, and language servers, VS Code settings,
Neovim LSP, debug, and format modules,
[Checkrun](https://github.com/cgraf78/checkrun) format and lint dispatch, and
AI-agent tooling ([agentguard](https://github.com/cgraf78/agentguard),
[Hive Memory](https://github.com/cgraf78/hive-memory),
[gstack](https://github.com/garrytan/gstack)).

It is an [overlay](https://github.com/cgraf78/dot/blob/main/docs/overlays.md):
a repo whose `home/` tree is linked into `$HOME` on top of the base dotfiles.
Machines get it when their dotfiles profile is `dev`, which also includes the
[dotfiles-nvim](https://github.com/cgraf78/dotfiles-nvim) editor layer.

This is my personal setup. The files under `home/` mirror `$HOME`, so you can
read and copy individual configs without installing anything. A clean `dev`
profile uses about 2.5–4.5 GiB once its tools are installed, excluding
language package caches and project build outputs.

Maintainer and agent notes (ownership rules, tests, CI) are in
[AGENTS.md](AGENTS.md).

## Repository maintenance

Run both public-boundary scans with this repository's allowlist:

```bash
gitleaks dir . --config home/.gitleaks.toml --redact --no-banner
gitleaks git . --config home/.gitleaks.toml --redact --no-banner
```
