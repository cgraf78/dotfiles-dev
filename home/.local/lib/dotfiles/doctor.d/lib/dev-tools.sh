# shellcheck shell=bash
# dot doctor: development command checks.

# Base dotfiles own the shdeps bin-link check (doctor.d/lib/shdeps-links.sh,
# `_dr_check_shdeps_bin_group LEVEL DEPENDENCY`); this overlay only passes its
# dependency list. Base and overlays update independently, so an older base
# without that module keeps the local fallback below. The source is quiet and
# non-fatal when the module is absent. The fallback deliberately has its own
# name and is chosen at call time, so it can never replace base's helper
# (which goes quiet when shdeps health covers bin links).
dot_doctor_source doctor.d/lib/shdeps-links.sh || true

_dr_dev_shdeps_link_issue() {
  local level="$1" label="$2" detail="${3:-}"
  if [[ $level == fail ]]; then _dr_fail "$label" "$detail"; else _dr_warn "$label" "$detail"; fi
}

# Fallback copy of base's helper for bases that predate shdeps-links.sh.
_dr_check_dev_shdeps_bin_group() {
  local level="$1" dependency="$2" rows cmd link expected extra actual
  local issue_count=0 command_count=0 conf_dir
  # The base adapter returns the directory through REPLY (no subshell);
  # reading it through a command substitution silently passed an empty
  # directory. Guarded so a base without the adapter cannot abort the worker,
  # and quiet so an older adapter that printed instead leaks nothing.
  REPLY=
  _dot_shdeps_conf_dir >/dev/null 2>&1 || true
  conf_dir=$REPLY
  if [[ -z $conf_dir ]]; then
    # Nothing is known to be wrong with the links, so this is a warning even
    # for dependencies whose broken links would fail.
    _dr_warn "$dependency bin links unchecked" \
      'could not resolve the shdeps config directory'
    return 0
  fi
  if ! rows=$(SHDEPS_CONF_DIR="$conf_dir" \
    command shdeps dep-links "cgraf78/$dependency" 2>/dev/null); then
    _dr_dev_shdeps_link_issue "$level" "$dependency bin links unchecked" \
      "shdeps cannot resolve command links for cgraf78/$dependency"
    return 0
  fi
  if [[ -z $rows ]]; then
    _dr_dev_shdeps_link_issue "$level" "$dependency bin links missing" \
      "shdeps reported no public command links for cgraf78/$dependency"
    return 0
  fi
  while IFS=$'\t' read -r cmd link expected extra || [[ -n $cmd$link$expected$extra ]]; do
    if [[ -z $cmd || -z $link || -z $expected || -n $extra ]]; then
      issue_count=$((issue_count + 1))
      _dr_dev_shdeps_link_issue "$level" "$dependency bin links malformed" \
        "unexpected shdeps dep-links row for cgraf78/$dependency"
      continue
    fi
    command_count=$((command_count + 1))
    if [[ ! -e $link && ! -L $link ]]; then
      issue_count=$((issue_count + 1))
      _dr_dev_shdeps_link_issue "$level" "$cmd not linked" \
        "expected $(_dr_tilde "$link") -> $(_dr_tilde "$expected")"
      continue
    fi
    if [[ $link != "$expected" ]]; then
      if [[ ! -L $link ]]; then
        issue_count=$((issue_count + 1))
        _dr_dev_shdeps_link_issue "$level" "$cmd not linked" \
          "expected $(_dr_tilde "$link") -> $(_dr_tilde "$expected")"
        continue
      fi
      if ! _dr_symlink_points_to "$link" "$expected"; then
        issue_count=$((issue_count + 1))
        actual=$(_dr_symlink_target_path "$link" 2>/dev/null || echo '?')
        _dr_dev_shdeps_link_issue "$level" "$cmd link target drift" \
          "got $(_dr_tilde "$actual"), expected $(_dr_tilde "$expected")"
        continue
      fi
    fi
    if [[ ! -x $link ]]; then
      issue_count=$((issue_count + 1))
      _dr_dev_shdeps_link_issue "$level" "$cmd not executable" "$(_dr_tilde "$link")"
    fi
  done <<<"$rows"
  ((issue_count != 0)) || _dr_ok "$dependency bin links" "$command_count command(s)"
}

# Check one dependency's command links through base's shared helper when this
# host's base ships it, else through the local fallback.
_dr_check_dev_bin_links() {
  if declare -F _dr_check_shdeps_bin_group >/dev/null; then
    _dr_check_shdeps_bin_group "$@"
  else
    _dr_check_dev_shdeps_bin_group "$@"
  fi
}

_dr_check_dev_tools() {
  local command_name
  _dr_section 'Development tools'

  for command_name in gh delta difft gitleaks lazygit sley checkrun; do
    if command -v "$command_name" >/dev/null 2>&1; then
      _dr_ok "$command_name" 'available'
    else
      _dr_warn "$command_name missing" "run 'dot update' with the dev profile"
    fi
  done

  if [[ -f "$HOME/.config/git/config" ]]; then
    _dr_ok 'global Git configuration' "$(_dr_tilde "$HOME/.config/git/config")"
  else
    _dr_fail 'global Git configuration missing' 'select the dev profile and run dot update'
  fi

  if command -v shdeps >/dev/null 2>&1; then
    _dr_check_dev_bin_links fail sley
    _dr_check_dev_bin_links warn checkrun
    _dr_check_dev_bin_links warn cmdblocks
    _dr_check_dev_bin_links warn git-tools
    _dr_check_dev_bin_links fail agentguard
    _dr_check_dev_bin_links warn hive-memory
  else
    _dr_warn 'development dependency command links unchecked' 'shdeps is not on PATH'
  fi
}
