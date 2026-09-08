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
# skills and mcps apply whenever the layer names them. This overlay names
# mcps=false and leaves skills unset so Claude skills stay on. The grok CLI
# gate is `_dot_tool_present grok` from base compat.sh.

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

# Drop Claude-compat keys whose native Grok replacement is not installed yet.
# skills/mcps apply whenever the layer names them. Other top-level tables
# survive even if every gated compat.claude cell is stripped. Prints JSON, or
# nothing when the filtered layer is {}.
_grok_config_ready_layer_json() {
  local src=$1 yq_bin=$2
  local hooks_ready=false rules_ready=false

  _grok_config_native_hooks && hooks_ready=true
  _grok_config_native_rules && rules_ready=true
  "$yq_bin" eval --input-format toml --output-format json '.' "$src" |
    jq -c --argjson hooks "$hooks_ready" --argjson rules "$rules_ready" '
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
      if . == {} then empty else . end
    '
}

# Merge one TOML layer into the live Grok config. Source wins on overlapping
# keys; nested tables merge recursively so unnamed [compat.claude] cells and
# unrelated root tables survive.
_merge_grok_config_layer() {
  local src=$1 dst=$2
  local yq_bin renderer dst_json src_json merged_json temporary layer_json

  yq_bin=$(_merge_hook_mikefarah_yq) || return 1
  renderer=$(_grok_config_toml_renderer) || return 1
  layer_json=$(_grok_config_ready_layer_json "$src" "$yq_bin") || return 1
  [[ -n $layer_json ]] || return 0

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
  elif [[ -e $dst || -L $dst ]]; then
    # config.toml holds user UI and marketplace state. A parse failure must
    # not rebuild from the policy layer alone.
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
  _dot_tool_present grok || return 0

  local dst="$HOME/.grok/config.toml"
  local src
  local -a src_files=()

  while IFS= read -r src; do
    src_files+=("$src")
  done < <(dot_hook_family_files_matching grok-config/config.d \
    '*.toml' '*.replace/*.toml')
  [[ ${#src_files[@]} -gt 0 ]] || return 0

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
  for src in "${src_files[@]}"; do
    _merge_grok_config_layer "$src" "$dst" || return 1
  done
}
