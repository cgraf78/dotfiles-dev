# AGENTS.md

## About

The public `dev` profile overlay for
[cgraf78/dotfiles](https://github.com/cgraf78/dotfiles). Only files under
`home/` are linked into `$HOME`. The base repo selects this overlay; nothing
here defines or changes profile selection.

- Configuration may use only tools this overlay owns or inherits from the
  base and editor (`dotfiles-nvim`) layers.
- No private, employer-specific, host-specific, or user-specific material.
- A capability's install declaration, config, runtime hooks, focused tests,
  doctor checks, and docs live and move together.
- Public agent rules and `agent-rules-sync` stay in base. This overlay adds
  rule and playbook fragments only for tools it owns
  (`home/.config/agent-rules/`).

## Layout

- `home/`: the payload; suites live in `home/.local/lib/dotfiles/tests/`.
- `dot/profile-deactivate`: Dot runs it when a machine leaves `dev`, to clean
  up generated state that removing the links does not.
- `docs/`: component docs.
- `test/run`: the suite runner. `test/workflow-test`: the repo contract.
- `test/lib/`: vendored from cgraf78/actions `capability-harness/`.
- `.selene.toml` and `vim.yml`: repo-level Lua lint config that
  `test/workflow-test` requires.

## Testing

- `test/run`: what CI runs. It needs network (it installs the latest Dot
  release unless `DOT_TEST_DOT_RELEASE_TAG` names one; `test/workflow-test`
  rejects a tag committed in `test/run` or a workflow) and `nvim` in a system
  root or an absolute `CAPABILITY_TEST_NVIM`.
- `test/run --termux`: the CI Termux smoke.
- `test/run --provider-compatibility` (CI only): needs
  `DOT_TEST_{CHECKRUN,SLEY,GIT_TOOLS,AGENTGUARD}_ROOT` checkouts with a
  `cgraf78/<repo>` origin, an absolute `DOT_TEST_WATCHEXEC_BIN`,
  `CAPABILITY_TEST_{YQ,NODE,NVIM}`, and Neovim 0.11.2 or newer.
- `test/workflow-test` (`--remote` also checks GitHub and needs `gh`).
- Locally, the `nvim-dev` suite is skipped when Neovim is older than 0.11.2.

## Test isolation

Suites run on a restricted PATH: only the `required_commands` in `test/run`,
resolved from `$PREFIX/bin` (Termux), `/opt/homebrew/bin`, `/usr/local/bin`,
`/usr/bin`, and `/bin`; `~/.local/bin` and mise shims are not visible. A new
tool needs three paired edits:
`required_commands`, the `profiles:` line in `.github/workflows/test.yml`, and
the matching `grep -Fx` line in `test/workflow-test`.

## CI and generated files

- CI's ShellCheck job fails on any shell program missing from
  `.github/shellcheck-files.txt` (untracked files included) and on stale rows;
  `test/run` runs no ShellCheck. Rows must be `program`, and every file
  under `dot/` needs one. Before pushing, run
  `SHELLCHECK_EXCLUDE_CODES=SC1091 bash <actions@lock>/.github/actions/shellcheck-inventory/run.sh "$PWD" .github/shellcheck-files.txt`.
- Every executable suite must be listed in `.github/dot-test-suites.txt`;
  `test/run` rejects unlisted ones.
- `.github/cgraf78-actions.lock` and every `uses: cgraf78/actions/...@sha`
  move together, only via `consumer-ci/sync.sh <this checkout>` run from
  cgraf78/actions at the locked SHA. The same command refreshes `test/lib/*`;
  change those files in actions, never here.
- `home/.local/share/checkrun/schemas/` is refreshed by a daily bot PR, and
  `home/.config/mise/mise.lock` by a weekly one. Don't hand-edit either.
- `test/workflow-test` pins exact lines of `test.yml` (name, cron, profiles,
  `setup: none`, provider checkouts, pinned yq/Neovim/watchexec URLs and
  hashes), both gitleaks commands in `README.md`, the LICENSE and
  `.gitignore` bytes, and the sha256 of `home/.config/checkrun/selene.toml`.
  Edit it together with any of those.
- `retry-infrastructure.yml` keys on the workflow name `Tests`; keep it.
- The `installed-profiles` job calls base
  `installed-profiles.yml@main`, and the provider job checks out checkrun,
  sley, git-tools, and agentguard at `main`. A change in any of them can turn
  this repo red without a change here.

## Release

None; installs track `main`.
