# shellcheck shell=bash
# AgentGuard integration helpers for the dev overlay.
#
# AgentGuard is a dev-profile dependency, so its adapter lives here rather than
# in the base repository. Callers must load base `merge-hooks.d/lib/compat.sh`
# first: these helpers resolve assets through its `dot_shdeps_dep_file` and
# compare outputs with its `dot_config_files_equal`. The file only defines
# functions, so doctor checks and `dot/profile-deactivate` can source it too.

# Resolve one of AgentGuard's native agent-integration assets.
#
# Keep the repository and provider layout behind this single boundary. Merge
# hooks should know only which runtime they activate and which native file type
# that runtime consumes; AgentGuard owns the event vocabulary, matchers,
# commands, and adapter implementation under the resolved directory. Besides
# keeping dotfiles thin, this makes normal shdeps rules (development-clone
# precedence, install roots, filters, and fleet updates) apply uniformly to
# every supported agent.
#
# Args: $1 = agent directory name, $2 = asset filename
# Prints: resolved dependency path on stdout
dot_agentguard_integration_file() {
  local agent="$1" asset="$2"
  dot_shdeps_dep_file \
    cgraf78/agentguard \
    "share/agentguard/integrations/$agent/$asset"
}

# Print the provider-owned first-line marker for AgentGuard's OpenCode adapter.
# The installer, doctor, and deactivation hook share this cross-repository
# identity rather than duplicating its literal at each consumer boundary.
dot_agentguard_opencode_marker() {
  printf '%s\n' '// agentguard-managed:opencode-plugin'
}

# Reconcile AgentGuard's provider-owned JSON hooks fragment into one agent
# config, preserving every non-AgentGuard entry already present.
#
# A missing or unparsable destination is rebuilt from the fragment alone.
#
# Args: $1 = display label, $2 = agent directory name, $3 = destination file
# Returns: 0 when the destination is current (already or after publishing);
#   1 when the provider fragment is unavailable or invalid, reconciliation
#   fails, or publication fails. Provider and reconciliation failures warn and
#   leave the destination untouched.
_merge_hook_agentguard_json_layer() {
  local label=$1 agent=$2 destination=$3
  local source='' reconciler='' live=/dev/null temporary=''

  source=$(dot_agentguard_integration_file "$agent" hooks.json 2>/dev/null) || source=''
  reconciler=$(dot_agentguard_integration_file _shared reconcile-hooks.jq 2>/dev/null) ||
    reconciler=''
  if [[ ! -r $source || ! -r $reconciler ]]; then
    dot_hook_warn "    warning: AgentGuard $agent integration unavailable — preserving $destination"
    return 1
  fi
  if ! jq empty "$source" 2>/dev/null; then
    dot_hook_warn "    warning: invalid AgentGuard $agent integration — preserving $destination"
    return 1
  fi
  if [[ (-e $destination || -L $destination) && -s $destination ]] &&
    jq empty "$destination" 2>/dev/null; then
    live=$destination
  elif [[ -e $destination || -L $destination ]]; then
    dot_hook_warn "    warning: corrupt $destination — rebuilding"
  fi

  mkdir -p "${destination%/*}"
  dot_sibling_tmp_for "$destination" || return 1
  temporary=$REPLY
  if ! jq -n --sort-keys --indent 2 \
    --arg agent "$agent" \
    --slurpfile d "$live" \
    --slurpfile s "$source" \
    -f "$reconciler" >"$temporary" ||
    [[ ! -s $temporary ]] || ! jq empty "$temporary" 2>/dev/null; then
    dot_hook_warn "    warning: AgentGuard $label reconciliation failed — preserving $destination"
    rm -f "$temporary"
    return 1
  fi
  if [[ ! -L $destination ]] &&
    dot_config_files_equal "$temporary" "$destination"; then
    rm -f "$temporary"
    return 0
  fi
  dot_commit_tmp "$temporary" "$destination" || {
    rm -f "$temporary"
    return 1
  }
}
