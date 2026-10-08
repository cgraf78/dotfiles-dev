# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Deploy Sapling hook config fragments to ~/.hgrc.
#
# Only deploys when sl is on PATH. Machines without Sapling get a no-op. Hook
# policy lives under sapling/hgrc.d/ so overlays can replace or extend it
# without editing this reusable merge implementation.

declare -F dot_hook_family_files_matching >/dev/null 2>&1 || return 1

# Expand every `${shdeps:<owner>/<repo>/<relative-path>}` token in $1 to the
# dependency file shdeps resolves, through REPLY. The token body is the same
# `shdeps:owner/repo/path` reference the Checkrun editor metadata uses; the
# braces only delimit it inside a line. hgrc is static config that Sapling
# reads on every command, so provider paths are resolved once here at merge
# time rather than spelled as shdeps' private install layout or wrapped in a
# runtime launcher. Returns 1 when a token is malformed or cannot be
# resolved, which is also how an absent provider looks.
_sapling_expand_deps() {
  local rest=$1 out="" token owner repo relative asset
  # shellcheck disable=SC2016 # The literal token opener, never expanded.
  local open='${shdeps:'
  while [[ $rest == *"$open"* ]]; do
    out+=${rest%%"$open"*}
    rest=${rest#*"$open"}
    [[ $rest == *\}* ]] || return 1
    token=${rest%%\}*}
    rest=${rest#*\}}
    owner=${token%%/*}
    repo=${token#*/}
    relative=${repo#*/}
    repo=${repo%%/*}
    [[ -n $owner && -n $repo && $token == "$owner/$repo/$relative" && -n $relative ]] ||
      return 1
    asset=$(dot_shdeps_dep_file "$owner/$repo" "$relative" 2>/dev/null) || return 1
    [[ -n $asset ]] || return 1
    out+=$asset
  done
  REPLY=$out$rest
}

_sapling_hooks_body() {
  local source line

  while IFS= read -r source; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      _sapling_expand_deps "$(dot_expand_home "$line")" || return 1
      printf '%s\n' "$REPLY"
    done <"$source"
  done < <(dot_hook_family_files_matching \
    sapling/hgrc.d \
    '*.ini' '*.replace/*.ini' \
    '*.hgrc' '*.replace/*.hgrc')
}

_sapling_hook_commands_ready() {
  local body="$1" line command executable section=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*[#\;] ]] && continue
    if [[ "$line" =~ ^[[:space:]]*\[([^]]+)\] ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi
    [[ "$section" == "hooks" ]] || continue
    [[ "$line" == *=* ]] || continue

    command="${line#*=}"
    command="${command#"${command%%[![:space:]]*}"}"
    [[ -n "$command" ]] || continue
    [[ "$command" == python:* ]] && continue

    executable="${command%%[[:space:]]*}"
    if [[ "$executable" == */* ]]; then
      [[ -x "$executable" ]] || return 1
    else
      command -v "$executable" >/dev/null 2>&1 || return 1
    fi
  done <<<"$body"
}

merge() {
  _dot_tool_present sapling || return 0

  local dst="$HOME/.hgrc"

  local body
  # An unresolvable provider token means that provider is absent; skip the
  # deployment the same way the readiness check below does for a missing hook.
  body="$(_sapling_hooks_body)" || return 0
  [[ -n "$body" ]] || return 0
  _sapling_hook_commands_ready "$body" || return 0

  dot_hook_log "  Sapling"

  local current old_marker block
  old_marker="# dot-managed:hgrc:repo-check"
  if [ -f "$dst" ]; then
    current="$(cat "$dst")"
    current="$(dot_managed_block_strip "$old_marker" "$current")"
    current="$(dot_managed_block_strip "# dot-managed:hgrc:sley-legacy" "$current")"
    # Strip legacy managed blocks before writing the current marker. Without
    # this one-time cleanup, users who installed prior variants would get
    # duplicate Sapling entries.
    if ! printf '%s\n' "$current" | cmp -s - "$dst"; then
      printf '%s\n' "$current" >"$dst"
    fi
  fi

  block=$(dot_managed_block_build "# dot-managed:hgrc:sley" \
    ".config/dot/merge-hooks.d/sapling/hgrc.d" "$body")

  dot_managed_block_merge "$dst" "$block"
}
