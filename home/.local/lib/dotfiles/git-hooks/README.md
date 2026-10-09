# Git Hooks

This directory is the global Git hook directory selected by
`~/.config/git/config` through `core.hooksPath`.

It lives under `~/.local/lib/dotfiles` because these files are executable,
dotfiles-owned client policy. It is separate from the standalone Dot public
library because Git invokes these entry points directly; the runtime does not
load or dispatch them.

## Hooks

- `pre-commit`, `pre-merge-commit`, `pre-applypatch`, `prepare-commit-msg`, and
  `commit-msg` are activation shims for Sley's generic Git hooks.
- `sley-provider-hook` resolves the Shdeps-managed Sley checkout, verifies the
  requested provider hook and matching CLI are executable, and dispatches
  without evaluating a command string.
- `sley-commit-gate` adds the one dotfiles-specific policy described below,
  then delegates the portable readiness behavior to Sley.
- `commit-msg` selects dotfiles' advanced message-policy provider before
  dispatching to Sley's generic finalized-message hook.
- `pre-push` refuses direct pushes to `main` or `master` of the owner's
  GitHub repositories.
- `policy.sh` is a sourced helper, not a hook: it holds the remote-ownership
  parser and the AgentGuard session check that `commit-msg` and `pre-push`
  share.

Sley owns the reusable decisions about ordinary commits, merges, patches, and
Git sequencer operations. Keeping those implementations in Sley gives direct
Sley users the same behavior and prevents this activation directory from
becoming a fork.

Dotfiles retains one intentionally local rule: `sley-commit-gate` sets
`SLEY_SKIP_UNTRACKED=1` for the base dotfiles client. Its separate Git directory
uses all of `$HOME` as the worktree, in both the canonical explicit-worktree
layout and the supported legacy bare layout, so an untracked-file walk would be
both expensive and unrelated to the staged commit scope. Sley does not need to
know that personal repository layout.

Normal activation asks shdeps for the `cgraf78/sley` dependency through the
base `dot_shdeps_dep_file` helper, so shdeps keeps owning the install root,
development-clone precedence, and host filters. The resolved `bin/sley` CLI
selects the root that also supplies the `share/sley/hooks/git/` hooks.
`DOT_SLEY_ROOT` may point at a complete Sley checkout for cross-repository
development and integration tests; selecting both artifacts from one root
prevents hook/CLI version skew. The override is not required on fleet machines
because `dot update` keeps the Shdeps dependency current.

## Agent and Owner Policy

The global hook directory reaches every clone on the machine, so policy that
expresses the owner's conventions is scoped by the remote's GitHub owner
(`cgraf78`), and policy for AI agents by AgentGuard's session detection. Third
party clones, owner-hosted forks (an `upstream` remote owned by someone
else), and human commits keep the advisory behavior.

- In an agent session, `commit-msg` forces `COMMIT_MSG_STRICT=1` when
  `origin` is owner-owned, so the validator rejects title-only messages,
  Markdown section headers, misordered or unseparated sections, and unwrapped
  body text. Agents may not use `GITHOOK_COMMITMSG_SKIP` or `COMMIT_MSG_SKIP`
  in any repository: both bypass the message gate, and skipping the hook also
  skips Sley's secret scan.
- `pre-push` blocks updating or deleting `refs/heads/main` and
  `refs/heads/master` on owner repositories, except for the private
  `dotfiles-personal` and `dotfiles-work` overlays, whose fast-forward pushes
  to `main` are intended. Forks, creating `main` on a new repository, tags,
  and feature branches pass, and `scripts/release.sh --push` keeps working
  because Git does not hand the hook its already-merged `main`. Humans may
  override with `GIT_ALLOW_PUSH_MAIN=1`; agent sessions may not.
- If AgentGuard cannot be resolved, both hooks warn and apply the human
  policy rather than blocking work on a broken install.

These hooks cannot see Git's `--no-verify` or `-c core.hooksPath=` flags,
development overrides such as `DOT_SLEY_ROOT` and `DOT_COMMIT_MSG_VALIDATOR`,
or an agent command relayed through a human tmux pane, so none of those are
refused today. Refusing them for agents is planned for AgentGuard's command
guard.

## Policy

Keep hooks thin. Portable readiness and commit-message provider dispatch belong
in Sley, formatting and linting policy belongs in Checkrun, and the local
commit-message grammar belongs in `../sley-hooks/validate-commit-msg`.

Hooks that only add advisory checks may degrade gracefully when a dependency is
not installed yet. Hooks that enforce commit readiness should fail closed and
explain which dependency or native bypass is needed.
