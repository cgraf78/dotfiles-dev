# shellcheck shell=bash
# dot doctor: development shell integrations.

_dr_check_dev_integrations() {
  local shell_name path content
  _dr_section 'Development shell integrations'

  for shell_name in bash zsh; do
    path="$HOME/.config/shell/interactive.d/80-dev-integrations.$shell_name"
    if [[ ! -r $path ]]; then
      _dr_fail "$shell_name dev integrations missing" "$(_dr_tilde "$path")"
      continue
    fi
    content=$(<"$path")
    if [[ $content == *'_tool_init sley '* &&
      $content == *'_tool_init git-tools '* &&
      $content == *'_tool_init direnv '* ]]; then
      _dr_ok "$shell_name dev integrations" 'sley, git-tools, direnv'
    else
      _dr_warn "$shell_name dev integrations incomplete" "$(_dr_tilde "$path")"
    fi
  done
}
# ---------------------------------------------------------------------------
# Git hooks
# ---------------------------------------------------------------------------
_dr_check_git_hooks() {
  _dr_section "Git hooks"

  local want_hooks="$HOME/.local/lib/dotfiles/git-hooks"
  # Check global first, then fall back to the dotfiles repo-local config.
  local actual_hooks scope=""
  actual_hooks=$(git config --get --global core.hooksPath 2>/dev/null || echo "")
  if [[ -n "$actual_hooks" ]]; then
    scope="global"
  elif [[ -d "$DOTFILES" ]]; then
    actual_hooks=$($GIT config --get core.hooksPath 2>/dev/null || echo "")
    [[ -n "$actual_hooks" ]] && scope="repo-local"
  fi
  # Normalize ~
  actual_hooks="${actual_hooks/#\~/$HOME}"

  if [[ "$actual_hooks" == "$want_hooks" ]]; then
    _dr_ok "core.hooksPath" "$(_dr_tilde "$actual_hooks") ($scope)"
  elif [[ -z "$actual_hooks" ]]; then
    _dr_warn "core.hooksPath not set" \
      "dotfiles ship a pre-commit hook — see $(_dr_tilde "$want_hooks")"
  else
    _dr_warn "core.hooksPath points elsewhere" "got $actual_hooks, expected $(_dr_tilde "$want_hooks")"
  fi

  if [[ -x "$want_hooks/pre-commit" ]]; then
    _dr_ok "pre-commit hook present and executable"
  elif [[ -f "$want_hooks/pre-commit" ]]; then
    _dr_fail "pre-commit hook not executable" "chmod +x $want_hooks/pre-commit"
  else
    _dr_warn "pre-commit hook missing" "$want_hooks/pre-commit"
  fi
}

# Hive Memory binary/config skew.
#
# The hm config is dotfiles-managed and syncs to machines independently of
# hive-memory releases, so a machine can carry a config key its installed hm
# does not understand yet (or no longer understands). hm deliberately
# downgrades unknown keys to a stderr warning so the hook path never fails —
# which means the configured memory policy silently stays on defaults unless
# something surfaces the skew. This check is that something.
_dr_check_hive_memory() {
  _dr_section "Hive Memory"

  if ! command -v hm >/dev/null 2>&1; then
    _dr_skip "hive-memory config" "hm not installed"
    return 0
  fi

  # `stores list` is the cheapest read-only command that still loads (and
  # therefore validates) the full config. Capture stderr only.
  local stderr unknown
  if ! stderr=$(hm stores list --json 2>&1 >/dev/null); then
    _dr_warn "hm config unchecked" "${stderr%%$'\n'*}"
    return 0
  fi

  unknown=$(printf '%s\n' "$stderr" | grep -F 'unknown config key' || true)
  if [[ -n "$unknown" ]]; then
    _dr_warn "hm binary behind configured keys" \
      "${unknown%%$'\n'*} — update hive-memory (shdeps) or drop the key"
    return 0
  fi
  _dr_ok "hm understands configured keys"
}
