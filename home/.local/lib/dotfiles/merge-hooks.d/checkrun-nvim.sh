# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return
dot_hook_source merge-hooks.d/lib/checkrun-nvim.sh || return

# shellcheck shell=bash
# Generate Neovim's Checkrun editor metadata on every `dot update`.
#
# Neovim reads schema associations and Checkrun capabilities from one JSON
# projection at startup instead of starting Checkrun's Python. The projection
# is derived entirely from the live association policy and the installed
# Checkrun, both of which `dot update` may have just changed, so it is
# regenerated here rather than tracked: a tracked copy silently went stale
# whenever either input changed without a manual regeneration. Merge hooks run
# after shdeps and overlay links converge, so this sees the final inputs.
#
# Publication goes through Dot's sibling-temporary and commit primitives, which
# replace only a regular file atomically. A failed or invalid generation keeps
# the previous projection, which Neovim can still use, and says why.

# Run Checkrun with a bound so a wedged interpreter cannot stall `dot update`.
_checkrun_nvim_generate() {
  local output=$1 errors=$2 seconds=${DOT_CHECKRUN_NVIM_TIMEOUT_SECONDS:-60}
  case $seconds in
    '' | *[!0-9]*) seconds=60 ;;
  esac
  if command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}s" checkrun editor-metadata --json >"$output" 2>"$errors"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${seconds}s" checkrun editor-metadata --json >"$output" 2>"$errors"
  else
    checkrun editor-metadata --json >"$output" 2>"$errors"
  fi
}

# Last non-blank stderr line, so a warning names the cause without a traceback.
_checkrun_nvim_reason() {
  local line reason=''
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n ${line//[[:space:]]/} ]] && reason=$line
  done <"$1"
  printf '%s\n' "${reason:-no error output}"
}

merge() {
  _dot_tool_any_command checkrun || return 0

  local destination temporary errors status=0
  if ! checkrun_nvim_metadata_path; then
    dot_hook_warn "    warning: Checkrun Neovim metadata has no state directory — skipping"
    return 0
  fi
  destination=$REPLY

  if ! dot_json_available; then
    dot_hook_warn "    warning: jq unavailable — keeping the previous Checkrun Neovim metadata"
    return 0
  fi

  # An interrupted run cannot clean up after itself, so clear its leftover
  # staging files here; `dot update` holds its lock, so none belong to a live
  # run.
  checkrun_nvim_remove_staging "$destination"
  if ! mkdir -p -- "${destination%/*}" || ! dot_sibling_tmp_for "$destination"; then
    dot_hook_warn "    warning: cannot stage Checkrun Neovim metadata in ${destination%/*} — skipping"
    return 0
  fi
  temporary=$REPLY
  if ! dot_sibling_tmp_for "$destination"; then
    rm -f -- "$temporary"
    dot_hook_warn "    warning: cannot stage Checkrun Neovim metadata in ${destination%/*} — skipping"
    return 0
  fi
  errors=$REPLY

  _checkrun_nvim_generate "$temporary" "$errors" || status=$?
  if ((status != 0)); then
    dot_hook_warn "    warning: checkrun editor-metadata failed (exit $status: $(_checkrun_nvim_reason "$errors")) — keeping the previous Neovim metadata"
    rm -f -- "$temporary" "$errors"
    return 0
  fi
  rm -f -- "$errors"

  # This is the shape Checkrun's Neovim adapter consumes: a version-1 object,
  # capabilities, a JSON schema list, and YAML/TOML association maps. The
  # adapter silently ignores a wrong-shaped section, so reject it here instead.
  # Compare the printed verdict rather than trusting `jq -e`: jq 1.6 exits 0 for
  # empty input, which would publish an empty projection.
  if [[ $(jq '.version == 1 and (.capabilities | type == "object")
    and (.schemas.json | type == "array")
    and (.schemas.yaml | type == "object")
    and (.schemas.toml | type == "object")' "$temporary" 2>/dev/null) != true ]]; then
    rm -f -- "$temporary"
    dot_hook_warn "    warning: checkrun editor-metadata output failed validation — keeping the previous Neovim metadata"
    return 0
  fi

  # Unchanged output leaves the destination untouched, so its timestamp
  # reflects real changes only.
  if [[ -f $destination && ! -L $destination ]] &&
    dot_config_files_equal "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 0
  fi

  dot_hook_log "  checkrun-nvim"
  # dot_commit_tmp refuses a directory or symlink at the destination rather
  # than moving the file inside it or replacing the link.
  # BSD chmod rejects `--`; the staged path is always absolute.
  if ! chmod 0644 "$temporary" || ! dot_commit_tmp "$temporary" "$destination"; then
    rm -f -- "$temporary"
    dot_hook_warn "    warning: cannot publish Checkrun Neovim metadata to $destination (not a regular file?)"
  fi
  return 0
}
