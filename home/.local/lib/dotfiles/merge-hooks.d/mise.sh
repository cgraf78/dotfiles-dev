# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Sync global mise-managed tools on every `dot update`.
#
# This runs as a merge hook rather than a shdeps post-install hook because the
# tracked toolset (`~/.config/mise/config.toml` and `mise.lock`) can change even
# when the `mise` package itself does not. `mise install --locked` is idempotent,
# so the correct boundary is the regular dot update path. The committed lockfile
# is authoritative, so installs fail closed instead of resolving new assets.

_mise_interactive() {
  [[ -t 0 && -t 1 ]]
}

merge() {
  _dot_tool_present mise || return 0
  # Mise's tracked global toolset targets Linux and macOS release assets.
  # Termux dependencies come from its native packages instead; asking Mise to
  # resolve them as Android assets produces deterministic unsupported-platform
  # failures and cannot install a useful generation.
  dot_hook_platform_match android && return 0

  local config="$HOME/.config/mise/config.toml"
  if [[ ! -f "$config" ]]; then
    return 0
  fi

  dot_hook_log "  mise"

  mise trust "$config" &>/dev/null || true

  local github_token install_ok=0
  github_token="${MISE_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"

  # Headless cron runs on Linux can leak a session bus/keyring pair when
  # `gh auth token` wakes up the credential stack, so only fall back to
  # `gh` when the merge is running interactively and owns the account HOME.
  if [[ -z "$github_token" ]] && _mise_interactive; then
    local gh_command
    if _dot_account_scoped_command \
      "Mise GitHub token lookup" gh "${DOT_TEST_GH:-}"; then
      gh_command="$REPLY"
      github_token="$("$gh_command" auth token 2>/dev/null || true)"
    fi
  fi

  if [[ -n "$github_token" ]]; then
    if (cd "$HOME" && MISE_GITHUB_TOKEN="$github_token" mise install --locked); then
      install_ok=1
    fi
  else
    if (cd "$HOME" && mise install --locked); then
      install_ok=1
    fi
  fi

  if ((install_ok)); then
    # SuperHTML moved from the deprecated UBI backend to the GitHub backend.
    # Prune only that retired payload, and let mise preserve it if another
    # tracked config still references the old provider.
    (cd "$HOME" && mise prune --tools --yes ubi:kristoff-it/superhtml) \
      &>/dev/null || true
  fi
}
