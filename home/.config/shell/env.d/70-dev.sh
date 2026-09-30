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

export AGENTGUARD_EDIT_CHURN_WARN="${AGENTGUARD_EDIT_CHURN_WARN:-10}"
export AGENTGUARD_EDIT_CHURN_BLOCK="${AGENTGUARD_EDIT_CHURN_BLOCK:-20}"
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS="${OPENCODE_DISABLE_CLAUDE_CODE_SKILLS:-1}"

# shellcheck disable=SC1091  # optional local Rust bootstrap
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
true
