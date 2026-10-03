# shellcheck shell=bash
# dot doctor: development shell integrations.

# Every shell asset the dev integrations load through
# `_tool_init NAME _tool_shdeps_source_emit DEP ASSET`, as NAME DEP ASSET
# triples. Keep this aligned with interactive.d/80-dev-integrations.{bash,zsh};
# the dev-doctor suite fails when they drift apart.
_DR_DEV_SHELL_ASSETS=(
  sley cgraf78/sley share/sley/shell.sh
  git-tools cgraf78/git-tools share/git-tools/shell.sh
)
# Deadline in seconds for the asset probe: two `shdeps dep-file` lookups.
_DR_DEV_SHELL_DEADLINE=10

# Probe what an interactive shell actually does at startup. `_tool_init`
# skips an integration silently when its command is missing or its init
# fails, and keeps sourcing the last good cache for up to a week, so a
# provider asset that stopped resolving only shows up days later as missing
# shell functions. Resolve each asset through the overlay's own adapter
# (70-dev-tool-init.sh, which loads base's shdeps helper) in one bare Bash
# with a private cache, so a cached answer cannot hide a broken resolution
# and the user's cache is left alone. Resolution is the same in Bash and
# Zsh, so one shell covers both. direnv's hook comes from the binary itself,
# so PATH is all it needs.
_dr_check_dev_integrations() {
  local adapter=$HOME/.config/shell/interactive.d/70-dev-tool-init.sh
  local cache output='' status=0 name dep asset index issues=0 list=''
  local -a names=()
  _dr_section 'Development shell integrations'

  if [[ ! -r $adapter ]]; then
    _dr_warn 'dev shell integration adapter missing' \
      "$(_dr_tilde "$adapter"); run 'dot update'"
    issues=1
  elif ! cache=$(mktemp -d "${TMPDIR:-/tmp}/dot-doctor-dev-shell.XXXXXX" 2>/dev/null); then
    _dr_warn 'dev shell integrations unchecked' 'could not create a temporary cache directory'
    issues=1
  else
    # BASH_ENV and ENV would load the user's env.d into the probe, which
    # costs time and is not how the interactive files run. The worker's own
    # Bash is 4 or newer; the first `bash` on PATH may be macOS's 3.2.
    # shellcheck disable=SC2016  # $1... expand in the probe shell.
    output=$(XDG_CACHE_HOME=$cache _dr_dev_bounded "$_DR_DEV_SHELL_DEADLINE" \
      env -u BASH_ENV -u ENV "$BASH" --noprofile --norc -c '
        . "$1" || exit 3
        shift
        while (($# >= 3)); do
          if _tool_shdeps_source_emit "$2" "$3" >/dev/null 2>&1; then
            printf "%s=1\n" "$1"
          else
            printf "%s=0\n" "$1"
          fi
          shift 3
        done
      ' dot-doctor "$adapter" "${_DR_DEV_SHELL_ASSETS[@]}" 2>/dev/null </dev/null) ||
      status=$?
    rm -rf "$cache" 2>/dev/null || true
    if _dr_dev_deadline_status "$status"; then
      _dr_warn 'dev shell integrations unchecked' \
        "resolving their shell assets took longer than ${_DR_DEV_SHELL_DEADLINE}s"
      issues=1
    else
      for ((index = 0; index < ${#_DR_DEV_SHELL_ASSETS[@]}; index += 3)); do
        name=${_DR_DEV_SHELL_ASSETS[index]}
        dep=${_DR_DEV_SHELL_ASSETS[index + 1]}
        asset=${_DR_DEV_SHELL_ASSETS[index + 2]}
        names+=("$name")
        case $'\n'$output$'\n' in
          *$'\n'"$name=1"$'\n'*) ;;
          *$'\n'"$name=0"$'\n'*)
            _dr_warn "$name shell integration unavailable" \
              "$dep $asset does not resolve, so new shells skip it; run 'dot update'"
            issues=1
            ;;
          *)
            # No verdict at all: the adapter did not load or the shell died.
            _dr_warn "$name shell integration unchecked" "the asset probe exited $status"
            issues=1
            ;;
        esac
      done
    fi
  fi

  names+=(direnv)
  if ! command -v direnv >/dev/null 2>&1; then
    _dr_warn 'direnv shell integration unavailable' \
      "direnv is not on PATH, so new shells skip its hook; run 'dot update'"
    issues=1
  fi
  ((issues == 0)) || return 0
  for name in "${names[@]}"; do
    list+=${list:+, }$name
  done
  _dr_ok 'dev shell integrations' "$list"
}

# ---------------------------------------------------------------------------
# Git hooks
# ---------------------------------------------------------------------------
# Run git against the repository whose commits the hooks guard: the base
# dotfiles client when its Git directory exists, otherwise whatever HOME is.
# DOTFILES is a base compat global outside its documented overlay surface, so
# derive the same default when a base does not set it.
_dr_hooks_git() {
  local git_dir=${DOTFILES:-${DOT_CLIENT_GIT_DIR:-$HOME/.dotfiles}}
  if [[ -d $git_dir ]]; then
    git --git-dir="$git_dir" "$@"
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
