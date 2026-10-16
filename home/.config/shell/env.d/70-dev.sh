# shellcheck shell=bash
# Development tool environment. Final PATH priority is owned by base.

# Base shell-loader.sh owns _shell_env_set: authoritative in interactive and
# login shells, fill-only in non-interactive children so caller overrides
# survive. Fall back to a plain export on a base checkout without it.
command -v _shell_env_set >/dev/null 2>&1 ||
  _shell_env_set() { export "$1=$2"; }

if [ -d "$HOME/.bun/bin" ]; then
  _shell_env_set BUN_INSTALL "$HOME/.bun"
fi

# This overlay ships the Checkrun schema policy, so its absence means a broken
# install, not "no schemas". Requiring it makes Checkrun exit 2 when the policy
# is missing or its validator cannot run (uv, installed on every platform here,
# normally bootstraps one), and Sley's commit gate fails on that exit 2 instead
# of passing a commit with no schema enforced.
_shell_env_set CHECKRUN_SCHEMA_POLICY_REQUIRED 1

# The Sley and agentguard blocks already yield to any inherited setting in
# every mode, so a caller or test can point them at another repository. The
# agentguard values are read by hook processes, whose environment comes from
# the agent harness rather than from tool shells, so a tool shell cannot use a
# fill-only load to weaken them.
if [ -z "${SLEY_BARE_REPO_GIT_DIR+x}" ] && [ -d "$HOME/.dotfiles" ]; then
  export SLEY_BARE_REPO_GIT_DIR="$HOME/.dotfiles"
  export SLEY_BARE_REPO_WORK_TREE="$HOME"
fi

if [ -z "${AGENTGUARD_PROTECTED_BARE_GIT_DIR+x}" ] && [ -d "$HOME/.dotfiles" ]; then
  export AGENTGUARD_PROTECTED_BARE_GIT_DIR="$HOME/.dotfiles"
  export AGENTGUARD_PROTECTED_BARE_GIT_WORK_TREE="$HOME"
  export AGENTGUARD_PROTECTED_BARE_GIT_ALIASES=DOTFILES
  export AGENTGUARD_PROTECTED_BARE_GIT_LAUNCHER="$HOME/.local/bin/git"
  export AGENTGUARD_PROTECTED_BARE_GIT_STATUS_MESSAGE="do not run base dotfiles git status with untracked files enabled. Use dot status, or inspect a scoped path with git ls-files --others --exclude-standard -- <path>."
  export AGENTGUARD_PROTECTED_BARE_GIT_LS_FILES_MESSAGE="do not list every untracked file in the base dotfiles repo. Use git ls-files --others --exclude-standard -- <path> for a scoped check."
  export AGENTGUARD_PROTECTED_BARE_GIT_CLEAN_MESSAGE="do not run unscoped git clean in the base dotfiles repo. Inspect a scoped path with git clean --dry-run -- <path>."
fi

# git-tools (`git pr-watch`) comes with this overlay, so agents here are held
# to watching the pull requests they push: AgentGuard's Stop hook blocks once
# per push or watcher exit when nothing watches one, and its pre-bash hook
# blocks foreground or detached watcher launches. An inherited value wins
# (0 turns both back into reminders).
export AGENTGUARD_WATCH_BLOCK="${AGENTGUARD_WATCH_BLOCK:-1}"
export AGENTGUARD_EDIT_CHURN_WARN="${AGENTGUARD_EDIT_CHURN_WARN:-10}"
export AGENTGUARD_EDIT_CHURN_BLOCK="${AGENTGUARD_EDIT_CHURN_BLOCK:-20}"
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS="${OPENCODE_DISABLE_CLAUDE_CODE_SKILLS:-1}"

# shellcheck disable=SC1091  # optional local Rust bootstrap
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
true
