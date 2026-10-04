# shellcheck shell=bash
# dot doctor: Hive Memory health, reported in the Agent tooling section.
#
# One bounded `hm sync-status --json` answers the two questions doctor can
# afford to ask:
# - Does the installed hm understand every configured key? The hm config is
#   dotfiles-managed and syncs independently of hive-memory releases, and hm
#   deliberately downgrades an unknown key to a stderr warning so hooks never
#   fail, which leaves the configured policy silently on defaults.
# - Can hm read its store? The store usually sits on a cloud or network
#   mount; when that drops, hooks keep working but memory goes stale.
# Not `hm doctor`: even `--quick` can take tens of seconds and has ignored
# SIGTERM.

# Deadline in seconds. A healthy store on a cloud mount answers in under one.
_DR_HM_DEADLINE=3

# Start the probe in the background so it overlaps the section's other
# probes: DIR receives hm.out (the JSON report), hm.err, and hm.rc. Sets
# _DR_HM_PID, or leaves it empty when hm is not installed.
_dr_hive_memory_start() {
  local dir=$1
  _DR_HM_PID=
  command -v hm >/dev/null 2>&1 || return 0
  (
    # Plain assignment: this fork cannot leak into the worker, and the `||`
    # keeps `set -e` from ending it before the status is written.
    rc=0
    _dr_dev_bounded "$_DR_HM_DEADLINE" hm sync-status --json \
      >"$dir/hm.out" 2>"$dir/hm.err" </dev/null || rc=$?
    printf '%s' "$rc" >"$dir/hm.rc"
  ) &
  _DR_HM_PID=$!
}

# Report via REPLY, as one line, why hm printed no report, from its STDERR:
# with --json, hm writes the error as a JSON object ({"error": {"message":
# ...}}), possibly after `warning:` lines; anything else falls back to the
# first line that is not a warning.
_dr_hive_memory_error() {
  local stderr=$1 text line
  REPLY=
  text=$'\n'$stderr
  if [[ $text == *$'\n{'* ]]; then
    REPLY=$(jq -r '.error.message // empty' <<<"{${text#*$'\n'\{}" 2>/dev/null) || REPLY=
  fi
  if [[ -z $REPLY ]]; then
    while IFS= read -r line; do
      [[ -n $line && $line != warning:* ]] || continue
      REPLY=$line
      break
    done <<<"$stderr"
  fi
  REPLY=${REPLY//[$'\t\r\n']/ }
}

# Report what the probe in DIR found: wait for it, then file its rows.
_dr_hive_memory_finish() {
  local dir=$1 rc=1 parsed stderr='' line detail
  local reachable='' error='' root='' conflicts='' keys_known='' keys=''

  if [[ -z ${_DR_HM_PID:-} ]]; then
    _dr_skip 'Hive Memory' 'hm not installed'
    return 0
  fi
  wait "$_DR_HM_PID" 2>/dev/null || true
  if [[ -f $dir/hm.rc ]]; then
    rc=$(<"$dir/hm.rc")
    [[ $rc =~ ^[0-9]+$ ]] || rc=1
  fi
  [[ ! -f $dir/hm.err ]] || stderr=$(<"$dir/hm.err")

  if _dr_dev_deadline_status "$rc"; then
    _dr_dev_row warn 'Hive Memory unchecked' \
      "hm sync-status gave no answer within ${_DR_HM_DEADLINE}s, so its store may be on a hung mount" \
      "check the store's mount, then run 'hm sync-status'"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _dr_skip 'Hive Memory' 'jq is required to read hm sync-status'
    return 0
  fi
  # A report is JSON on stdout whatever the exit status. One jq call turns
  # it into key=value lines; anything else (no output, an older hm that
  # exits 1 when its store scan fails) leaves the store unchecked. Absent
  # fields stay distinguishable from empty ones: an hm before
  # `unknown_config_keys` cannot say a key list is empty, and its
  # `cloud_conflict_files` also counted copies `hm doctor --fix` had already
  # quarantined, so the count is only read alongside `store_error`, which
  # arrived with the corrected rule.
  if [[ -s $dir/hm.out ]] && parsed=$(jq -r '
    def line: tostring | gsub("[\\t\\r\\n]"; " ");
    "reachable=\(.reachable)",
    "error=\((.store_error // .manifest_error // "") | line)",
    "root=\((.root // "") | line)",
    "conflicts=\(if has("store_error") then (.cloud_conflict_files // 0) else "" end)",
    "keys_known=\(has("unknown_config_keys"))",
    "keys=\((.unknown_config_keys // []) | map(line) | join(", "))"
  ' "$dir/hm.out" 2>/dev/null); then
    while IFS= read -r line; do
      case $line in
        reachable=*) reachable=${line#*=} ;;
        error=*) error=${line#*=} ;;
        root=*) root=${line#*=} ;;
        conflicts=*) conflicts=${line#*=} ;;
        keys_known=*) keys_known=${line#*=} ;;
        keys=*) keys=${line#*=} ;;
      esac
    done <<<"$parsed"
  fi
  if [[ $reachable != true && $reachable != false ]]; then
    _dr_hive_memory_error "$stderr"
    if ((rc == 127)); then
      # The overlay's hm launcher exits 127 when the real binary is not
      # installed, as on Android, where hive-memory is not offered; shdeps
      # health reports it where it should be.
      _dr_skip 'Hive Memory' "${REPLY:-hm not installed}"
      return 0
    fi
    _dr_dev_row warn 'Hive Memory unchecked' \
      "${REPLY:-hm sync-status exited $rc without a report}" "run 'hm sync-status' to see why"
    return 0
  fi

  if [[ $keys_known != true ]]; then
    # Compatibility for an hm before `unknown_config_keys`: every version
    # prints `warning: unknown config key: KEY` on stderr, so read the key
    # names from there. Remove once that hm is gone from the fleet.
    keys=
    while IFS= read -r line; do
      [[ $line == *'unknown config key: '* ]] || continue
      line=${line#*unknown config key: }
      keys+=${keys:+, }${line//[$'\t\r']/ }
    done <<<"$stderr"
  fi

  local problems=0
  if [[ -n $keys ]]; then
    _dr_dev_row warn 'hm binary behind configured keys' "unknown key(s): $keys" \
      "run 'dot update' to update hive-memory, or drop the key(s) from Hive Memory's config"
    problems=1
  fi
  if [[ $reachable == false ]]; then
    _dr_dev_row warn 'Hive Memory store unreachable' "${error:-$root}" \
      "check that the store's mount is up, then run 'hm sync-status'"
    problems=1
  elif [[ $conflicts =~ ^[1-9][0-9]*$ ]]; then
    _dr_dev_row warn "Hive Memory store has $conflicts cloud conflict file(s)" "" \
      "run 'hm doctor --fix' to quarantine them"
    problems=1
  fi
  # `index_stale` gets no row: hm rebuilds its index on the next read, so a
  # note written since then (by any host) is the normal state, not a fault.
  ((problems == 0)) || return 0
  detail=
  [[ -z $root ]] || detail=$(_dr_tilde "$root")
  [[ $keys_known != true ]] || detail+="${detail:+; }every config key understood"
  _dr_ok 'Hive Memory store reachable' "$detail"
}
