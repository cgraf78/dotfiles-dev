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
# Run git against the repository whose commits the hooks guard: the base
# dotfiles client when its Git directory exists, otherwise whatever HOME is.
_dr_hooks_git() {
  if [[ -d $DOTFILES ]]; then
    git --git-dir="$DOTFILES" "$@"
  else
    git -C "$HOME" "$@"
  fi
}

_dr_check_git_hooks() {
  _dr_section "Git hooks"

  local want_hooks="$HOME/.local/lib/dotfiles/git-hooks"
  local output="" status=0 scope="" actual_hooks="" hook name display
  local hook_count=0 issue_count=0

  # One lookup with Git's own precedence and include handling yields the value
  # a commit would actually use, labelled with the scope that set it. Reading
  # `--global` first skipped include.path files, so a hooksPath set through an
  # include fell through to the repository lookup and was mislabelled.
  output=$(_dr_hooks_git config --show-scope --get core.hooksPath 2>/dev/null) ||
    status=$?
  if ((status == 129)); then
    # Git before 2.26 has no --show-scope; keep the value, drop the label.
    status=0
    output=$(_dr_hooks_git config --get core.hooksPath 2>/dev/null) || status=$?
    output=$'scope unknown\t'$output
  fi
  case $status in
    0) IFS=$'\t' read -r scope actual_hooks <<<"$output" ;;
    1) ;; # Git's exit status for an unset key.
    *)
      _dr_warn "core.hooksPath unchecked" "git config exited $status"
      ;;
  esac
  # Git expands a leading ~ in pathname values; compare the expanded form.
  actual_hooks="${actual_hooks/#\~/$HOME}"

  if [[ -n "$actual_hooks" && "${actual_hooks%/}" == "$want_hooks" ]]; then
    _dr_ok "core.hooksPath" "$(_dr_tilde "$want_hooks") ($scope)"
  elif [[ -n "$actual_hooks" ]]; then
    _dr_warn "core.hooksPath points elsewhere" \
      "got $actual_hooks ($scope), expected $(_dr_tilde "$want_hooks")"
  elif ((status <= 1)); then
    _dr_warn "core.hooksPath not set" \
      "dotfiles ship Git hooks in $(_dr_tilde "$want_hooks")"
  fi

  # Check every shipped hook rather than only pre-commit: Git silently skips a
  # hook it cannot execute, so a lost mode bit or a dangling link disables that
  # gate without any error. Shipped hooks and helpers have no dot in their
  # names; README.md, *.sample, *.orig, and editor backups are not hooks.
  for hook in "$want_hooks"/*; do
    [[ -e $hook || -L $hook ]] || continue
    name=${hook##*/}
    case $name in *.* | *~) continue ;; esac
    hook_count=$((hook_count + 1))
    display=$(_dr_tilde "$hook")
    if [[ ! -e $hook ]]; then
      issue_count=$((issue_count + 1))
      _dr_fail "$name hook link broken" "$display"
    elif [[ ! -f $hook ]]; then
      issue_count=$((issue_count + 1))
      _dr_fail "$name hook is not a file" "$display"
    elif [[ ! -x $hook ]]; then
      issue_count=$((issue_count + 1))
      _dr_fail "$name hook not executable" "chmod +x $display"
    fi
  done
  if ((hook_count == 0)); then
    _dr_warn "Git hooks missing" "$(_dr_tilde "$want_hooks")"
  elif ((issue_count == 0)); then
    _dr_ok "Git hooks executable" "$hook_count hook(s)"
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
