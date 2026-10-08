# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Initialize Hive Memory store state and verify managed config still loads.
#
# Dotfiles owns bootstrap and the static guidance selected from
# ~/.config/agent-rules/rules.d; the standalone agent-rules-sync provider owns
# publishing that selection. `hm hook` separately owns dynamic, project-aware
# memory context. Do not install generated include markers into agent rule
# targets: adapter-specific include blocks would make the shared generated body
# noisy and ambiguous. Hooks are the runtime context path.

_hive_memory_config() {
  # Match Hive's public config precedence. An explicitly set override keeps its
  # existing semantics, including an empty or relative value; only XDG base
  # directories require an absolute path.
  if [[ "${HIVE_MEMORY_CONFIG+x}" == x ]]; then
    REPLY="$HIVE_MEMORY_CONFIG"
  else
    dot_xdg_path config "hive-memory/config.toml" || return
  fi
}

_hive_memory_warn() {
  dot_hook_warn "    warning: Hive Memory $1"
}

# The real hm that Shdeps installs, through REPLY. The tracked launcher
# resolves the same dependency file, so both share one installation contract.
_hive_memory_core_path() {
  # The resolver reads HOME-relative shdeps config; without HOME (an absolute
  # XDG config under nounset) there is no installation to find.
  [[ -n "${HOME:-}" ]] || return 1
  REPLY=$(dot_shdeps_dep_file cgraf78/hive-memory hm 2>/dev/null) || return 1
  [[ -n "$REPLY" ]]
}

# Succeed when the real hm is installed, by the launcher's own test.
_hive_memory_core_installed() {
  _hive_memory_core_path || return 1
  [[ -x "$REPLY" && ! -d "$REPLY" ]]
}

# Print the effective default store as one field per line. Returns 127 when
# hm itself exits 127 and 1 for any other hm failure (even with a parsable
# report, as Dot's pipefail worker always treated it) or a parse failure.
_hive_memory_effective_store_spec() {
  local config="$1" json rc

  json=$(hm --config "$config" stores show --json) || {
    rc=$?
    ((rc == 127)) && return 127
    return 1
  }
  printf '%s\n' "$json" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
store_name = data.get("name", "")
store = data.get("config", {})
root = store.get("root", "")

if not store_name or not root:
    raise SystemExit(1)

print(
    "\n".join(
        [
            store_name,
            root,
            store.get("description") or "",
            store.get("sensitivity") or "",
            "true" if data.get("available", False) else "false",
            "__DOT_HIVE_MEMORY_SPEC_END__",
        ]
    )
)
' || return 1
}

_hive_memory_cloud_root_for() {
  local root="$1" gdrive

  # Cloud-root policy is HOME-relative. An absolute XDG config remains usable
  # without HOME, but there is no personal cloud root to classify in that
  # environment.
  [[ -n "${HOME:-}" ]] || return 1
  gdrive="$HOME/gdrive"

  case "$root" in
    "$gdrive" | "$gdrive"/*)
      printf '%s\n' "$gdrive"
      return 0
      ;;
  esac

  return 1
}

# Initialize the default store from SPEC, the effective store spec, which was
# read with status SPEC_RC.
_hive_memory_init_default_store() {
  local config="$1" spec_rc="$2" spec="$3"
  local store root description sensitivity available line
  local -a fields=()

  if ((spec_rc != 0)); then
    _hive_memory_warn "effective config unavailable"
    return 0
  fi

  # Preserve intentionally empty optional fields. Bash's whitespace splitting
  # would collapse a missing description and shift sensitivity into the wrong
  # flag, so the Python side emits one field per line plus a sentinel that keeps
  # command substitution from trimming meaningful trailing empties.
  while IFS= read -r line; do
    [[ "$line" == "__DOT_HIVE_MEMORY_SPEC_END__" ]] && break
    fields+=("$line")
  done <<<"$spec"

  store="${fields[0]:-}"
  root="${fields[1]:-}"
  description="${fields[2]:-}"
  sensitivity="${fields[3]:-}"
  available="${fields[4]:-}"
  [[ -n "$store" && -n "$root" ]] || return 0

  [[ "$available" == true ]] && return 0

  # Do not create a cloud-drive mount itself. Configs under ~/gdrive are personal
  # overlay policy; if that sync root is absent, warn and leave recovery to the
  # user. Non-cloud roots can be initialized normally so future base or overlay
  # configs are not forced into the same storage shape.
  local cloud_root
  if cloud_root=$(_hive_memory_cloud_root_for "$root") && [[ ! -d "$cloud_root" ]]; then
    _hive_memory_warn "cloud root not available: $cloud_root"
    return 0
  fi

  local -a init_args=(--config "$config" stores init "$store" --root "$root")
  [[ -n "$description" ]] && init_args+=(--description "$description")
  [[ -n "$sensitivity" ]] && init_args+=(--sensitivity "$sensitivity")

  if ! hm "${init_args[@]}" >/dev/null 2>&1; then
    _hive_memory_warn "store initialization failed"
  fi
}

_hive_memory_check_config() {
  local config="$1"

  # `dot update` is the convergence path, not the diagnostic path. Keep this
  # check to config parsing and store alias loading; broader store/cache scans
  # belong in `dot doctor` or explicit `hm doctor` runs.
  if ! hm --config "$config" stores list --json >/dev/null 2>&1; then
    _hive_memory_warn "config check reported issues"
  fi
}

merge() {
  _dot_tool_any_command hm || return 0
  local config spec spec_rc
  _hive_memory_config || return 0
  config="$REPLY"

  [[ -f "$config" ]] || return 0

  # Ask Hive for its effective layered configuration rather than parsing the
  # primary TOML ourselves. This keeps config.local.toml precedence, expansion,
  # validation, and future schema behavior owned by the provider.
  spec_rc=0
  spec=$(_hive_memory_effective_store_spec "$config" 2>/dev/null) || spec_rc=$?
  # The tracked launcher stays linked where the real hm is never installed:
  # Android is excluded from the dependency, and a client without a dependency
  # provider never converges it. The launcher exits 127 there, which is an
  # absent tool, not a broken config, so skip quietly like any other missing
  # tool. A 127 while the core is installed (the launcher also uses it for an
  # unavailable AgentGuard) is a broken install and still warns below.
  if ((spec_rc == 127)) && ! _hive_memory_core_installed; then
    return 0
  fi

  dot_hook_log "  Hive Memory"

  _hive_memory_init_default_store "$config" "$spec_rc" "$spec"
  _hive_memory_check_config "$config"
}
