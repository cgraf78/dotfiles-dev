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

# Delete installed versions that no tracked config still selects. Every
# `latest` bump otherwise leaves the previous release behind, which grew the
# global toolset to several times its live size. Mise records each config it
# loads, so a config copied into a Dot backup tree keeps pinning the versions
# it named once anything loads it there. Ignore those trees for this prune
# only; the `ignored_config_paths` setting in a config file does not affect
# which tracked configs `mise prune` honors, but the environment form does.
# Prune also keeps versions that a running process was started from, so it is
# safe during unattended cron updates. Failure is advisory: stale versions
# only cost disk space.
_mise_prune() {
  local ignored="$HOME/.dot-backup:$HOME/.dotfiles-backup"
  if [[ -n "${MISE_IGNORED_CONFIG_PATHS:-}" ]]; then
    ignored="$MISE_IGNORED_CONFIG_PATHS:$ignored"
  fi
  (cd "$HOME" && MISE_IGNORED_CONFIG_PATHS="$ignored" mise prune --yes) \
    &>/dev/null || true
}

merge() {
  _dot_tool_any_command mise || return 0
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

  # The tracked config and lockfile decide what gets installed; `dot update`
  # must not rewrite the lockfile, which is a symlink into the overlay
  # checkout. Since mise 2026.10.19 the default `lockfile_mode = "generate"`
  # makes both `mise install` and `mise prune` rebuild `mise.lock`
  # (backfilling other platforms' checksums), dirtying the checkout. Merge
  # mode only adds missing entries instead of rebuilding, and `--locked`
  # refuses to add any, so a complete committed lock stays byte-identical.
  # Forced over any caller value; the scheduled lock-refresh workflow owns
  # lock updates.
  local -x MISE_LOCKFILE_MODE=merge

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

  # Prune only after the locked toolset is fully installed, so a failed update
  # never removes the versions still serving as the working generation.
  if ((install_ok)); then
    _mise_prune
  fi
}
