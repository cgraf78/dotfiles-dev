# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return
dot_hook_source merge-hooks.d/lib/profile-state.sh || return

# shellcheck shell=bash
# Merge VS Code settings and keybindings from dotfiles into local config.
# Runs during standalone Dot client convergence.
# Requires jq.

# The no-op signature covers this hook's own code; resolve it while sourcing.
_dot_vscode_hook_source="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/${BASH_SOURCE[0]##*/}" || return

# Strip // line comments from JSONC so jq can parse it. Normalize transport
# bytes first because Settings Sync can move CRLF/BOM files across platforms;
# leaving a BOM attached to the first comment would make a valid source or
# synchronized destination fail parsing for a formatting-only reason. Callers
# parse the output with jq themselves, so it is not validated here.
_strip_jsonc() {
  LC_ALL=C awk '
    NR == 1 { sub(/^\357\273\277/, "", $0) }
    { sub(/\r$/, "", $0) }
    !/^[[:space:]]*\/\//
  ' "$1"
}

# Set REPLY to dirname(1) of $1 without starting a process; merges compute
# parents for every destination and extension link. Matches GNU dirname: trailing
# slashes are ignored, a bare name yields ".", and a root child yields "/".
_vscode_dirname() {
  local path=$1
  while [[ $path == */ && $path != / ]]; do
    path=${path%/}
  done
  case $path in
    /) REPLY=/ ;;
    */*)
      path=${path%/*}
      while [[ $path == */ && $path != / ]]; do
        path=${path%/}
      done
      REPLY=${path:-/}
      ;;
    *) REPLY=. ;;
  esac
}

# Retirement history stays in source because there is no universally inert
# ownership field in a VS Code keybinding. Comments disappear during divergent
# Settings Sync merges, `when` participates in resolver implication, and `args`
# can change positive-command behavior. Exact source records are less clever
# and more durable: they alter no generated shortcut semantics at all.
_DOT_VSCODE_KEYBINDING_RETIRE='dotfiles.retire'
_DOT_VSCODE_KEYBINDING_RETIRE_PROOF='dotfiles.retire-proof'
_DOT_VSCODE_KEYBINDING_REVIEW_PROOF='review-build:7030e8e'
_DOT_VSCODE_KEYBINDING_LEGACY_PROOF='legacy-local:280f7f8'

_vscode_is_wsl() {
  dot_hook_platform_match wsl
}

_vscode_commit_tmp() {
  local tmp="$1" dst="$2" size

  if [[ -f "$dst" ]] && _dev_profile_state_files_equal "$tmp" "$dst"; then
    rm -f -- "$tmp"
    return 0
  fi

  if _vscode_is_wsl; then
    if ! command -v python3 >/dev/null 2>&1; then
      dot_hook_warn "    warning: python3 unavailable for verified VS Code config write to $dst — leaving temp file"
      return 1
    fi

    # WSL writes to native Windows config files can report a successful rename
    # while leaving a short byte stream behind. Write through an already-open
    # handle, truncate only after all bytes are written, then verify the final
    # content before deleting the temp file.
    if python3 - "$tmp" "$dst" <<'PY'
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, "rb") as handle:
    expected = handle.read()

try:
    with open(dst, "rb") as handle:
        original = handle.read()
    existed = True
except FileNotFoundError:
    original = b""
    existed = False

def write_bytes(data):
    fd = os.open(dst, os.O_WRONLY | os.O_CREAT, 0o666)
    try:
        view = memoryview(data)
        written = 0
        while written < len(view):
            written += os.write(fd, view[written:])
        os.ftruncate(fd, len(data))
        os.fsync(fd)
    finally:
        os.close(fd)

try:
    write_bytes(expected)
    with open(dst, "rb") as handle:
        actual = handle.read()
    if actual != expected:
        raise RuntimeError("destination did not match expected bytes after write")
except BaseException:
    try:
        if existed:
            write_bytes(original)
        else:
            os.unlink(dst)
    except BaseException:
        pass
    raise
PY
    then
      rm -f -- "$tmp"
      return 0
    fi
    dot_hook_warn "    warning: verified VS Code config write failed for $dst — leaving temp file"
    return 1
  fi

  # WSL already returned through the verified in-place writer above. Other
  # platforms use ordinary mv: sibling temporaries take its rename path, while
  # general mktemp callers may require its cross-filesystem copy fallback. Keep
  # the post-move size normalization as defensive compatibility only. Once mv
  # succeeds the new config is published, so that optional normalization must
  # not turn publication success into a merge failure.
  size=$(wc -c <"$tmp")
  if mv -f -- "$tmp" "$dst"; then
    truncate -s "$size" "$dst" 2>/dev/null || true
  else
    rm -f -- "$tmp"
    return 1
  fi
}

