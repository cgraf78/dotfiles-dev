# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge overlay Grok config policy into ~/.grok/config.toml.
# Runs during standalone Dot client convergence.
# Requires mikefarah/yq, jq, and python3.
#
# Layers come from grok-config/config.d. Direct files aggregate in lexical
# order; each immediate *.replace directory contributes only its last lexical
# file, so overlays can express environment-specific overrides without this
# hook knowing those environment names.
#
# This hook does not write ~/.grok/hooks/; AgentGuard's Grok fragment is a
# separate merge. It writes named [compat.claude] cells plus any other
# overlay-owned tables in the same layer so user-owned keys stay in place.
#
# hooks still wait on ~/.grok/hooks/agentguard.json, and rules/agents wait on
# ~/.grok/rules/agent-rules.md, so an out-of-order land cannot strip
# Claude-compat AgentGuard or home rules with nothing to take their place.
# skills and mcps apply whenever the layer names them. This overlay leaves
# both unset so Claude skills and MCP config stay on. The grok CLI gate is
# `_dot_tool_any_command grok`.
#
# Layers in grok-config/sandbox.d merge the same way into ~/.grok/sandbox.toml
# (custom sandbox profiles) and run first. A config layer's sandbox.profile
# applies only once a built-in name or a profile sandbox.toml defines: Grok
# refuses to start under an undefined profile. Until then built-in
# workspace is selected.

# Shared TOML serializer used by Codex and profile-state. Keep Grok on that
# writer so array-of-tables round-trip instead of using yq's TOML emitter,
# which can reattach root scalars to the wrong table.
_grok_config_toml_renderer() {
  dot_hook_file merge-hooks.d/lib/codex/toml-render.py || return 1
  printf '%s\n' "$REPLY"
}

_grok_config_native_hooks() {
  local path="$HOME/.grok/hooks/agentguard.json"
  [[ -f $path && ! -L $path ]]
}

_grok_config_native_rules() {
  local path="$HOME/.grok/rules/agent-rules.md"
  [[ -f $path && ! -L $path ]]
}

