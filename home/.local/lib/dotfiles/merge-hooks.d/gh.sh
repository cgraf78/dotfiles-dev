# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return
dot_hook_source merge-hooks.d/lib/profile-state.sh || return

# shellcheck shell=bash
# Merge GitHub CLI preferences from dotfiles into the local gh config.
# Runs during standalone Dot client convergence.
# Requires yq.
#
# Policy: dotfiles keys overwrite matching local keys.
# Local-only keys are preserved.

_gh_config_sources() {
  _gh_sources=()

  local source
  while IFS= read -r source; do
    _gh_sources+=("$source")
  done < <(dot_hook_family_files_matching gh/config.d '*.yml' '*.yaml' '*.replace/*.yml' '*.replace/*.yaml')
}

_gh_merge_layer() {
  local yq_bin="$1" dst="$2" src="$3" merged

  # Merge: source keys overwrite destination, local-only keys are preserved.
  # Gh writes unset top-level options as blank YAML values, but reads a
  # serialized `null` such as `http_unix_socket: null` as the literal string
  # "null". Omit those empty defaults after yq materializes them.
  merged=$("$yq_bin" eval-all \
    '(select(fileIndex == 0) * select(fileIndex == 1)) | with_entries(select(.value != null))' \
    "$dst" "$src") || {
    dot_hook_warn "    warning: GitHub CLI merge failed for $src — skipping"
    return 0
  }

  dot_write_text_if_changed "$dst" "$merged"
}

merge() {
  _dot_tool_any_command gh || return 0
  local dst="$HOME/.config/gh/config.yml"
  local yq_bin="" managed_dir managed
  local -a _gh_sources

  _gh_config_sources
  yq_bin=$(_merge_hook_mikefarah_yq) || return 0
  ((${#_gh_sources[@]} > 0)) || return 0

  _dev_profile_state_tempdir || return 1
  managed_dir=$REPLY
  managed=$managed_dir/gh.yml
  printf '{}\n' >"$managed"
  for src in "${_gh_sources[@]}"; do
    _gh_merge_layer "$yq_bin" "$managed" "$src" || {
      _dev_profile_state_tempdir_remove "$managed_dir" || true
      return 1
    }
  done
  if ! dev_profile_state_begin gh yaml "$dst" "$managed"; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  _dev_profile_state_tempdir_remove "$managed_dir" || {
    dev_profile_state_abort || true
    return 1
  }

  local src
  dot_hook_log "  GitHub CLI"
  mkdir -p "$(dirname "$dst")"
  if [[ ! -f "$dst" ]]; then
    cp "${_gh_sources[0]}" "$dst"
    _gh_sources=("${_gh_sources[@]:1}")
  fi

  for src in "${_gh_sources[@]}"; do
    if ! _gh_merge_layer "$yq_bin" "$dst" "$src"; then
      dev_profile_state_abort || true
      return 1
    fi
  done
  dev_profile_state_commit || {
    dev_profile_state_abort || true
    return 1
  }
}
