# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Install AgentGuard's provider-owned Grok hooks fragment.
# Runs during standalone Dot client convergence.
# Requires jq.
#
# Grok loads every ~/.grok/hooks/*.json file itself. Keep AgentGuard's
# generation in a dedicated fragment so user-owned sibling JSON files and
# ~/.grok/config.toml stay outside this hook. AgentGuard's reconciler owns
# add/remove of provider hooks in that fragment; this overlay does not merge
# Grok settings layers.

merge() {
  _dot_tool_present grok || return 0
  dot_json_available || return 0

  local dst="$HOME/.grok/hooks/agentguard.json"

  dot_hook_log "  Grok"
  # A missing or invalid provider asset is a failed refresh, not a request to
  # disable protection. The helper leaves the last destination in place.
  _merge_hook_agentguard_json_layer "Grok hooks" grok "$dst"
}
