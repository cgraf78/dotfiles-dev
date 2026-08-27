# shellcheck shell=bash
# Environment owned by development workflows and agents.

export DS_DEV_CHATBOT="${DS_DEV_CHATBOT:-claude}"
export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml"
export GITHOOK_PRECOMMIT_STRICT_LINT=1

if [ -f "$HOME/.config/gh/github-pat" ]; then
  chmod 600 "$HOME/.config/gh/github-pat" 2>/dev/null || true
  read -r _DOT_GITHUB_PAT <"$HOME/.config/gh/github-pat" || true
  if [ -n "${_DOT_GITHUB_PAT:-}" ]; then
    export GH_TOKEN="${GH_TOKEN:-$_DOT_GITHUB_PAT}"
    export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
    export CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
  fi
  unset _DOT_GITHUB_PAT
fi
