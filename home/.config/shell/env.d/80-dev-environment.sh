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

if [ -f "$HOME/.config/gh/github-pat" ]; then
  # Keep a hand-written token owner-only, but repair the mode only in
  # interactive shells. env.d also loads in every non-interactive bash
  # (BASH_ENV) and zsh (~/.zshenv), where chmod would fork on each agent tool
  # call and script, and recurse without end under a test that shadows chmod
  # with a bash script; bash has no builtin to check the mode first. The gh
  # merge hook also repairs it on `dot update`.
  case $- in
    *i*) chmod 600 "$HOME/.config/gh/github-pat" 2>/dev/null || true ;;
  esac
  read -r _DOT_GITHUB_PAT <"$HOME/.config/gh/github-pat" || true
  if [ -n "${_DOT_GITHUB_PAT:-}" ]; then
    export GH_TOKEN="${GH_TOKEN:-$_DOT_GITHUB_PAT}"
    export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
    export CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
  fi
  unset _DOT_GITHUB_PAT
fi