# Merge VS Code keybindings from dotfiles into a local keybindings.json.
# Policy: dotfiles win on key+when conflicts. Append-only, exact source
# retirement records identify old managed generations that can be removed,
# including bindings imported by Settings Sync from another machine. Genuinely
# local-only bindings retain their precedence. Keeping history in JSONC teaches
# this hook nothing about keys, commands, platforms, or Termnav behavior.
#
# Managed terminal-native tab routes are the exception to normal ordering: they
# must reach the pty ahead of stale local handlers with overlapping conditions.
# Writes to a .tmp file first so the original is preserved on failure.
_merge_vscode_keybindings() {
  local src="$1" dst="$2"
  local out src_clean dst_clean
  _vscode_dirname "$dst"
  [[ -d $REPLY ]] || mkdir -p "$REPLY"

  # Normalize exactly one top-level array from each JSONC input. Accepting a
  # second JSON document would let a plausible-looking prefix hide corruption,
  # then silently discard retirement policy or bindings through $slurpfile[0].
  src_clean=$(mktemp)
  dst_clean=$(mktemp)
  trap 'rm -f "${src_clean:-}" "${dst_clean:-}"' RETURN

  # jq parses the stripped text directly: a second normalizing jq in front of
  # each slurp would add a process without changing the parsed documents.
  if ! _strip_jsonc "$src" |
    jq -s -e \
      --arg retire "$_DOT_VSCODE_KEYBINDING_RETIRE" \
      --arg proof "$_DOT_VSCODE_KEYBINDING_RETIRE_PROOF" \
      --arg review_proof "$_DOT_VSCODE_KEYBINDING_REVIEW_PROOF" \
      --arg legacy_proof "$_DOT_VSCODE_KEYBINDING_LEGACY_PROOF" '
      def valid_binding:
        type == "object"
        and (.key | type == "string" and length > 0)
        and (.command | type == "string" and length > 0)
        and ((has("when") | not) or (.when | type == "string"))
        and (
          (has($retire) | not)
          or .[$retire] == true
        )
        and (
          (has($proof) | not)
          or (
            .[$retire] == true
            and (
              .[$proof] == $review_proof
              or .[$proof] == $legacy_proof
            )
          )
        );

      if length == 1
        and (.[0] | type == "array")
        and all(.[0][]; valid_binding)
      then .[0]
      else error("expected one valid keybinding array")
      end
    ' \
      >"$src_clean"; then
    dot_hook_warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    return 1
  fi

  if [[ -f "$dst" ]]; then
    if ! _strip_jsonc "$dst" |
      jq -s -e 'if length == 1 and (.[0] | type == "array") then .[0] else error("expected one array") end' \
        >"$dst_clean"; then
      dot_hook_warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
      return 1
    fi
  else
    printf '[]\n' >"$dst_clean"
  fi

  # Current key+when conflicts and exact retirement records are source-owned
  # policy. A changed or deleted binding keeps its former exact object in the
  # JSONC history, allowing machines to skip releases without stranding an
  # intermediate generation synchronized from elsewhere. "Exact" deliberately
  # includes args and any additional properties: a near-match may be a user's
  # independent binding, so broad key/command heuristics are not safe deletion
  # authority.
  # VS Code resolves equal-weight user bindings from the bottom up, so keep only
  # the managed terminal-native tab routes after preserved local entries; unrelated
  # local overrides retain the existing source-first precedence.
  dot_sibling_tmp_for "$dst" || return 1
  out="$REPLY"
  if ! jq -n --indent 4 --sort-keys \
    --arg retire "$_DOT_VSCODE_KEYBINDING_RETIRE" \
    --arg proof "$_DOT_VSCODE_KEYBINDING_RETIRE_PROOF" \
    --slurpfile s "$src_clean" \
    --slurpfile d "$dst_clean" '
    def terminal_tab_route:
      .command == "workbench.action.terminal.sendSequence"
      and .when == "terminalFocus"
      and (.key == "ctrl+tab" or .key == "ctrl+shift+tab");

    ($s[0] | map(select(.[$retire] != true))) as $active |
    ($s[0] | map(select(.[$retire] == true) | del(.[$retire], .[$proof]))) as $retired |
    ($active | map({key: .key, when: (.when // "")})) as $skeys |
    # Current managed entries come first, matching the historical merge
    # policy. A local key+when conflict is removed even when its command
    # differs because VS Code would otherwise resolve two definitions for the
    # same shortcut condition.
    ($active | map(select(terminal_tab_route | not)))
    + [
      $d[0][]
      | select(
          ({key: .key, when: (.when // "")} as $key_when
            | $skeys | map(. == $key_when) | any | not)
          and
          (. as $binding
            | $retired | map(. == $binding) | any | not)
        )
    ]
    + ($active | map(select(terminal_tab_route)))
  ' >"$out"; then
    dot_hook_warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$out"
    return 1
  fi

  _vscode_commit_tmp "$out" "$dst"
}

# Merge VS Code settings from dotfiles into a local settings.json.
# Policy: dotfiles win on conflicts (same key, different value).
# Local-only settings are preserved. Writes to .tmp first for safety.
_merge_vscode_settings() {
  local src="$1" dst="$2" out
  _vscode_dirname "$dst"
  [[ -d $REPLY ]] || mkdir -p "$REPLY"

  # No existing file — just copy (stripping comments)
  if [[ ! -f "$dst" ]]; then
    dot_sibling_tmp_for "$dst" || return 1
    out="$REPLY"
    if _strip_jsonc "$src" | jq --indent 4 --sort-keys '.' >"$out"; then
      _vscode_commit_tmp "$out" "$dst"
    else
      rm -f "$out"
      return 1
    fi
    return
  fi

  # Merge: local settings * dotfiles settings (recursive merge, dotfiles win).
  # Using * instead of + keeps local-only nested keys in objects like
  # "[python]". commandsToSkipShell is VS Code's additive command policy, so
  # preserve unrelated local/Settings Sync entries while letting each managed
  # entry replace its positive or negative counterpart by command id.
  #
  # Both inputs stream straight from the comment stripper: this runs once per
  # settings layer, and normalizing each side into a temporary file first cost
  # two jq starts and three temp-file operations per layer. Unparsable or
  # empty input fails this jq, taking the same warn-and-skip path as before.
  dot_sibling_tmp_for "$dst" || return 1
  out="$REPLY"
  if ! jq -n --indent 4 --sort-keys --slurpfile s <(_strip_jsonc "$src") \
    --slurpfile d <(_strip_jsonc "$dst") \
    '
    def valid_command_list:
      type == "array" and all(.[]; type == "string");
    def command_id:
      if startswith("-") then .[1:] else . end;
    def merge_command_policy($local; $managed):
      reduce $managed[] as $entry (
        ($local | if valid_command_list then . else [] end);
        [.[] | select(command_id != ($entry | command_id))] + [$entry]
      );

    ($d[0] * $s[0]) as $merged
    | if (
        $s[0] | has("terminal.integrated.commandsToSkipShell")
        and (."terminal.integrated.commandsToSkipShell" | valid_command_list)
      )
      then $merged
        | ."terminal.integrated.commandsToSkipShell" = merge_command_policy(
            $d[0]."terminal.integrated.commandsToSkipShell";
            $s[0]."terminal.integrated.commandsToSkipShell"
          )
      else $merged
      end
    ' >"$out"; then
    dot_hook_warn "    warning: settings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$out"
  else
    _vscode_commit_tmp "$out" "$dst"
  fi
}

_vscode_checkrun_capabilities() {
  local out="$1"

  printf '{}\n' >"$out"
  command -v checkrun >/dev/null 2>&1 || return 0
  checkrun capabilities --json >"$out" 2>/dev/null || printf '{}\n' >"$out"
}

_vscode_checkrun_schema_config() {
  local out="$1" schema_policy

  printf '{}\n' >"$out"
  if command -v shdeps >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    schema_policy=$(shdeps dep-file cgraf78/checkrun lib/checkrun/schemas/schema_policy.py 2>/dev/null || true)
    if [[ -n "$schema_policy" && -f "$schema_policy" ]]; then
      # Checkrun owns schema association matching for hooks, CLI diagnostics,
      # and editors. Project that public LSP surface into VS Code settings here
      # rather than duplicating schema globs in dotfiles.
      python3 "$schema_policy" --lsp-schemas --editor-sources >"$out" 2>/dev/null || printf '{}\n' >"$out"
    fi
  fi
}

# Resolve one Checkrun projection (`capabilities` or `schemas`) into REPLY.
# Each projection launches Python and is fixed for the life of one merge, so
# merge() provides `_vscode_checkrun_memo` (a private directory) and the
# signature plus every config variant share one result. Outside merge() there
# is no memo and callers project directly.
_vscode_checkrun_projection() {
  local kind=$1 out
  [[ -n ${_vscode_checkrun_memo:-} && -d $_vscode_checkrun_memo ]] || return 1
  out=$_vscode_checkrun_memo/$kind.json
  if [[ ! -f $out ]]; then
    case $kind in
      capabilities) _vscode_checkrun_capabilities "$out" ;;
      schemas) _vscode_checkrun_schema_config "$out" ;;
      *) return 2 ;;
    esac
  fi
  REPLY=$out
}

_vscode_write_checkrun_settings() {
  local cap="$1" schema_config="$2" include_sley="$3" out="$4"

  jq --indent 4 \
    --arg include_sley "$include_sley" \
    --slurpfile schema_config "$schema_config" '
    def first_mapped_language($language_map; $ft):
      first(($language_map[$ft] // [$ft])[] | select(type == "string" and length > 0));

    def mapped_languages($language_map; $ft):
      ($language_map[$ft] // [$ft])[] | select(type == "string" and length > 0);

    def custom_associations($language_map):
      (.filetypes.custom // {}) as $custom |
      (
        [($custom.extension // {}) | to_entries[] | {
          key: ("*." + .key),
          value: first_mapped_language($language_map; .value)
        }]
        + [($custom.filename // {}) | to_entries[] | {
          key: .key,
          value: first_mapped_language($language_map; .value)
        }]
        + [($custom.patterns // [])[] | select(.pattern? and .filetype?) | {
          key: .pattern,
          value: first_mapped_language($language_map; .filetype)
        }]
      )
      | map(select(.value != null))
      | unique_by(.key)
      | from_entries;

    def json_schemas:
      ($schema_config[0].json // [])
      | map(select(type == "object")
        | .fileMatch = ((.fileMatch // [])
          | map(select(type == "string" and (startswith("/") | not)))))
      | map(select((.fileMatch // []) | length > 0));

    def yaml_schemas:
      ($schema_config[0].yaml // {})
      | select(type == "object")
      | with_entries(
        .value = ((.value // [])
          | map(select(type == "string" and (startswith("/") | not))))
        | select((.value // []) | length > 0)
      );

    def toml_schema_associations:
      ($schema_config[0].toml // {})
      | select(type == "object")
      | with_entries(select(.key | startswith("^/") | not));

    def sley_formatter_settings($language_map):
      ([(.filetypes.format // [])[] | mapped_languages($language_map; .)]
      | unique
      | reduce .[] as $language ({};
        .["[" + $language + "]"] = {
          "editor.defaultFormatter": "cgraf.sley-tools",
          "editor.formatOnSave": true
        }
      ));

    (.editorLanguageIds.vscode // {}) as $language_map |
    (if $include_sley == "1" then sley_formatter_settings($language_map) else {} end)
    + (custom_associations($language_map) as $assoc |
      if ($assoc | length) > 0 then
        {"files.associations": $assoc}
      else
        {}
      end)
    + (json_schemas as $json |
      if ($json | length) > 0 then
        {"json.schemas": $json}
      else
        {}
      end)
    + (yaml_schemas as $yaml |
      if ($yaml | length) > 0 then
        {"yaml.schemas": $yaml}
      else
        {}
      end)
    + (toml_schema_associations as $toml |
      if ($toml | length) > 0 then
        {"evenBetterToml.schema.associations": $toml}
      else
        {}
      end)
  ' "$cap" >"$out"
}

# Generate VS Code language and schema settings from Checkrun-owned capability
# and schema projections. Checkrun owns the filetype-to-editor language aliases;
# keeping this hook as a projection prevents VS Code settings from growing a
# second copy of language policy.
_vscode_checkrun_settings() {
  local out="$1" include_sley="${2:-1}"
  printf '{}\n' >"$out"

  command -v checkrun >/dev/null 2>&1 || return 0

  local cap schemas tmp
  cap=$(mktemp)
  schemas=$(mktemp)
  tmp=$(mktemp)

  if _vscode_checkrun_projection capabilities; then
    cp "$REPLY" "$cap" || printf '{}\n' >"$cap"
  else
    _vscode_checkrun_capabilities "$cap"
  fi
  if ! jq -e '.filetypes | type == "object"' "$cap" >/dev/null 2>&1; then
    rm -f "$cap" "$schemas" "$tmp"
    return 0
  fi
  if _vscode_checkrun_projection schemas; then
    cp "$REPLY" "$schemas" || printf '{}\n' >"$schemas"
  else
    _vscode_checkrun_schema_config "$schemas"
  fi

  if _vscode_write_checkrun_settings "$cap" "$schemas" "$include_sley" "$tmp"; then
    _vscode_commit_tmp "$tmp" "$out"
  else
    rm -f "$tmp"
    printf '{}\n' >"$out"
  fi
  rm -f "$cap" "$schemas" "$tmp"
}

_remove_vscode_generated_checkrun_settings() {
  local settings="$1"
  [[ -f "$settings" ]] || return 0

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --sort-keys '
    # These settings are complete projections from Checkrun schema policy.
    # Recursive settings merges preserve unknown nested object keys, which is
    # right for hand-written user settings but wrong for generated machine-local
    # fileMatch and file:// schema paths. Drop the old projection before writing
    # the current machine projection so VS Code Settings Sync cannot leave a
    # trail of /Users, /home, and /root entries behind.
    del(.["json.schemas"])
    | del(.["yaml.schemas"])
    | del(.["evenBetterToml.schema.associations"])
  ' "$settings" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$settings"
  else
    rm -f "$tmp"
    return 1
  fi

  _remove_vscode_sley_settings "$settings"
}

_vscode_host_label() {
  if [[ -n "${DOT_TEST_VSCODE_HOSTNAME:-}" ]]; then
    printf '%s\n' "$DOT_TEST_VSCODE_HOSTNAME"
    return 0
  fi

  local host=""
  if command -v hostname >/dev/null 2>&1; then
    host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  fi
  host="${host%%.*}"
  host="${host%$'\r'}"

  if [[ -n "$host" ]]; then
    printf '%s\n' "$host"
  else
    printf 'unknown\n'
  fi
}

_vscode_window_title_settings() {
  local out="$1" host
  host="$(_vscode_host_label)"

  jq -n --indent 4 --arg host "$host" '
    {
      "window.title": (
        $host
        + "${separator}${activeRepositoryBranchName}${separator}${rootNameShort}${separator}${activeEditorShort}"
      )
    }
  ' >"$out"
}

_merge_vscode_window_title() {
  local dst="$1" title_settings rc

  title_settings=$(mktemp)
  if _vscode_window_title_settings "$title_settings"; then
    _merge_vscode_settings "$title_settings" "$dst"
    rc=$?
  else
    rm -f "$title_settings"
    return 1
  fi
  rm -f "$title_settings"
  return "$rc"
}

_vscode_mcp_auth_token_path() {
  dot_xdg_path state "dot/vscode-mcp-auth-token"
}

# Only variants that can actually run nabheet.vscode-ide-mcp (declared under
# editor = "vscode" in the extension manifest family) should receive the
# secret. Cursor variants share this file's discovery/merge plumbing but never
# install that extension, so writing the token there is pure unnecessary secret
# exposure.
# Path substring matching mirrors how _vscode_variants() already identifies
# Cursor (".cursor/extensions", "Cursor/User", ".cursor-server").
_vscode_mcp_auth_applicable() {
  case "$1" in
    *[Cc]ursor*) return 1 ;;
    *) return 0 ;;
  esac
}

# Both openssl and the /dev/urandom fallback must produce non-empty output to
# count as success; a broken openssl invocation (nonzero exit, empty stdout)
# falls through to /dev/urandom instead of failing outright.
_vscode_mcp_auth_generate_token() {
  local token
  if command -v openssl >/dev/null 2>&1; then
    token="$(openssl rand -hex 32 2>/dev/null)" || token=""
    if [[ -n "$token" ]]; then
      printf '%s\n' "$token"
      return 0
    fi
  fi
  if [[ -r /dev/urandom ]]; then
    token="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if [[ -n "$token" ]]; then
      printf '%s\n' "$token"
      return 0
    fi
  fi
  return 1
}

# A crash or disk-full mid-write can leave a short, non-empty, garbage token
# that a bare non-empty check would accept forever. Both generators always
# emit exactly 64 lowercase hex chars, so anything else is corrupt and
# triggers regeneration rather than silently persisting a weak secret.
_vscode_mcp_auth_token_is_valid() {
  local path="$1" contents
  [[ -s "$path" ]] || return 1
  contents="$(<"$path")"
  [[ "$contents" =~ ^[0-9a-f]{64}$ ]]
}

# mkdir is atomic on every POSIX filesystem this repo targets, so it doubles
# as a lock: only one racer can mkdir the same path. A lock left behind by a
# killed/crashed dot update (Ctrl-C, SSH drop, suspend mid-run) would
# otherwise wedge every future run behind it forever, so anything older than
# a minute is treated as abandoned and cleared.
_vscode_mcp_auth_lock_stale() {
  local lock="$1" mtime now
  mtime=$(stat -c '%Y' "$lock" 2>/dev/null || stat -f '%m' "$lock" 2>/dev/null) || return 1
  now=$(date +%s)
  ((now - mtime > 60))
}

# Bearer token for the vscode-ide-mcp extension's local HTTP server, which
# otherwise accepts unauthenticated requests (it treats a missing Origin
# header as a trusted non-browser client). Generated once per machine and
# persisted outside the dotfiles tree so `dot update` keeps re-applying the
# same value without ever committing a secret. This mirrors the
# bearer_token_env_var pattern in codex/config.d: dotfiles own the
# policy of setting a token, not the token itself.
#
# Both first-run creation and corrupt-file recovery are racy across
# concurrent `dot update` invocations (e.g. cron + interactive), so the
# whole generate-and-install step runs inside an mkdir-based mutex: whichever
# process gets the lock first writes the token, and every other racer
# re-checks validity after acquiring (or timing out on) the lock and adopts
# whatever is actually on disk rather than blindly writing its own value —
# otherwise different settings.json files could end up with different
# tokens depending on which process's write landed last.
_vscode_mcp_auth_token() {
  local path
  _vscode_mcp_auth_token_path || return 1
  path="$REPLY"

  if ! _vscode_mcp_auth_token_is_valid "$path"; then
    mkdir -p "$(dirname "$path")" || return 1
    local lock="$path.lock" attempt=0 acquired=1
    until mkdir "$lock" 2>/dev/null; do
      if _vscode_mcp_auth_lock_stale "$lock"; then
        rmdir "$lock" 2>/dev/null
        continue
      fi
      attempt=$((attempt + 1))
      # Give up waiting after ~2s and proceed unlocked rather than hang
      # forever; the only cost is reopening the same narrow race this lock
      # exists to close, not a broken merge. Do NOT rmdir below in this
      # case — the lock is still held by whoever we're waiting on, and
      # removing it out from under them would break their own mutex.
      if ((attempt >= 20)); then
        acquired=0
        break
      fi
      sleep 0.1
    done

    if ! _vscode_mcp_auth_token_is_valid "$path"; then
      local token tmp
      token="$(_vscode_mcp_auth_generate_token)"
      if [[ -n "$token" ]] && dot_sibling_tmp_for "$path"; then
        tmp="$REPLY"
        if (umask 077 && printf '%s\n' "$token" >"$tmp"); then
          mv -f "$tmp" "$path"
        else
          rm -f "$tmp"
        fi
      fi
    fi
    ((acquired)) && rmdir "$lock" 2>/dev/null
  fi

  _vscode_mcp_auth_token_is_valid "$path" || return 1
  REPLY="$(<"$path")"
}

_vscode_mcp_auth_settings() {
  local out="$1"
  printf '{}\n' >"$out"

  if ! _vscode_mcp_auth_token; then
    dot_hook_warn "    warning: could not generate vscode-mcp-server auth token — nabheet.vscode-ide-mcp will run unauthenticated on 127.0.0.1 until this is resolved"
    return 0
  fi
  jq -n --indent 4 --arg token "$REPLY" '{"vscode-mcp-server.authToken": $token}' >"$out"
}

_merge_vscode_mcp_auth() {
  local dst="$1" auth_settings rc
  _vscode_mcp_auth_applicable "$dst" || return 0
  auth_settings=$(mktemp)
  if _vscode_mcp_auth_settings "$auth_settings"; then
    _merge_vscode_settings "$auth_settings" "$dst"
    rc=$?
  else
    rm -f "$auth_settings"
    return 1
  fi
  rm -f "$auth_settings"
  return "$rc"
}

_remove_vscode_sley_settings() {
  local settings="$1"
  [[ -f "$settings" ]] || return 0

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --sort-keys '
    with_entries(
      if ((.key | test("^\\[.*\\]$")) and (.value | type == "object") and
          .value["editor.defaultFormatter"] == "cgraf.sley-tools") then
        .value |= del(.["editor.defaultFormatter"])
        | .value |= (if .["editor.formatOnSave"] == true then del(.["editor.formatOnSave"]) else . end)
      else
        .
      end
    )
    | with_entries(select(
        ((.key | test("^\\[.*\\]$")) | not) or
        (.value | type != "object") or
        ((.value | length) > 0)
      ))
  ' "$settings" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$settings"
  else
    rm -f "$tmp"
  fi
}

_vscode_opts_contains() {
  local opts="$1" wanted="$2"
  case ",$opts," in
    *",$wanted,"*) return 0 ;;
    *) return 1 ;;
  esac
}

_vscode_settings_sources() {
  # The settings family keeps VS Code's native JSON shape per fragment while
  # centralizing ordering and optional .replace behavior in dot core. This hook
  # only cares that it receives an ordered stream of JSON settings layers.
  dot_hook_family_files_matching vscode/settings.d '*.json' '*.replace/*.json'
}

# Print the stable platform key used by keybinding families.
_vscode_keybinding_platform() {
  # _vscode_platform is the canonical host classifier used by variant
  # selection. Map its display vocabulary once so family paths cannot drift
  # into an independent uname/WSL policy.
  case "$(_vscode_platform)" in
    Darwin) printf 'macos\n' ;;
    Linux) printf 'linux\n' ;;
    WSL | Windows) printf 'windows\n' ;;
    *) return 1 ;;
  esac
}

# Print the keybinding families that apply to the current platform.
#
# Keybindings have two independent policies: the shared family mechanism orders
# fragments inside a family, while this hook still owns VS Code's platform
# split. Keeping the platform choice here avoids turning dot core family names
# into semantic concepts like mac/windows/linux.
#
# Args: $1 = optional stable platform key
# Returns merge-hook family names on stdout: common, then platform-specific
# policy. Focus-aware routes stay in common policy because their positive
# context condition is the capability boundary.
_vscode_keybinding_families() {
  local platform="${1:-}"
  if [[ -z "$platform" ]]; then
    platform=$(_vscode_keybinding_platform) || return 1
  fi

  printf '%s\n' vscode/keybindings/all.d
  printf 'vscode/keybindings/%s.d\n' "$platform"
}

# Merge settings into a VS Code config dir.
# $1 = target config dir (e.g., ~/Library/Application Support/Code/User)
# $2 = optional comma-separated variant options.
# $3 = optional logical config dir when rendering into a temporary projection.
_merge_vscode_settings_config() {
  local cfg_dir="$1" opts="${2:-}" logical_cfg_dir="${3:-$1}"

  local settings_src
  while IFS= read -r settings_src; do
    _merge_vscode_settings "$settings_src" "$cfg_dir/settings.json"
  done < <(_vscode_settings_sources)

  local checkrun_settings
  checkrun_settings=$(mktemp)
  if _vscode_opts_contains "$opts" "no-sley"; then
    _vscode_checkrun_settings "$checkrun_settings" 0
    _remove_vscode_generated_checkrun_settings "$cfg_dir/settings.json"
    _merge_vscode_settings "$checkrun_settings" "$cfg_dir/settings.json"
    _remove_vscode_sley_settings "$cfg_dir/settings.json"
  else
    _vscode_checkrun_settings "$checkrun_settings" 1
    _remove_vscode_generated_checkrun_settings "$cfg_dir/settings.json"
    _merge_vscode_settings "$checkrun_settings" "$cfg_dir/settings.json"
  fi
  rm -f "$checkrun_settings"
  _merge_vscode_window_title "$cfg_dir/settings.json"
  if _vscode_mcp_auth_applicable "$logical_cfg_dir/settings.json"; then
    _merge_vscode_mcp_auth "$cfg_dir/settings.json"
  fi
}

# Apply an already-rendered managed settings projection after profile-state has
# restored the user baseline. Building that projection resolves Checkrun and
# every source family; repeating that work here made unchanged updates pay for
# the same policy twice. The cleanup still runs against the live baseline so
# settings imported by Settings Sync cannot preserve retired generated values.
_vscode_apply_settings_projection() {
  local managed=$1 destination=$2 opts=${3:-}

  _remove_vscode_generated_checkrun_settings "$destination" || return 1
  _merge_vscode_settings "$managed" "$destination" || return 1
  if _vscode_opts_contains "$opts" "no-sley"; then
    _remove_vscode_sley_settings "$destination" || return 1
  fi
  return 0
}

# Materialize the ordered source policy once. The active projection and the
# live destination both need the complete retirement history, so reusing only
# the final active bindings would be incorrect for Settings Sync migrations.
_vscode_build_keybinding_source() {
  local output=$1
  local kb_family kb_source kb_platform kb_dir kb_layer kb_list=
  local -a kb_args=()
  kb_platform=$(_vscode_keybinding_platform) || return 1
  # Strip each layer with one awk process, then validate and prepend every
  # layer in a single jq. Merges rebuild this source often, and per-layer temp
  # files plus two jq starts per layer dominated its cost. Each layer is a
  # separate --slurpfile, so jq parses every file on its own: a layer holding
  # zero or several documents, or a truncated one, still fails as before.
  kb_dir=$(mktemp -d) || return 1
  while IFS= read -r kb_family; do
    while IFS= read -r kb_source; do
      kb_layer=L$((${#kb_args[@]} / 3))
      _strip_jsonc "$kb_source" >"$kb_dir/$kb_layer" || {
        rm -rf -- "$kb_dir" "$output"
        return 1
      }
      kb_args+=(--slurpfile "$kb_layer" "$kb_dir/$kb_layer")
      kb_list+="${kb_list:+, }\$$kb_layer"
    done < <(dot_hook_family_files_matching "$kb_family" '*.jsonc' '*.replace/*.jsonc')
  done < <(_vscode_keybinding_families "$kb_platform")
  # kb_list is the generated "$L0, $L1, ..." sequence, in source order.
  # shellcheck disable=SC2016 # $layer is a jq variable.
  if ! jq -n ${kb_args[@]+"${kb_args[@]}"} '
    reduce ['"$kb_list"'][] as $layer ([];
      if ($layer | length) == 1 and ($layer[0] | type == "array")
      then $layer[0] + .
      else error("expected one array")
      end)
  ' >"$output"; then
    rm -rf -- "$kb_dir" "$output"
    return 1
  fi
  rm -rf -- "$kb_dir"
}

# Merge keybindings into a VS Code config dir.
_merge_vscode_keybindings_config() {
  local cfg_dir=$1

  # Aggregate every applicable source before reconciliation. This keeps
  # two current fragments with the same action but distinct conditions from
  # mistaking each other for stale output, while preserving the existing
  # later-fragment-first output precedence.
  local kb_aggregate
  kb_aggregate=$(mktemp)
  if ! _vscode_build_keybinding_source "$kb_aggregate"; then
    rm -f "$kb_aggregate"
    dot_hook_warn "    warning: keybindings source aggregation failed for $cfg_dir — skipping"
    return 1
  fi
  if ! _merge_vscode_keybindings \
    "$kb_aggregate" \
    "$cfg_dir/keybindings.json"; then
    rm -f "$kb_aggregate"
    return 1
  fi
  rm -f "$kb_aggregate"
}

_merge_vscode_config() {
  local cfg_dir=$1 opts=${2:-}
  _merge_vscode_settings_config "$cfg_dir" "$opts" "$cfg_dir" || return 1
  _merge_vscode_keybindings_config "$cfg_dir"
}

_vscode_profile_state_publisher() {
  local destination=$1
  if _vscode_is_wsl && {
    [[ $destination != "$HOME/"* ]] ||
      { [[ -n ${DOT_TEST_WINDOWS_APPDATA:-} ]] &&
        [[ $destination == "$DOT_TEST_WINDOWS_APPDATA/"* ]]; }
  }; then
    printf 'verified-in-place\n'
  else
    printf 'atomic\n'
  fi
}

# Commit the active profile-state transaction for DESTINATION (optionally with
# a links file) and remember the blob id of the bytes it committed. merge()
# declares `_vscode_committed_sums`; the no-op signature records these
# instead of re-reading destinations after the merge, so a write by another
# program after a commit forces the next update through the full merge.
_vscode_commit_tracked() {
  local destination=$1
  shift
  dev_profile_state_commit "$@" || return
  if [[ -n ${DEV_PROFILE_STATE_COMMITTED_SUM:-} ]] &&
    declare -p _vscode_committed_sums >/dev/null 2>&1; then
    _vscode_committed_sums[$destination]=$DEV_PROFILE_STATE_COMMITTED_SUM
  fi
}

_merge_vscode_config_tracked() {
  local cfg_dir=$1 opts=${2:-} managed_dir publisher keybinding_source
  local baseline work
  _dev_profile_state_tempdir || return 1
  managed_dir=$REPLY
  keybinding_source=$managed_dir/keybindings-source.json
  if ! _merge_vscode_settings_config "$managed_dir" "$opts" "$cfg_dir"; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  if ! _vscode_build_keybinding_source "$keybinding_source"; then
    dot_hook_warn "    warning: keybindings source aggregation failed for $cfg_dir — skipping"
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  if ! _merge_vscode_keybindings \
    "$keybinding_source" "$managed_dir/keybindings.json"; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  publisher=$(_vscode_profile_state_publisher "$cfg_dir/settings.json") || {
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  }

  # Deferred transactions build the final document off-live: begin stages
  # the user baseline without touching the live files, and publish_final
  # installs the merged result in one guarded write. Live-editing the
  # baseline first made VS Code's restart prompt fire on every run.
  if ! dev_profile_state_begin vscode-settings jsonc \
    "$cfg_dir/settings.json" "$managed_dir/settings.json" "$publisher" deferred; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  baseline=$REPLY
  work=$managed_dir/working-settings.json
  if ! cp "$baseline" "$work" ||
    ! _vscode_apply_settings_projection \
      "$managed_dir/settings.json" "$work" "$opts" ||
    ! dev_profile_state_publish_final "$work" ||
    ! _vscode_commit_tracked "$cfg_dir/settings.json"; then
    dev_profile_state_abort || true
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi

  if ! dev_profile_state_begin vscode-keybindings jsonc \
    "$cfg_dir/keybindings.json" "$managed_dir/keybindings.json" "$publisher" deferred; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  baseline=$REPLY
  work=$managed_dir/working-keybindings.json
  if ! cp "$baseline" "$work" ||
    ! _merge_vscode_keybindings \
      "$keybinding_source" "$work" ||
    ! dev_profile_state_publish_final "$work" ||
    ! _vscode_commit_tracked "$cfg_dir/keybindings.json"; then
    dev_profile_state_abort || true
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  _dev_profile_state_tempdir_remove "$managed_dir"
}

# Ensure a local extension is registered in an extensions.json.
# Existing local entries are refreshed so path corrections take effect.
# $1 = extension ID (e.g., cgraf.sley-tools)
# $2 = extension dir name (e.g., sley-tools-0.0.1)
# $3 = extensions.json path
# $4 = optional location.path override
_ensure_vscode_extension() {
  local ext_id="$1" ext_dir="$2" ext_json="$3" location_path="${4:-}"

  local ext_base ext_version
  _vscode_dirname "$ext_json"
  ext_base=$REPLY
  [[ -d $ext_base ]] || mkdir -p "$ext_base"
  [[ -d "$ext_base/$ext_dir" ]] || return 0
  [[ -n "$location_path" ]] || location_path="$ext_base/$ext_dir"
  ext_version=$(jq -r '.version // empty | select(type == "string")' \
    "$ext_base/$ext_dir/package.json" 2>/dev/null || true)
  [[ -n "$ext_version" ]] || ext_version="0.0.1"

  if [[ ! -f "$ext_json" ]]; then
    printf '[]\n' >"$ext_json"
  fi

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --arg id "$ext_id" --arg dir "$ext_dir" \
    --arg path "$location_path" --arg version "$ext_version" '
    def local_extension_entry: {
      identifier: {id: $id},
      version: $version,
      location: {"\u0024mid": 1, path: $path, scheme: "file"},
      relativeLocation: $dir,
      metadata: {source: "local"}
    };

    if any(.[]; (.identifier.id // "") == $id) then
      map(if (.identifier.id // "") == $id then local_extension_entry else . end)
    else
      . + [local_extension_entry]
    end
  ' "$ext_json" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$ext_json"
  else
    rm -f "$tmp"
    return 1
  fi
}

_remove_vscode_extension() {
  local ext_id="$1" ext_dir="$2" ext_json="$3"

  local ext_base
  _vscode_dirname "$ext_json"
  ext_base=$REPLY
  if [[ -L "$ext_base/$ext_dir" ]]; then
    rm -f "$ext_base/$ext_dir" || return 1
  fi

  [[ -f "$ext_json" ]] || return 0

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --arg id "$ext_id" \
    'map(select((.identifier.id // "") != $id))' "$ext_json" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$ext_json"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Remove older symlinked generations of one dot-managed local extension. Limit
# ownership to links whose name and target stay under the declared source
# family, which also identifies a managed generation after its target vanishes
# without claiming same-ID development links elsewhere.
_prune_vscode_extension_versions() {
  local ext_id="$1" managed_source="$2" keep_dir="$3" ext_json="$4"
  local ext_base managed_parent extension_name
  local candidate candidate_dir target target_dir target_name version_suffix
  _vscode_dirname "$ext_json"
  ext_base=$REPLY
  _vscode_dirname "$managed_source"
  managed_parent=$REPLY
  extension_name="${ext_id#*.}"

  for candidate in "$ext_base"/*; do
    [[ -L "$candidate" ]] || continue
    candidate_dir="${candidate##*/}"
    [[ -z "$keep_dir" || "$candidate_dir" != "$keep_dir" ]] || continue
    target=$(readlink "$candidate") || continue
    [[ "$target" == /* ]] || target="$ext_base/$target"
    _vscode_dirname "$target"
    target_dir=$REPLY
    target_name="${target##*/}"
    # Shdeps may spell one provider root two ways (its managed checkout link
    # and the development clone it points at), so accept the same directory
    # under either spelling while it still exists.
    [[ "$target_dir" == "$managed_parent" || "$target_dir" -ef "$managed_parent" ]] ||
      continue
    [[ "$candidate_dir" == "$target_name" ]] || continue
    # A live generation proves or disproves ownership through its manifest, so
    # any folder name the provider chose is recognized and a sibling extension
    # is never claimed by name.
    if [[ -f "$candidate/package.json" ]]; then
      _vscode_extension_dir_is "$ext_id" "$candidate" || continue
      rm -f "$candidate" || return 1
      continue
    fi
    # Broken managed generations no longer have package metadata, so the name
    # is the remaining ownership proof. Require the complete suffix to be a
    # dotted semver (with optional prerelease/build tails); a first-digit check
    # would still claim a sibling such as termnav-2-tools-*.
    if [[ "$target_name" != "$extension_name" ]]; then
      [[ "$target_name" == "${extension_name}-"* ]] || continue
      version_suffix="${target_name#"$extension_name"-}"
      [[ "$version_suffix" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)*$ ]] || continue
    fi
    rm -f "$candidate" || return 1
  done
}

# Remove dot-managed local extensions whose source has been retired. A deleted
# source leaves the installed symlink dangling; metadata.source distinguishes
# these registrations from gallery extensions without claiming ownership of
# unrelated local directories.
_prune_vscode_local_extensions() {
  local ext_json="$1" ext_base ext_id ext_dir
  [[ -f "$ext_json" ]] || return 0

  _vscode_dirname "$ext_json"
  ext_base=$REPLY
  while IFS=$'\t' read -r ext_id ext_dir; do
    [[ -n "$ext_id" && -n "$ext_dir" ]] || continue
    [[ "$ext_dir" == "${ext_dir##*/}" && "$ext_dir" != "." && "$ext_dir" != ".." ]] || continue
    if [[ -L "$ext_base/$ext_dir" && ! -e "$ext_base/$ext_dir" ]]; then
      _remove_vscode_extension "$ext_id" "$ext_dir" "$ext_json" || return 1
    fi
  done < <(jq -r '.[] | select(.metadata.source == "local") |
    [(.identifier.id // ""), (.relativeLocation // "")] | @tsv' "$ext_json")
}

_vscode_wsl_appdata_dirs() {
  # Every Linux account on this WSL distro can ask Windows for the same
  # profile. Only the account paired with it (dot_wsl_is_paired_windows_account)
  # may resolve it here — checked first, ahead of the test overrides below, so
  # DOT_TEST_WINDOWS_APPDATA can't be used to bypass it in tests either.
  dot_wsl_is_paired_windows_account || return 0

  if [[ -n "${DOT_TEST_WINDOWS_APPDATA:-}" ]]; then
    printf '%s\n' "$DOT_TEST_WINDOWS_APPDATA"
    return 0
  fi

  if [[ "${DOT_TEST:-0}" = 1 ]]; then
    # WSL exposes the real Windows profile even when tests replace HOME.
    # Tests must opt in with DOT_TEST_WINDOWS_APPDATA to avoid host writes.
    return 0
  fi

  # Query %APPDATA% directly rather than deriving it from
  # dot_wsl_windows_home()'s USERPROFILE (as WezTerm does): a profile with
  # Windows folder redirection can have %APPDATA% pointed somewhere other
  # than %USERPROFILE%\AppData\Roaming, and VS Code itself follows %APPDATA%.
  local cmd_appdata=""
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd_appdata="$(cmd.exe /C 'echo %APPDATA%' </dev/null 2>/dev/null | tr -d '\r')" || true
  elif [[ -x /mnt/c/Windows/System32/cmd.exe ]]; then
    cmd_appdata="$(/mnt/c/Windows/System32/cmd.exe /C 'echo %APPDATA%' </dev/null 2>/dev/null | tr -d '\r')" || true
  fi
  if [[ -n "$cmd_appdata" && "$cmd_appdata" != "." ]]; then
    local converted
    converted="$(wslpath "$cmd_appdata" 2>/dev/null)" || true
    if [[ -n "$converted" && "$converted" == */AppData/Roaming ]]; then
      printf '%s\n' "$converted"
      return 0
    fi
  fi
}

_vscode_applications_dir() {
  printf '%s\n' "${DOT_TEST_VSCODE_APPLICATIONS_DIR:-/Applications}"
}

# Expand path fragments in variant data files without evaluating arbitrary shell.
_vscode_expand_path() {
  local path="$1"
  local app_ref="\${VSCODE_APPLICATIONS_DIR}"
  local app_dir
  app_dir="$(_vscode_applications_dir)"
  path="${path//"$app_ref"/$app_dir}"
  path="${path//\$VSCODE_APPLICATIONS_DIR/$app_dir}"

  local appdata_ref="\${APPDATA}"
  if [[ "$path" == *"$appdata_ref"* || "$path" == *"\$APPDATA"* ]]; then
    [[ -n "${APPDATA:-}" ]] || {
      printf '\n'
      return 0
    }
    path="${path//"$appdata_ref"/$APPDATA}"
    path="${path//\$APPDATA/$APPDATA}"
  fi

  local braced_home="\${HOME}"
  if [[ "$path" == "$braced_home" ]]; then
    printf '%s\n' "$HOME"
    return 0
  fi
  if [[ "$path" == "$braced_home/"* ]]; then
    printf '%s/%s\n' "$HOME" "${path:$((${#braced_home} + 1))}"
    return 0
  fi

  case "$path" in
    "" | "-") printf '\n' ;;
    \$HOME) printf '%s\n' "$HOME" ;;
    \$HOME/*) printf '%s/%s\n' "$HOME" "${path#\$HOME/}" ;;
    # \~ (escaped) keeps this a literal-tilde pattern. An unescaped ~ here
    # would undergo bash's own tilde expansion to the current $HOME before
    # matching, so it would also match any already-absolute path that simply
    # happens to live under $HOME (e.g. "$HOME/.vscode/extensions" written
    # out literally) and double-prefix it with $HOME again.
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${path#\~/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

_vscode_platform() {
  case "$(uname -s)" in
    Darwin) printf 'Darwin\n' ;;
    Linux)
      if _vscode_is_wsl; then
        printf 'WSL\n'
      else
        printf 'Linux\n'
      fi
      ;;
    MINGW* | MSYS*) printf 'Windows\n' ;;
    *) printf '%s\n' "$(uname -s)" ;;
  esac
}

_vscode_platform_matches() {
  local wanted="$1" current="$2"
  [[ "$wanted" == "*" || "$wanted" == "$current" ]]
}

_vscode_substitute_wsl_appdata() {
  local value="$1" appdata="$2"
  local appdata_ref="\${WSL_APPDATA}"
  value="${value//"$appdata_ref"/$appdata}"
  value="${value//\$WSL_APPDATA/$appdata}"
  printf '%s\n' "$value"
}

_vscode_variant_uses_wsl_appdata() {
  local braced_wsl_appdata="\${WSL_APPDATA}"
  local plain_wsl_appdata="\$WSL_APPDATA"
  case "$1	$2	$3" in
    *"$braced_wsl_appdata"* | *"$plain_wsl_appdata"*) return 0 ;;
    *) return 1 ;;
  esac
}

_vscode_record_variant() {
  local marker="$1" ext_dir="$2" cfg_dir="$3" opts="${4:-}"
  marker="$(_vscode_expand_path "$marker")"
  ext_dir="$(_vscode_expand_path "$ext_dir")"
  cfg_dir="$(_vscode_expand_path "$cfg_dir")"

  [[ -n "$marker" && -e "$marker" ]] || return 0
  [[ -n "$ext_dir" ]] || return 0

  # Config-bearing variants are active only after the app has created its user
  # config dir. Extension-only variants, such as remote VS Code server profiles,
  # are active when their extension dir already exists.
  if [[ -n "$cfg_dir" ]]; then
    [[ -d "$cfg_dir" ]] || return 0
  else
    [[ -d "$ext_dir" ]] || return 0
  fi

  if [[ -n "$opts" ]]; then
    printf '%s\t%s\t%s\n' "$ext_dir" "$cfg_dir" "$opts"
  else
    printf '%s\t%s\n' "$ext_dir" "$cfg_dir"
  fi
}

_vscode_variant_sources() {
  # Variant files are another overlay extension point. Keep the family contract
  # named here so discovery, docs, and tests can drift together less.
  dot_hook_family_files_matching vscode/variants.d '*.tsv' '*.replace/*.tsv'
}

_vscode_local_extension_sources() {
  dot_hook_family_files_matching vscode/local-extensions.d '*.tsv' '*.replace/*.tsv'
}

_vscode_extension_manifest_sources() {
  # Extension manifests are TOML fragments. Each file may be incomplete; the
  # vscode-exts provider validates the aggregate after dot core has selected the
  # family stream and any .replace winners.
  dot_hook_family_files_matching vscode/extensions.d '*.toml' '*.replace/*.toml'
}

_vscode_install_declared_extensions() {
  # Broader merge tests focus on settings/keybindings/local-extension behavior
  # and should not accidentally call a developer's real VS Code CLI. Production
  # dot updates leave this unset; the dedicated vscode-extensions-test exercises
  # this adapter with a fake provider.
  [[ "${DOT_VSCODE_EXTENSIONS_SKIP:-0}" = 1 ]] && return 0

  # vscode-exts owns manifest parsing, platform discovery, locking, and editor
  # CLI behavior. Dot owns only activation timing and selection of its overlay
  # fragment stream. Resolve the dependency once so the adapter cannot drift
  # into a second implementation or accidentally fall through to XDG discovery.
  local provider
  provider=$(command -v vscode-exts) || return 0

  local -a args=()
  local manifest
  while IFS= read -r manifest; do
    args+=(--manifest "$manifest")
  done < <(_vscode_extension_manifest_sources)

  ((${#args[@]} > 0)) || return 0

  # Runtime extension installation is advisory, but malformed manifest fragments
  # are dotfiles configuration errors. The provider keeps network/gallery
  # failures at exit 0 after warning; exit 2 is reserved for invalid aggregate
  # policy.
  local rc=0
  (
    # The provider intentionally has no dependency on dotfiles names. Preserve
    # Dot's established WSL and timeout controls at this activation boundary,
    # while letting an explicitly provider-scoped value win. Keep the exports
    # inside a subshell so one merge hook cannot affect another consumer.
    local compat_windows_home=""
    if [[ -z "${VSCODE_EXTS_WINDOWS_HOME+x}" ]]; then
      compat_windows_home="${DOT_TEST_WINDOWS_HOME:-${DOT_WINDOWS_HOME:-${DOT_VSCODE_WINDOWS_HOME:-}}}"
      if [[ -n "$compat_windows_home" ]]; then
        VSCODE_EXTS_WINDOWS_HOME="$compat_windows_home"
        export VSCODE_EXTS_WINDOWS_HOME
      fi
    fi
    if [[ -z "${VSCODE_EXTS_TIMEOUT_SECONDS+x}" &&
      -n "${DOT_VSCODE_EXTENSIONS_TIMEOUT_SECONDS:-}" ]]; then
      VSCODE_EXTS_TIMEOUT_SECONDS="$DOT_VSCODE_EXTENSIONS_TIMEOUT_SECONDS"
      export VSCODE_EXTS_TIMEOUT_SECONDS
    fi
    if [[ -z "${VSCODE_EXTS_TEST_MODE+x}" && "${DOT_TEST:-0}" = 1 ]]; then
      # Preserve the old resolver's safety boundary: an isolated Dot test must
      # never discover and write through to the real Windows profile in WSL.
      VSCODE_EXTS_TEST_MODE=1
      export VSCODE_EXTS_TEST_MODE
    fi

    "$provider" "${args[@]}"
  ) || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    dot_hook_warn "    warning: invalid VS Code extension manifest"
    return "$rc"
  elif [[ "$rc" -ne 0 ]]; then
    dot_hook_warn "    warning: VS Code extension install failed — skipping"
  fi
}

_vscode_remote_settings_dirs() {
  local root

  for root in \
    "$HOME/.vscode-server" \
    "$HOME/.vscode-server-insiders" \
    "$HOME/.vscode-remote" \
    "$HOME/.cursor-server"; do
    # Server roots are discovered opportunistically. An inaccessible leftover
    # (for example, one created by a privileged installer) is not a client
    # config surface and must not make every dot update fail.
    [[ -d "$root" && -O "$root" && -x "$root" ]] || continue
    printf '%s/data/Machine\n' "$root"
  done
}

_merge_vscode_remote_settings_tracked() {
  local cfg_dir=$1 managed_dir publisher
  local destination=$cfg_dir/settings.json
  local baseline work
  _dev_profile_state_tempdir || return 1
  managed_dir=$REPLY
  printf '{}\n' >"$managed_dir/settings.json"
  if ! _merge_vscode_window_title "$managed_dir/settings.json"; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  if _vscode_mcp_auth_applicable "$destination" &&
    ! _merge_vscode_mcp_auth "$managed_dir/settings.json"; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  publisher=$(_vscode_profile_state_publisher "$destination") || {
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  }
  # Deferred: stage the final document off-live so observers never see the
  # managed-stripped intermediate state (see _merge_vscode_config_tracked).
  if ! dev_profile_state_begin vscode-settings jsonc \
    "$destination" "$managed_dir/settings.json" "$publisher" deferred; then
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  baseline=$REPLY
  work=$managed_dir/working-settings.json
  if ! cp "$baseline" "$work" ||
    ! _merge_vscode_window_title "$work" ||
    { _vscode_mcp_auth_applicable "$destination" &&
      ! _merge_vscode_mcp_auth "$work"; } ||
    ! dev_profile_state_publish_final "$work" ||
    ! _vscode_commit_tracked "$destination"; then
    dev_profile_state_abort || true
    _dev_profile_state_tempdir_remove "$managed_dir" || true
    return 1
  fi
  _dev_profile_state_tempdir_remove "$managed_dir"
}

_merge_vscode_remote_configs_tracked() {
  local remote_settings_dir status=0
  while IFS= read -r remote_settings_dir; do
    _merge_vscode_remote_settings_tracked "$remote_settings_dir" || status=1
  done < <(_vscode_remote_settings_dirs)
  return "$status"
}

_vscode_variant_file_records() {
  local current
  current="$(_vscode_platform)"

  # WSL is called out as its own platform value here specifically so overlay
  # rows can declare extra config dirs under the native Windows profile (see
  # the merge-hooks README) — the same single-shared-file hazard as the
  # built-in WSL appdata variant below, so gate every row the same way rather
  # than trusting each future overlay author to remember it per row.
  if [[ "$current" == "WSL" ]]; then
    dot_wsl_is_paired_windows_account || return 0
  fi

  local file platform marker ext_dir cfg_dir opts _rest appdata
  while IFS= read -r file; do
    while IFS=$'\t' read -r platform marker ext_dir cfg_dir opts _rest || [[ -n "${platform:-}" ]]; do
      [[ -n "${platform:-}" ]] || continue
      [[ "$platform" == \#* ]] && continue
      _vscode_platform_matches "$platform" "$current" || continue
      if _vscode_variant_uses_wsl_appdata "$marker" "$ext_dir" "$cfg_dir"; then
        while IFS= read -r appdata; do
          [[ -n "$appdata" ]] || continue
          _vscode_record_variant \
            "$(_vscode_substitute_wsl_appdata "$marker" "$appdata")" \
            "$(_vscode_substitute_wsl_appdata "$ext_dir" "$appdata")" \
            "$(_vscode_substitute_wsl_appdata "$cfg_dir" "$appdata")" \
            "$opts"
        done < <(_vscode_wsl_appdata_dirs)
      else
        _vscode_record_variant "$marker" "$ext_dir" "$cfg_dir" "$opts"
      fi
    done <"$file"
  done < <(_vscode_variant_sources)
}

# Discover installed VS Code variants.  Each entry is a pair of tab-separated
# paths: extensions_dir<TAB>config_dir.  The config dir may be empty for remote
# extension-host profiles that need local extensions registered but do not own a
# user settings/keybindings file on this machine.
_vscode_variants() {
  # A later overlay may refine an existing target with local capability
  # options. Collapse matching extension/config directory pairs here so the
  # final policy wins without processing the same installation twice.
  _vscode_variant_file_records | awk -F '\t' '
    {
      key = $1 SUBSEP $2
      order[NR] = key
      last[key] = NR
      record[key] = $0
    }
    END {
      for (i = 1; i <= NR; i++) {
        key = order[i]
        if (last[key] == i) {
          print record[key]
        }
      }
    }
  '
}

_vscode_opts_intersect() {
  local opts="$1" disabled_opts="$2" disabled
  [[ -n "$disabled_opts" && "$disabled_opts" != "-" ]] || return 1

  local IFS=','
  for disabled in $disabled_opts; do
    [[ -n "$disabled" ]] || continue
    _vscode_opts_contains "$opts" "$disabled" && return 0
  done
  return 1
}

# Succeed when DIR holds the VS Code extension EXT_ID. VS Code identifies an
# extension by its manifest's `<publisher>.<name>`, case-insensitively; the
# folder name is only the provider's packaging choice and usually embeds the
# manifest version, which moves independently of the provider's own release
# version. A manifest without a publisher matches on name alone.
_vscode_extension_dir_is() {
  local ext_id=$1 dir=$2
  [[ -f $dir/package.json ]] || return 1
  jq -e --arg id "$ext_id" '
    ($id | ascii_downcase) as $id
    | (.name | ascii_downcase) as $name
    | (.publisher // "" | ascii_downcase) as $publisher
    | $name != ""
      and if $publisher == "" then ($id | sub("^[^.]*[.]"; "")) == $name
          else $publisher + "." + $name == $id end
  ' "$dir/package.json" >/dev/null 2>&1
}

# Resolve the directory holding EXT_ID inside a provider dependency, through
# REPLY.
#
# Providers publish editor adapters under `share/<repo>/vscode/`, next to their
# other `share/<repo>/` assets. Where the dependency itself lives is shdeps'
# contract (install roots, development-clone precedence, host filters), so ask
# it instead of spelling an install layout here, then select the one folder
# whose manifest identifies EXT_ID, whatever its name.
#
# Returns 1 without output when the dependency is inactive, not installed, or
# unknown on this host: shdeps reports all three the same way, and provider
# absence is a supported state. Returns 2 after warning when the dependency is
# not an `owner/repo` name shdeps accepts, or an installed provider publishes
# no unique match. For the last case REPLY names a nonexistent path under the
# provider's extension directory (or is empty when none is safe), so opt-out
# variants can still unregister the extension and prune its managed
# generations from that directory.
_vscode_resolve_local_extension() {
  local ext_id=$1 dependency=$2 vscode_dir candidate match="" count=0 rc=0
  REPLY=""
  if [[ ! $dependency =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    dot_hook_warn "    warning: VS Code local extension $ext_id names an invalid dependency: $dependency"
    return 2
  fi
  command -v shdeps >/dev/null 2>&1 || return 1
  # Read the same tracked configuration as the base dep-file helper does.
  vscode_dir=$(SHDEPS_CONF_DIR="$HOME/.config/shdeps" \
    shdeps dep-path "$dependency" "share/${dependency##*/}/vscode" 2>/dev/null) ||
    rc=$?
  if ((rc == 2)); then
    dot_hook_warn "    warning: shdeps rejects dependency $dependency for VS Code local extension $ext_id"
    return 2
  fi
  ((rc == 0)) && [[ -n $vscode_dir ]] || return 1

  for candidate in "$vscode_dir"/*/; do
    candidate=${candidate%/}
    _vscode_extension_dir_is "$ext_id" "$candidate" || continue
    match=$candidate
    count=$((count + 1))
  done
  if ((count == 1)); then
    REPLY=$match
    return 0
  fi

  if ((count == 0)); then
    dot_hook_warn "    warning: $dependency publishes no VS Code extension $ext_id under $vscode_dir"
  else
    dot_hook_warn "    warning: $dependency publishes $count copies of VS Code extension $ext_id under $vscode_dir — skipping"
  fi
  candidate=$vscode_dir/${ext_id#*.}
  [[ -e $candidate || -L $candidate ]] || REPLY=$candidate
  return 2
}

# Emit one `extension_id<TAB>source_dir<TAB>disabled_options` record per
# declared local extension whose provider is present on this host.
_vscode_local_extensions() {
  local file ext_id dependency disabled_opts _rest
  while IFS= read -r file; do
    while IFS=$'\t' read -r ext_id dependency disabled_opts _rest || [[ -n "${ext_id:-}" ]]; do
      [[ -n "${ext_id:-}" ]] || continue
      [[ "$ext_id" == \#* ]] && continue
      if [[ -z "${dependency:-}" || -n "${_rest:-}" ]]; then
        dot_hook_warn "    warning: malformed VS Code local extension row in $file"
        continue
      fi
      _vscode_resolve_local_extension "$ext_id" "$dependency" || [[ -n $REPLY ]] || continue
      printf '%s\t%s\t%s\n' "$ext_id" "$REPLY" "${disabled_opts:-}"
    done <"$file"
  done < <(_vscode_local_extension_sources)
}

# Emit the config-bearing variant records that should drive settings and
# keybinding reconciliation. Multiple extension hosts can deliberately share a
# single user config directory (for example, stable and insiders builds). Each
# _merge_vscode_config call fully reconciles that directory, so replaying every
# host does duplicate work and makes the final result depend on the last call
# anyway. Keep that existing last-declaration-wins policy explicit.
_vscode_config_variants() {
  local -a variants=("$@")
  local i j line rest cfg_dir later_rest later_cfg_dir superseded

  for ((i = 0; i < ${#variants[@]}; i++)); do
    line="${variants[$i]}"
    rest="${line#*	}"
    cfg_dir="${rest%%	*}"
    [[ -n "$cfg_dir" ]] || continue

    superseded=0
    for ((j = i + 1; j < ${#variants[@]}; j++)); do
      later_rest="${variants[$j]#*	}"
      later_cfg_dir="${later_rest%%	*}"
      if [[ "$later_cfg_dir" == "$cfg_dir" ]]; then
        superseded=1
        break
      fi
    done
    ((superseded)) || printf '%s\n' "$line"
  done
}

# Extension reconciliation depends only on the extension directory and its
# effective options; the associated config directory is irrelevant. Some
# editor installations expose the same extension host through multiple config
# targets, so collapse exact extension-policy duplicates at their last
# occurrence while retaining distinct policies for the same directory.
_vscode_extension_variants() {
  local -a variants=("$@")
  local i j line rest cfg_dir opts later_line later_rest later_cfg_dir
  local later_opts superseded

  for ((i = 0; i < ${#variants[@]}; i++)); do
    line="${variants[$i]}"
    rest="${line#*	}"
    cfg_dir="${rest%%	*}"
    opts="${rest#*	}"
    [[ $opts == "$cfg_dir" ]] && opts=

    superseded=0
    for ((j = i + 1; j < ${#variants[@]}; j++)); do
      later_line="${variants[$j]}"
      later_rest="${later_line#*	}"
      later_cfg_dir="${later_rest%%	*}"
      later_opts="${later_rest#*	}"
      [[ $later_opts == "$later_cfg_dir" ]] && later_opts=
      if [[ "${later_line%%	*}" == "${line%%	*}" &&
        "$later_opts" == "$opts" ]]; then
        superseded=1
        break
      fi
    done
    ((superseded)) || printf '%s\n' "$line"
  done
}

# Build from the caller's declaration snapshot so every extension target sees
# one consistent policy without rescanning the declaration sources.
_vscode_build_managed_extensions() {
  local ext_dir=$1 opts=$2 output=$3 work projection local_extension
  local ext_id ext_src disabled_opts ext_name
  shift 3
  local -a local_extensions=("$@")
  _dev_profile_state_tempdir || return 1
  work=$REPLY
  projection=$work/extensions/extensions.json
  mkdir -p "${projection%/*}" || {
    _dev_profile_state_tempdir_remove "$work" || true
    return 1
  }
  printf '[]\n' >"$projection"
  for local_extension in ${local_extensions[@]+"${local_extensions[@]}"}; do
    IFS=$'\t' read -r ext_id ext_src disabled_opts <<<"$local_extension"
    _vscode_opts_intersect "$opts" "$disabled_opts" && continue
    [[ -d $ext_src ]] || continue
    ext_name=${ext_src##*/}
    ln -s "$ext_src" "$work/extensions/$ext_name" || {
      _dev_profile_state_tempdir_remove "$work" || true
      return 1
    }
    _ensure_vscode_extension \
      "$ext_id" "$ext_name" "$projection" "$ext_dir/$ext_name" || {
      _dev_profile_state_tempdir_remove "$work" || true
      return 1
    }
  done
  cp "$projection" "$output" || {
    _dev_profile_state_tempdir_remove "$work" || true
    return 1
  }
  _dev_profile_state_tempdir_remove "$work"
}

_vscode_merge_extensions_tracked() {
  local line=$1 ext_dir rest cfg_dir opts work managed links next_links
  shift
  local ext_id ext_src disabled_opts ext_name ext_link ext_target legacy_ext_src
  local local_extension cached_extensions=0
  local index status=0 rollback_status=0
  local -a local_extensions=()

  # merge() passes an explicit snapshot after --. Preserve the historical
  # direct-call contract for focused lifecycle tests and other internal users.
  if (($# > 0)) && [[ $1 == -- ]]; then
    cached_extensions=1
    shift
    local_extensions=("$@")
  fi
  if ((cached_extensions == 0)); then
    while IFS= read -r local_extension; do
      local_extensions+=("$local_extension")
    done < <(_vscode_local_extensions)
  fi
  local -a changed_paths=() changed_kinds=() old_targets=() new_targets=()

  ext_dir=${line%%	*}
  rest=${line#*	}
  cfg_dir=${rest%%	*}
  opts=${rest#*	}
  [[ $opts == "$cfg_dir" ]] && opts=

  # Broken and explicitly disabled generations are permanent hygiene, not
  # active-profile ownership. Remove them before capturing the reversible
  # baseline so a later downgrade cannot resurrect stale registrations.
  _prune_vscode_local_extensions "$ext_dir/extensions.json" || return 1
  for local_extension in ${local_extensions[@]+"${local_extensions[@]}"}; do
    IFS=$'\t' read -r ext_id ext_src disabled_opts <<<"$local_extension"
    ext_name=${ext_src##*/}
    if _vscode_opts_intersect "$opts" "$disabled_opts"; then
      _prune_vscode_extension_versions \
        "$ext_id" "$ext_src" "" "$ext_dir/extensions.json" || return 1
      _remove_vscode_extension \
        "$ext_id" "$ext_name" "$ext_dir/extensions.json" || return 1
      continue
    fi
    [[ -d $ext_src ]] || continue
    _prune_vscode_extension_versions \
      "$ext_id" "$ext_src" "$ext_name" "$ext_dir/extensions.json" || return 1
  done

  _dev_profile_state_tempdir || return 1
  work=$REPLY
  managed=$work/managed.json
  links=$work/links.json
  _vscode_build_managed_extensions \
    "$ext_dir" "$opts" "$managed" \
    ${local_extensions[@]+"${local_extensions[@]}"} || {
    _dev_profile_state_tempdir_remove "$work" || true
    return 1
  }
  printf '[]\n' >"$links"
  if jq -e 'length == 0' "$managed" >/dev/null &&
    ! dev_profile_state_tracked \
      vscode-extensions json "$ext_dir/extensions.json"; then
    _dev_profile_state_tempdir_remove "$work"
    return 0
  fi
  dev_profile_state_begin \
    vscode-extensions json "$ext_dir/extensions.json" "$managed" || {
    _dev_profile_state_tempdir_remove "$work" || true
    return 1
  }

  for local_extension in ${local_extensions[@]+"${local_extensions[@]}"}; do
    IFS=$'\t' read -r ext_id ext_src disabled_opts <<<"$local_extension"
    _vscode_opts_intersect "$opts" "$disabled_opts" && continue
    [[ -d $ext_src ]] || continue
    ext_name=${ext_src##*/}
    mkdir -p "$ext_dir" || {
      status=1
      break
    }
    ext_link=$ext_dir/$ext_name
    legacy_ext_src=$HOME/.local/share/dot-vscode-extensions/$ext_name
    if [[ -L $ext_link && -e $ext_link ]] && ext_target=$(readlink "$ext_link"); then
      [[ $ext_target == /* ]] || ext_target=$ext_dir/$ext_target
      # Besides the legacy dotfiles-owned payload, respell a link that already
      # reaches the resolved source through another path (shdeps' managed
      # checkout link versus the development clone it points at) so the
      # ownership receipt below records it.
      if [[ $ext_target != "$ext_src" &&
        ($ext_target == "$legacy_ext_src" || $ext_target -ef $ext_src) ]]; then
        changed_paths+=("$ext_link")
        changed_kinds+=(symlink)
        old_targets+=("$(readlink "$ext_link")")
        new_targets+=("$ext_src")
        rm -f -- "$ext_link" || {
          status=1
          break
        }
        ln -s "$ext_src" "$ext_link" || {
          status=1
          break
        }
      fi
    elif [[ -L $ext_link && ! -e $ext_link ]]; then
      changed_paths+=("$ext_link")
      changed_kinds+=(symlink)
      old_targets+=("$(readlink "$ext_link")")
      new_targets+=("$ext_src")
      rm -f -- "$ext_link" || {
        status=1
        break
      }
      ln -s "$ext_src" "$ext_link" || {
        status=1
        break
      }
    elif [[ ! -e $ext_link && ! -L $ext_link ]]; then
      changed_paths+=("$ext_link")
      changed_kinds+=(absent)
      old_targets+=("")
      new_targets+=("$ext_src")
      ln -s "$ext_src" "$ext_link" || {
        status=1
        break
      }
    fi
    _ensure_vscode_extension \
      "$ext_id" "$ext_name" "$ext_dir/extensions.json" || {
      status=1
      break
    }
    if [[ -L $ext_link && $(readlink "$ext_link") == "$ext_src" ]]; then
      next_links=$work/links.next.json
      if ! jq --arg path "$ext_link" --arg target "$ext_src" \
        '. + [{path: $path, target: $target}]' "$links" >"$next_links" ||
        ! mv -f "$next_links" "$links"; then
        status=1
        break
      fi
    fi
  done

  if ((status == 0)) && _vscode_commit_tracked "$ext_dir/extensions.json" "$links"; then
    _dev_profile_state_tempdir_remove "$work"
    return 0
  fi
  dev_profile_state_abort || rollback_status=1
  for ((index = ${#changed_paths[@]} - 1; index >= 0; index--)); do
    ext_link=${changed_paths[index]}
    ext_target=${new_targets[index]}
    if [[ -L $ext_link && $(readlink "$ext_link") == "$ext_target" ]]; then
      rm -f -- "$ext_link" || {
        rollback_status=1
        continue
      }
    elif [[ -e $ext_link || -L $ext_link ]]; then
      rollback_status=1
      continue
    fi
    if [[ ${changed_kinds[index]} == symlink ]]; then
      ln -s "${old_targets[index]}" "$ext_link" || rollback_status=1
    fi
  done
  _dev_profile_state_tempdir_remove "$work" || true
  ((rollback_status == 0)) ||
    dot_hook_warn "    warning: VS Code extension rollback left recovery state"
  return 1
}

# Unchanged-update fast path.
#
# A converged merge still forks hundreds of short-lived jq, mktemp, cp, and
# Python processes to prove that nothing changed: about 2.3s on an idle Linux
# host and around 4s inside a loaded parallel update, which made this hook the
# tail of the Configs stage. After a fully successful merge the hook records a
# signature of everything that can change its result, and a later update with
# the same signature reports success without repeating the proof.
#
# Key: this hook, profile-state, compat, and Dot hook-runtime code; the
# platform, HOME, and host label; the resolved variant, remote, and local
# extension records; every settings, keybinding, variant, local-extension,
# and extension-manifest fragment; the Checkrun capability and schema
# projections; and the post-merge state of every destination (settings and
# keybindings files, extension directory entries, link targets, and
# registries, remote machine settings, the MCP token, local extension
# manifests, and the ownership receipts).
#
# Invalidation: any change to one of those inputs, a failed or partial merge
# (only full success records a signature), outstanding profile-state recovery,
# or `dot update -f` (DOT_FORCE=1) forces the full merge. Extension installs
# stay outside the skip because they reconcile the editor's own state.
#
# The signature file is a cache with no other authority: a missing,
# unreadable, or stale one is just a mismatch, and deleting it costs one full
# merge. The update lock is the only writer; publication is an atomic rename
# of a private sibling file.
_vscode_signature_file() {
  dot_xdg_path cache dot/merge-vscode-signature-v1
}

# Print a type-and-content line per path, following symlinks the way the merge
# reads them; a symlink also gets its own line so replacing a file with a link
# to identical bytes still changes the signature. Regular files are hashed as
# Git blobs by one process: per-file forks are what made the unchanged merge
# slow in the first place, and Git is already a profile-state prerequisite.
_vscode_signature_files() {
  local path id index=0
  local -a files=()
  for path in "$@"; do
    if [[ -L $path ]]; then
      printf 'link\t%s\n' "$path"
      [[ ! -f $path ]] || files+=("$path")
    elif [[ -f $path ]]; then
      files+=("$path")
    elif [[ -d $path ]]; then
      printf 'dir\t%s\n' "$path"
    elif [[ -e $path ]]; then
      printf 'other\t%s\n' "$path"
    else
      printf 'absent\t%s\n' "$path"
    fi
  done
  ((${#files[@]} > 0)) || return 0
  while IFS= read -r id; do
    ((index < ${#files[@]})) || return 1
    printf '%s\t%s\n' "$id" "${files[index]}"
    index=$((index + 1))
  done < <(git hash-object --no-filters -- "${files[@]}")
  ((index == ${#files[@]}))
}

# Print every entry of an extension directory with its type and any link
# target. Version pruning and link repair act on these entries, so a removed
# version directory or a dangling link must invalidate the signature; entry
# contents stay unhashed because large marketplace installs are not merge
# inputs.
_vscode_signature_entries() {
  local dir=$1 entry target
  if [[ ! -d $dir ]]; then
    printf 'absent\t%s\n' "$dir"
    return 0
  fi
  printf 'entries\t%s\n' "$dir"
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    if [[ -L $entry ]]; then
      target=$(readlink -- "$entry") || return 1
      if [[ -e $entry ]]; then
        printf 'link\t%s\t%s\n' "${entry##*/}" "$target"
      else
        printf 'dangling\t%s\t%s\n' "${entry##*/}" "$target"
      fi
    elif [[ -d $entry ]]; then
      printf 'dir\t%s\n' "${entry##*/}"
    elif [[ -e $entry ]]; then
      printf 'file\t%s\n' "${entry##*/}"
    fi
  done
}

# Print the inputs that stay fixed while a merge runs. Callers pass the lists
# merge() already resolved, as `variants`, `config_variants`, and
# `local_extensions` arrays in the caller's scope.
_vscode_signature_inputs() {
  local file family_root record
  local -a code=() sources=()

  printf 'version\t%s\n' vscode-merge-signature-v1
  printf 'home\t%s\n' "$HOME"
  printf 'platform\t%s\n' "$(_vscode_platform)"
  printf 'host\t%s\n' "$(_vscode_host_label)"

  code+=("$_dot_vscode_hook_source")
  dot_hook_file merge-hooks.d/lib/profile-state.sh && code+=("$REPLY")
  dot_hook_file merge-hooks.d/lib/compat.sh && code+=("$REPLY")
  _dev_profile_state_engine_path && code+=("$REPLY")
  if [[ -n ${DOT_SOURCE_ROOT:-} ]]; then
    code+=("$DOT_SOURCE_ROOT"/lib/dot/public/*.sh)
    code+=("$DOT_SOURCE_ROOT"/lib/dot/public/hook-runtime-v1/*.sh)
  fi
  _vscode_signature_files "${code[@]}" || return 1

  for record in ${variants[@]+"${variants[@]}"}; do
    printf 'variant\t%s\n' "$record"
  done
  while IFS= read -r record; do
    printf 'remote\t%s\n' "$record"
  done < <(_vscode_remote_settings_dirs)
  for record in ${local_extensions[@]+"${local_extensions[@]}"}; do
    printf 'local-extension\t%s\n' "$record"
  done

  # Hash every file in the VS Code family tree (settings, keybindings,
  # variants, local extensions, and extension manifests) instead of replaying
  # each family's ordered resolution. The tree is a superset of what the merge
  # selects, so this can only over-invalidate, and it keeps source resolution
  # to once per merge. Interpreter caches are not policy.
  family_root=$(dot_hook_family vscode) || return 1
  if [[ -d $family_root ]]; then
    while IFS= read -r file; do
      sources+=("$file")
    done < <(find -L "$family_root" -name __pycache__ -prune -o -type f -print |
      LC_ALL=C sort)
  fi
  printf 'sources\t%s\n' "$family_root"
  _vscode_signature_files ${sources[@]+"${sources[@]}"} || return 1

  # Only config-bearing variants consume the Checkrun projections. Hash the
  # public CLI outputs rather than Checkrun internals so the signature follows
  # the same boundary the merge consumes; the memo lets the merge reuse them.
  if ((${#config_variants[@]} > 0)) && command -v checkrun >/dev/null 2>&1; then
    _vscode_checkrun_projection capabilities || return 1
    file=$REPLY
    _vscode_checkrun_projection schemas || return 1
    # Content only: the memo lives in a per-merge temporary directory.
    record=$(git hash-object --no-filters -- "$file" "$REPLY") || return 1
    printf 'checkrun\t%s\n' "${record//$'\n'/ }"
  fi
}

# Print the destination and ownership state that a merge reads and writes.
# Evaluated before the merge to test the fast path and after a successful
# merge to record the converged state. Uses the caller's `config_variants`,
# `extension_variants`, `local_extensions`, and `_vscode_committed_sums`.
#
# A destination the merge committed is recorded by the blob id of the bytes
# its transaction committed, not by re-reading it afterwards: a concurrent
# writer (Settings Sync, the editor itself) can replace a file between its
# commit and this scan, and that newer content must not be certified as
# converged. A symlinked destination, which transactions refuse, never matches.
_vscode_signature_state() {
  local line rest ext_dir cfg_dir local_extension ext_id ext_src disabled_opts
  local destination path
  local -a destinations=() files=() receipts=()

  while IFS= read -r cfg_dir; do
    destinations+=("$cfg_dir/settings.json")
    receipts+=("vscode-settings"$'\t'"$cfg_dir/settings.json")
  done < <(_vscode_remote_settings_dirs)
  for line in ${extension_variants[@]+"${extension_variants[@]}"}; do
    ext_dir=${line%%	*}
    destinations+=("$ext_dir/extensions.json")
    receipts+=("vscode-extensions"$'\t'"$ext_dir/extensions.json")
    _vscode_signature_entries "$ext_dir" || return 1
  done
  for line in ${config_variants[@]+"${config_variants[@]}"}; do
    rest=${line#*	}
    cfg_dir=${rest%%	*}
    [[ -n $cfg_dir ]] || continue
    destinations+=("$cfg_dir/settings.json" "$cfg_dir/keybindings.json")
    receipts+=("vscode-settings"$'\t'"$cfg_dir/settings.json")
    receipts+=("vscode-keybindings"$'\t'"$cfg_dir/keybindings.json")
  done
  for destination in ${destinations[@]+"${destinations[@]}"}; do
    [[ ! -L $destination ]] || return 1
  done

  while IFS= read -r line; do
    if [[ $line =~ ^[0-9a-f]{40,64}$'\t'(.*)$ ]]; then
      path=${BASH_REMATCH[1]}
      if [[ -n ${_vscode_committed_sums[$path]+x} ]]; then
        printf '%s\t%s\n' "${_vscode_committed_sums[$path]}" "$path"
        continue
      fi
    fi
    printf '%s\n' "$line"
  done < <(_vscode_signature_files ${destinations[@]+"${destinations[@]}"} ||
    printf 'unreadable\n')

  # Local extension sources gate activation by directory presence and supply
  # the registered version through their manifest.
  for local_extension in ${local_extensions[@]+"${local_extensions[@]}"}; do
    IFS=$'\t' read -r ext_id ext_src disabled_opts <<<"$local_extension"
    files+=("$ext_src" "$ext_src/package.json")
  done
  _vscode_mcp_auth_token_path && files+=("$REPLY")
  _vscode_signature_files ${files[@]+"${files[@]}"} || return 1
  dev_profile_state_fingerprint ${receipts[@]+"${receipts[@]}"} || return 1
}

# Succeed unless some destination receives the MCP auth setting while the token
# is unusable. Token generation failure is deliberately a warning, not a merge
# failure, so recording that degraded result would stop later updates from
# retrying generation.
_vscode_signature_mcp_ready() {
  local line rest cfg_dir
  local -a destinations=()
  while IFS= read -r cfg_dir; do
    destinations+=("$cfg_dir/settings.json")
  done < <(_vscode_remote_settings_dirs)
  for line in ${config_variants[@]+"${config_variants[@]}"}; do
    rest=${line#*	}
    cfg_dir=${rest%%	*}
    [[ -z $cfg_dir ]] || destinations+=("$cfg_dir/settings.json")
  done
  for line in ${destinations[@]+"${destinations[@]}"}; do
    _vscode_mcp_auth_applicable "$line" || continue
    _vscode_mcp_auth_token_path || return 1
    _vscode_mcp_auth_token_is_valid "$REPLY"
    return
  done
}

# Record the converged signature after a fully successful merge. Reads
# merge()'s `signature_file` and `signature_inputs`; an input or state probe
# that cannot be evaluated removes any previous signature so the next update
# repeats the full merge. Failing to record is harmless and stays silent.
_vscode_write_signature() {
  local state tmp
  [[ -n $signature_file ]] || return 0
  if [[ -z $signature_inputs ]] || ! _vscode_signature_mcp_ready ||
    ! state=$(_vscode_signature_state) ||
    [[ $'\n'$state$'\n' == *$'\n'unreadable$'\n'* ]]; then
    rm -f -- "$signature_file" 2>/dev/null || true
    return 0
  fi
  mkdir -p "${signature_file%/*}" 2>/dev/null || return 0
  dot_sibling_tmp_for "$signature_file" || return 0
  tmp=$REPLY
  if (umask 077 && printf '%s\n%s\n' "$signature_inputs" "$state" >"$tmp") &&
    mv -f -- "$tmp" "$signature_file"; then
    return 0
  fi
  rm -f -- "$tmp" 2>/dev/null || true
}

# Succeed when any VS Code variant this hook configures is installed: a
# desktop or Windows-side CLI, a remote server directory, or a macOS app
# bundle. The variant list belongs here beside the per-variant config paths,
# not in base compat.sh, which only supplies the literal probes and platform.
_vscode_present() {
  local platform

  _dot_tool_any_command \
    code code-insiders code-fb code-fb-insiders cursor codium codium-insiders \
    code.exe code-insiders.exe cursor.exe codium.exe \
    codium-insiders.exe && return 0
  _dot_tool_any_path \
    "$HOME/.vscode-server" "$HOME/.vscode-server-insiders" \
    "$HOME/.vscode-remote" "$HOME/.cursor-server" && return 0
  platform=$(_dot_tool_platform)
  [[ $platform == Darwin ]] || return 1
  _dot_tool_any_path \
    '/Applications/Visual Studio Code.app' \
    "$HOME/Applications/Visual Studio Code.app" \
    '/Applications/Visual Studio Code - Insiders.app' \
    "$HOME/Applications/Visual Studio Code - Insiders.app" \
    '/Applications/VS Code @ FB.app' \
    "$HOME/Applications/VS Code @ FB.app" \
    '/Applications/VS Code @ FB - Insiders.app' \
    "$HOME/Applications/VS Code @ FB - Insiders.app" \
    /Applications/Cursor.app "$HOME/Applications/Cursor.app" \
    /Applications/VSCodium.app "$HOME/Applications/VSCodium.app"
}

# Main: deploy extensions, settings, and keybindings to all VS Code variants.
merge() {
  _vscode_present || return 0

  # Scope the Checkrun projection memo to this one merge; dynamic scoping
  # exposes it to every helper below, and it disappears on return.
  local _vscode_checkrun_memo="" rc=0
  local -A _vscode_committed_sums=()
  # Ask profile-state commits to report the bytes they committed.
  # shellcheck disable=SC2034 # Read by dev_profile_state_commit via scope.
  local DEV_PROFILE_STATE_RECORD_COMMITTED_SUM=1
  _dev_profile_state_tempdir && _vscode_checkrun_memo=$REPLY
  _vscode_merge || rc=$?
  if [[ -n $_vscode_checkrun_memo ]]; then
    _dev_profile_state_tempdir_remove "$_vscode_checkrun_memo" || true
  fi
  return "$rc"
}

_vscode_merge() {
  _vscode_install_declared_extensions || return $?

  command -v jq &>/dev/null || return 0

  local -a variants=()
  local -a extension_variants=()
  local -a config_variants=()
  local -a local_extensions=()
  local line
  while IFS= read -r line; do
    variants+=("$line")
  done < <(_vscode_variants)

  # Configuration and extension reconciliation have different identities.
  # Build each list once so shared targets are processed only when their
  # effective policy differs. The signature needs the same lists, so resolve
  # them before the remote merge rather than twice.
  if ((${#variants[@]} > 0)); then
    while IFS= read -r line; do
      config_variants+=("$line")
    done < <(_vscode_config_variants "${variants[@]}")

    while IFS= read -r line; do
      extension_variants+=("$line")
    done < <(_vscode_extension_variants "${variants[@]}")

    while IFS= read -r line; do
      local_extensions+=("$line")
    done < <(_vscode_local_extensions)
  fi

  local signature_file="" signature_inputs="" signature_state=""
  if _vscode_signature_file; then
    signature_file=$REPLY
    signature_inputs=$(_vscode_signature_inputs) || signature_inputs=""
  fi
  if [[ -n $signature_inputs && ${DOT_FORCE:-0} != 1 && -f $signature_file ]] &&
    signature_state=$(_vscode_signature_state) &&
    [[ "$(cat -- "$signature_file" 2>/dev/null)" == "$signature_inputs"$'\n'"$signature_state" ]]; then
    ((${#variants[@]} > 0)) && dot_hook_log "  VS Code"
    return 0
  fi

  _merge_vscode_remote_configs_tracked || return 1

  if ((${#variants[@]} == 0)); then
    _vscode_write_signature
    return 0
  fi

  local ext_dir cfg_dir opts rest merge_rc=0
  for line in ${extension_variants[@]+"${extension_variants[@]}"}; do
    _vscode_merge_extensions_tracked \
      "$line" -- \
      ${local_extensions[@]+"${local_extensions[@]}"} || merge_rc=1
  done

  # Merge settings and keybindings. Config destinations are independent, so
  # keep processing after one fails. Preserve the aggregate failure explicitly:
  # the hook runner deliberately invokes merge in a context where Bash errexit
  # is not a reliable error boundary, and a later successful destination must
  # not make a partial deployment look healthy.
  dot_hook_log "  VS Code"
  for line in ${config_variants[@]+"${config_variants[@]}"}; do
    rest="${line#*	}"
    cfg_dir="${rest%%	*}"
    opts="${rest#*	}"
    [[ "$opts" == "$cfg_dir" ]] && opts=""
    if [[ -n "$cfg_dir" ]]; then
      _merge_vscode_config_tracked "$cfg_dir" "$opts" || merge_rc=1
    fi
  done
  ((merge_rc != 0)) || _vscode_write_signature
  return "$merge_rc"
}
