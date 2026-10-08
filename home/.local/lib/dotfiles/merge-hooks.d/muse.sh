# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return
dot_hook_source merge-hooks.d/lib/agentguard.sh || return
dot_hook_source merge-hooks.d/lib/profile-state.sh || return

# shellcheck shell=bash
# Merge Muse Code settings into ~/.config/muse/settings.json.
# Runs during standalone Dot client convergence.
# Requires jq.
#
# Layers come from muse/settings.d. Direct files aggregate in lexical order;
# each immediate *.replace directory contributes only its last lexical file, so
# overlays can express personal/work mutual exclusivity without this hook knowing
# those environment names.
#
# Muse rejects any settings-level "permissions" object at startup, so no
# layer may provide one and the merge strips the key from both the managed
# and live documents. Hook arrays are merged per event by identity
# (matcher + command), so a config change to an existing hook replaces it
# instead of appending a duplicate.

# Merge a Muse settings layer into an existing settings.json.
# Policy: source wins on conflicts (same key, different value).
# Existing scalar keys and non-conflicting object keys are preserved.
# Hook arrays are merged per event by identity (matcher + command) so
# re-merging is idempotent.
_merge_muse_settings() {
  local src="$1" dst="$2"
  local filter

  # Merge: existing settings * source settings (recursive merge, source wins).
  # shellcheck disable=SC2016 # jq owns $d/$s inside this filter.
  filter='
    # A hook group'"'"'s identity is its matcher plus which commands it runs;
    # timeout/type are just that hook'"'"'s execution parameters, not part of
    # what makes it "the same hook". Existing (destination) groups sharing an
    # incoming group'"'"'s identity are dropped before appending the incoming
    # group, so re-running this merge is idempotent (no accumulation run over
    # run) and self-healing (an already-duplicated live settings.json collapses
    # to one canonical copy per event on the next `dot update`, and a config
    # change like a new timeout cleanly replaces the old value instead of
    # sitting duplicated alongside it forever).
    def hook_group_identity:
      {matcher: (.matcher // null), commands: [(.hooks // [])[].command]};
    def merge_hook_group_list($existing; $incoming):
      ($incoming | map(hook_group_identity)) as $incoming_ids |
      ($existing | map(select((hook_group_identity as $id | ($incoming_ids | index($id))) | not)))
        as $kept |
      $kept + $incoming;

    # Merge hook arrays per event instead of letting `*` replace them: `*` would
    # overwrite the base layer'"'"'s hooks (e.g. Stop) as soon as a later layer
    # defines any hooks at all. Concatenate each event'"'"'s groups, base first.
    (($d[0].hooks // {}) as $dh | ($s[0].hooks // {}) as $sh |
      reduce (($dh | keys_unsorted) + ($sh | keys_unsorted))[] as $e
        ({}; .[$e] = merge_hook_group_list($dh[$e] // []; $sh[$e] // []))) as $merged_hooks |

    $d[0] * $s[0] |

    (if ($merged_hooks | length) > 0 then .hooks = $merged_hooks else . end)
  '
  dot_json_layer "Muse settings" "$src" "$dst" "$filter"
}

# Drop the settings-level `permissions` key from a Muse settings document.
# Muse rejects any such object at startup ("Named permission profiles are
# unavailable"), so neither layers, overlay additions, nor stale live
# targets may leave it behind. Runs inside the active transaction: a
# failure aborts and the live target keeps its pre-merge bytes.
_strip_muse_permissions() {
  local dst="$1" tmp
  tmp=$(mktemp "${dst}.tmp.XXXXXX") || return 1
  if ! jq 'del(.permissions)' "$dst" >"$tmp" || ! mv -f "$tmp" "$dst"; then
    rm -f "$tmp"
    return 1
  fi
}

merge() {
  _dot_tool_present muse || return 0
  dot_json_available || return 0

  local dst="$HOME/.config/muse/settings.json" managed_dir managed
  local -a src_files=()
  local src

  while IFS= read -r src; do
    src_files+=("$src")
  done < <(dot_hook_family_files_matching muse/settings.d '*.json' '*.replace/*.json')

  dot_hook_log "  Muse Code"

  _dev_profile_state_tempdir || return 1
  managed_dir=$REPLY
  managed=$managed_dir/muse.json
  printf '{}\n' >"$managed"
  _merge_hook_agentguard_json_layer "Muse settings" muse "$managed" || {
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  }
  for src in "${src_files[@]}"; do
    _merge_muse_settings "$src" "$managed" || {
      _dev_profile_state_tempdir_remove "$managed_dir" || true
      return 1
    }
  done
  _strip_muse_permissions "$managed" || {
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  }

  # The provider reconciler knows which historical Muse hooks it owns, so an
  # unsupported event can be retired without encoding Muse vocabulary here.
  # It also stages symlink migration transactionally and reports a missing
  # dependency as a failed refresh instead of silently installing bare policy.
  if ! dev_profile_state_begin muse json "$dst" "$managed"; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  _dev_profile_state_tempdir_remove "$managed_dir" || {
    dev_profile_state_abort || true
    return 1
  }
  if ! _merge_hook_agentguard_json_layer "Muse settings" muse "$dst"; then
    dev_profile_state_abort || true
    return 1
  fi

  for src in "${src_files[@]}"; do
    if ! _merge_muse_settings "$src" "$dst"; then
      dev_profile_state_abort || true
      return 1
    fi
  done
  if ! _strip_muse_permissions "$dst"; then
    dev_profile_state_abort || true
    return 1
  fi
  dev_profile_state_commit || {
    dev_profile_state_abort || true
    return 1
  }
}
