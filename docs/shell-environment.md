# Development environment

Ordered files under `home/.config/shell/env.d/` provide development-only
environment variables. Base owns `GH_TOKEN` loading and the user-owned
`~/.config/gh/github-pat` file. When `GH_TOKEN` is nonempty, this overlay supplies
`GITHUB_PERSONAL_ACCESS_TOKEN` and `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN` aliases,
preserving explicit caller values. No credential or site-specific value is
stored in this repository.
