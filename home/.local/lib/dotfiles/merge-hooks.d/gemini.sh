# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return
dot_hook_source merge-hooks.d/lib/profile-state.sh || return

# shellcheck shell=bash
# Merge Gemini CLI settings into ~/.gemini/settings.json.
# Runs during standalone Dot client convergence.
# Requires jq.
#
# Layers come from gemini/settings.d. Direct files aggregate in lexical order;
# each immediate *.replace directory contributes only its last lexical file, so
# overlays can express environment-specific overrides without this hook knowing
# those environment names.
#
# Gemini-owned state (sessionRetention, trustedFolders, etc.) is preserved
# because the recursive merge only overwrites keys present in the source.

_merge_gemini_settings() {
  local src="$1" dst="$2"
  # shellcheck disable=SC2016 # jq owns $d/$s inside this filter.
  dot_json_layer "Gemini settings" "$src" "$dst" '$d[0] * $s[0]'
}

merge() {
  _dot_tool_present gemini || return 0
  dot_json_available || return 0

  local dst="$HOME/.gemini/settings.json" managed_dir managed
  local -a src_files=()
  local src

  while IFS= read -r src; do
    src_files+=("$src")
  done < <(dot_hook_family_files_matching gemini/settings.d '*.json' '*.replace/*.json')

  dot_hook_log "  Gemini CLI"

  _dev_profile_state_tempdir || return 1
  managed_dir=$REPLY
  managed=$managed_dir/gemini.json
  printf '{}\n' >"$managed"
  _merge_hook_agentguard_json_layer "Gemini settings" gemini "$managed" || {
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  }
  for src in "${src_files[@]}"; do
    _merge_gemini_settings "$src" "$managed" || {
      _dev_profile_state_tempdir_remove "$managed_dir" || true
      return 1
    }
  done

  # Reconciliation is provider-owned so event retirement and command changes
  # stay reusable outside this dotfiles repository. A failed required refresh
  # leaves the whole generated target unchanged and fails the merge hook.
  if ! dev_profile_state_begin gemini json "$dst" "$managed"; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  _dev_profile_state_tempdir_remove "$managed_dir" || {
    dev_profile_state_abort || true
    return 1
  }
  if ! _merge_hook_agentguard_json_layer "Gemini settings" gemini "$dst"; then
    dev_profile_state_abort || true
    return 1
  fi

  for src in "${src_files[@]}"; do
    if ! _merge_gemini_settings "$src" "$dst"; then
      dev_profile_state_abort || true
      return 1
    fi
  done
  dev_profile_state_commit || {
    dev_profile_state_abort || true
    return 1
  }
}