# Sandbox profile names Grok accepts in config.toml: its built-ins plus every
# [profiles.*] table in ~/.grok/sandbox.toml, as a JSON array. A missing,
# empty, or unparsable sandbox.toml contributes only the built-ins.
_grok_config_sandbox_profiles() {
  local yq_bin=$1 sandbox="$HOME/.grok/sandbox.toml" defined='[]'

  # Only table-valued entries are profiles. Filter in jq: yq's `type` reports
  # YAML tags (`!!map`), not JSON type names.
  if [[ -s $sandbox ]]; then
    defined=$("$yq_bin" eval --input-format toml --output-format json \
      '.profiles // {}' "$sandbox" 2>/dev/null |
      jq -c 'if type == "object"
        then to_entries | map(select(.value | type == "object") | .key)
        else []
        end' 2>/dev/null) || defined='[]'
  fi
  jq -cn --argjson defined "${defined:-[]}" \
    '["off", "workspace", "devbox", "read-only", "strict"] + $defined'
}

# Drop Claude-compat keys whose native Grok replacement is not installed yet.
# A sandbox.profile Grok could not resolve becomes built-in workspace, the
# profile this layer forced before custom profiles existed. Deleting it would
# leave a fresh config on Grok's unsandboxed default, and keeping the current
# value could keep `off` or a profile that is itself undefined (Grok then
# refuses to start). skills/mcps apply whenever the
# layer names them. Other top-level tables survive even if every gated cell
# is stripped. Prints JSON, or nothing when the filtered layer is {}.
_grok_config_ready_layer_json() {
  local src=$1 yq_bin=$2
  local hooks_ready=false rules_ready=false profiles

  _grok_config_native_hooks && hooks_ready=true
  _grok_config_native_rules && rules_ready=true
  profiles=$(_grok_config_sandbox_profiles "$yq_bin") || return 1
  "$yq_bin" eval --input-format toml --output-format json '.' "$src" |
    jq -c --argjson hooks "$hooks_ready" --argjson rules "$rules_ready" \
      --argjson profiles "$profiles" '
      def take($obj; $key):
        if ($obj | type) == "object" and ($obj | has($key))
        then {($key): $obj[$key]}
        else {}
        end;
      (.compat.claude // null) as $c |
      if ($c | type) != "object" then
        .
      else
        .compat.claude = (
          {}
          + take($c; "skills")
          + take($c; "mcps")
          + (if $hooks then take($c; "hooks") else {} end)
          + (if $rules then take($c; "rules") + take($c; "agents") else {} end)
        )
      end |
      if (.compat.claude? | type) == "object" and
        (.compat.claude | length) == 0
      then del(.compat.claude)
      else .
      end |
      if (.compat? | type) == "object" and (.compat | length) == 0
      then del(.compat)
      else .
      end |
      if (.sandbox | type) == "object" and
        (.sandbox.profile | type) == "string" and
        (.sandbox.profile | IN($profiles[]) | not)
      then .sandbox.profile = "workspace"
      else .
      end |
      if . == {} then empty else . end
    '
}

# String grants under the named keys of every [profiles.*] table, one per
# line. Captured whole so a jq failure fails the caller instead of ending a
# read loop early and leaving a `~` grant unexpanded.
_grok_sandbox_grants() {
  local layer_json=$1
  shift
  jq -r --args '
    $ARGS.positional as $keys |
    .profiles // {} | if type == "object" then .[] else empty end |
    objects | .[$keys[]] | arrays | .[] | strings
  ' "$@" <<<"$layer_json"
}

# Sandbox layer as JSON with `~`/$HOME grants made absolute. Grok resolves
# read_only/read_write as literal directories and skips a `~` entry without
# warning, so the expansion must happen here.
_grok_sandbox_layer_json() {
  local src=$1 yq_bin=$2
  local layer grants grant expanded map='{}'

  layer=$("$yq_bin" eval --input-format toml --output-format json '.' "$src") ||
    return 1
  grants=$(_grok_sandbox_grants "$layer" read_only read_write) || return 1
  while IFS= read -r grant; do
    [[ -n $grant ]] || continue
    expanded=$(dot_expand_home "$grant") || return 1
    map=$(jq -c --arg k "$grant" --arg v "$expanded" '. + {($k): $v}' \
      <<<"$map") || return 1
  done <<<"$grants"
  jq -c --argjson map "$map" '
    if (.profiles? | type) == "object" then
      .profiles |= map_values(
        if type == "object" then
          reduce ("read_only", "read_write") as $k (.;
            if (.[$k] | type) == "array"
            then .[$k] |= map(if type == "string" then ($map[.] // .) else . end)
            else .
            end)
        else .
        end)
    else .
    end |
    if . == {} or . == null then empty else . end
  ' <<<"$layer"
}

# Create missing read_write grants privately before Grok sees them. Grok
# creates a missing grant itself, but 0755; AgentGuard's state is 0700.
# Only the grant itself is private: missing parents such as ~/.local/state
# get the normal umask, like any other tool would create them. Existing
# directories keep their mode.
_grok_sandbox_make_grants() {
  local layer_json=$1 grants grant

  grants=$(_grok_sandbox_grants "$layer_json" read_write) || return 1
  while IFS= read -r grant; do
    grant=${grant%/}
    [[ $grant == /?* && ! -e $grant ]] || continue
    mkdir -p "${grant%/*}/" && (umask 077 && mkdir "$grant") || return 1
  done <<<"$grants"
}

# Merge one config.d layer into ~/.grok/config.toml.
_merge_grok_config_layer() {
  local src=$1 dst=$2 yq_bin layer_json

  yq_bin=$(_merge_hook_mikefarah_yq) || return 1
  layer_json=$(_grok_config_ready_layer_json "$src" "$yq_bin") || return 1
  [[ -n $layer_json ]] || return 0
  _merge_grok_toml_json "$layer_json" "$dst"
}

# Merge one sandbox.d layer into ~/.grok/sandbox.toml.
_merge_grok_sandbox_layer() {
  local src=$1 dst=$2 yq_bin layer_json

  yq_bin=$(_merge_hook_mikefarah_yq) || return 1
  layer_json=$(_grok_sandbox_layer_json "$src" "$yq_bin") || return 1
  [[ -n $layer_json ]] || return 0
  _grok_sandbox_make_grants "$layer_json" || {
    dot_hook_warn "    warning: could not create a Grok sandbox grant; preserving $dst"
    return 1
  }
  _merge_grok_toml_json "$layer_json" "$dst"
}

# Merge a JSON layer into a Grok TOML file. Source wins on overlapping keys;
# nested tables merge recursively so unnamed cells, user profiles, and
# unrelated root tables survive.
_merge_grok_toml_json() {
  local layer_json=$1 dst=$2
  local yq_bin renderer dst_json src_json merged_json temporary

  yq_bin=$(_merge_hook_mikefarah_yq) || return 1
  renderer=$(_grok_config_toml_renderer) || return 1

  dst_json=$(mktemp) || return 1
  src_json=$(mktemp) || {
    rm -f "$dst_json"
    return 1
  }
  merged_json=$(mktemp) || {
    rm -f "$dst_json" "$src_json"
    return 1
  }

  if [[ -s $dst ]] &&
    "$yq_bin" eval --input-format toml '.' "$dst" >/dev/null 2>&1; then
    if ! "$yq_bin" eval --input-format toml --output-format json '.' \
      "$dst" >"$dst_json"; then
      dot_hook_warn "    warning: Grok config conversion failed; preserving $dst"
      rm -f "$dst_json" "$src_json" "$merged_json"
      return 1
    fi
  elif [[ -L $dst ]]; then
    dot_hook_warn "    warning: $dst is a symlink — preserving"
    rm -f "$dst_json" "$src_json" "$merged_json"
    return 1
  elif [[ -f $dst && ! -s $dst ]]; then
    # An empty file is an empty TOML document; Grok creates sandbox.toml
    # that way on first launch.
    printf '{}\n' >"$dst_json"
  elif [[ -e $dst || -L $dst ]]; then
    # config.toml holds user UI and marketplace state, and sandbox.toml user
    # profiles. A parse failure must not rebuild from the policy layer alone.
    dot_hook_warn "    warning: corrupt $dst — preserving"
    rm -f "$dst_json" "$src_json" "$merged_json"
    return 1
  else
    printf '{}\n' >"$dst_json"
  fi

  printf '%s\n' "$layer_json" >"$src_json"
  if ! jq -n --sort-keys --indent 2 \
    --slurpfile d "$dst_json" \
    --slurpfile s "$src_json" \
    '$d[0] * $s[0]' >"$merged_json" ||
    [[ ! -s $merged_json ]] || ! jq empty "$merged_json" 2>/dev/null; then
    dot_hook_warn "    warning: Grok config merge failed; preserving $dst"
    rm -f "$dst_json" "$src_json" "$merged_json"
    return 1
  fi

  mkdir -p "${dst%/*}"
  if [[ -L $dst ]]; then
    dot_hook_warn "    warning: $dst is a symlink — preserving"
    rm -f "$dst_json" "$src_json" "$merged_json"
    return 1
  fi
  dot_sibling_tmp_for "$dst" || {
    rm -f "$dst_json" "$src_json" "$merged_json"
    return 1
  }
  temporary=$REPLY
  if ! python3 "$renderer" render-json "$merged_json" >"$temporary" ||
    [[ ! -s $temporary ]]; then
    dot_hook_warn "    warning: Grok config render failed; preserving $dst"
    rm -f "$dst_json" "$src_json" "$merged_json" "$temporary"
    return 1
  fi
  rm -f "$dst_json" "$src_json" "$merged_json"
  if cmp -s "$temporary" "$dst" 2>/dev/null; then
    rm -f "$temporary"
    return 0
  fi
  dot_commit_tmp "$temporary" "$dst" || {
    rm -f "$temporary"
    return 1
  }
}

merge() {
  _dot_tool_any_command grok || return 0

  local dst="$HOME/.grok/config.toml"
  local sandbox_dst="$HOME/.grok/sandbox.toml"
  local src
  local -a src_files=() sandbox_files=()

  while IFS= read -r src; do
    src_files+=("$src")
  done < <(dot_hook_family_files_matching grok-config/config.d \
    '*.toml' '*.replace/*.toml')
  while IFS= read -r src; do
    sandbox_files+=("$src")
  done < <(dot_hook_family_files_matching grok-config/sandbox.d \
    '*.toml' '*.replace/*.toml')
  [[ ${#src_files[@]} -gt 0 || ${#sandbox_files[@]} -gt 0 ]] || return 0

  _merge_hook_mikefarah_yq >/dev/null || {
    dot_hook_warn "    warning: mikefarah/yq not found; skipping Grok config merge"
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    dot_hook_warn "    warning: jq not found; skipping Grok config merge"
    return 1
  }
  command -v python3 >/dev/null 2>&1 || {
    dot_hook_warn "    warning: python3 not found; skipping Grok config merge"
    return 1
  }
  _grok_config_toml_renderer >/dev/null || {
    dot_hook_warn "    warning: Grok config TOML renderer unavailable; skipping"
    return 1
  }

  dot_hook_log "  Grok config"
  # Profiles first, so config.d can select one in the same run. A failure
  # still refreshes config.toml: its profile gate selects built-in workspace
  # unless sandbox.toml already defines the profile.
  local sandbox_status=0
  for src in ${sandbox_files[@]+"${sandbox_files[@]}"}; do
    _merge_grok_sandbox_layer "$src" "$sandbox_dst" || {
      sandbox_status=1
      break
    }
  done
  for src in ${src_files[@]+"${src_files[@]}"}; do
    _merge_grok_config_layer "$src" "$dst" || return 1
  done
  return "$sandbox_status"
}
