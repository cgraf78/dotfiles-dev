# shellcheck shell=bash
# Environment owned by development workflows and agents.

# Base shell-loader.sh owns _shell_env_set: authoritative in interactive and
# login shells, fill-only in non-interactive children so caller overrides
# survive. Fall back to a plain export on a base checkout without it.
command -v _shell_env_set >/dev/null 2>&1 ||
  _shell_env_set() { export "$1=$2"; }

# The work overlay also sets DS_DEV_CHATBOT; every env.d writer of a
# helper-managed name must use the helper.
_shell_env_set DS_DEV_CHATBOT claude
_shell_env_set LG_CONFIG_FILE "$HOME/.config/lazygit/config.yml"
_shell_env_set GITHOOK_PRECOMMIT_STRICT_LINT 1

# Base owns GitHub credential loading. Development consumers use these aliases,
# while explicit caller values survive both authoritative and fill-only loads.
if [ -n "${GH_TOKEN:-}" ]; then
  _shell_env_set GITHUB_PERSONAL_ACCESS_TOKEN "${GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
  _shell_env_set CODEX_GITHUB_PERSONAL_ACCESS_TOKEN "${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
fi
