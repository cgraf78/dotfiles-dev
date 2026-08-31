# shellcheck shell=bash
# dot doctor: development-only Nvim policy.

_DR_NVIM_DEV_SESSION_GUARD=(--cmd 'lua vim.g.disable_session_restore = true')

_dr_dev_csv() {
  local IFS=,
  printf '%s' "$*"
}

_dr_lsp_policy_diff() {
  local enabled="$1" covered="$2" server
  local -a missing=() stale=()
  for server in $enabled; do
    case " $covered " in *" $server "*) ;; *) missing+=("$server") ;; esac
  done
  for server in $covered; do
    case " $enabled " in *" $server "*) ;; *) stale+=("$server") ;; esac
  done
  ((${#missing[@]} == 0)) || mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort)
  ((${#stale[@]} == 0)) || mapfile -t stale < <(printf '%s\n' "${stale[@]}" | sort)
  printf 'missing=%s\n' "$(_dr_dev_csv "${missing[@]+"${missing[@]}"}")"
  printf 'stale=%s\n' "$(_dr_dev_csv "${stale[@]+"${stale[@]}"}")"
}

_dr_check_nvim_lsp_policy() {
  local query_file output status enabled covered drift missing stale
  query_file=$(mktemp "${TMPDIR:-/tmp}/dot-nvim-lsp-policy.XXXXXX") || {
    _dr_warn 'nvim LSP fallback policy check failed' 'could not create temp file'
    return 0
  }
  cat >"$query_file" <<'LUA'
local policy = require("config.mason-policy")
require("lazy").load({ plugins = { "nvim-lspconfig" } })
local opts = require("lazyvim.util").opts("nvim-lspconfig")
local enabled, covered = {}, {}
for server, server_opts in pairs(opts.servers or {}) do
  if server ~= "*" and type(server_opts) == "table" and server_opts.enabled ~= false then
    table.insert(enabled, server)
  end
end
for server, _ in pairs(policy.lsp_server_packages()) do table.insert(covered, server) end
table.sort(enabled)
table.sort(covered)
print("enabled=" .. table.concat(enabled, " "))
print("covered=" .. table.concat(covered, " "))
LUA
  status=0
  output=$(nvim -i NONE --headless "${_DR_NVIM_DEV_SESSION_GUARD[@]}" \
    --cmd 'lua vim.g.mason_disabled = true' +"luafile $query_file" +qa! 2>&1) || status=$?
  rm -f "$query_file"
  if [[ $status -ne 0 ]]; then
    _dr_warn 'nvim LSP fallback policy check failed' \
      'run nvim headless with Mason disabled to debug'
    return 0
  fi
  enabled=$(printf '%s\n' "$output" | awk -F= '/^enabled=/ {print $2; exit}')
  covered=$(printf '%s\n' "$output" | awk -F= '/^covered=/ {print $2; exit}')
  drift=$(_dr_lsp_policy_diff "$enabled" "$covered")
  missing=$(printf '%s\n' "$drift" | awk -F= '/^missing=/ {print $2; exit}')
  stale=$(printf '%s\n' "$drift" | awk -F= '/^stale=/ {print $2; exit}')
  if [[ -z $missing && -z $stale ]]; then
    _dr_ok 'nvim LSP fallback policy in sync'
  else
    local -a details=()
    [[ -z $missing ]] || details+=("missing fallback policy for enabled server(s): $missing")
    [[ -z $stale ]] || details+=("fallback policy for disabled server(s): $stale")
    _dr_warn 'nvim LSP fallback policy drift' "$(_dr_dev_csv "${details[@]}")"
  fi
}

_dr_nvim_health_error_counts() {
  local health_file="$1"
  awk '
    function should_ignore() {
      if (section == "image" && image_disabled) return 1
      if (section == "input" && /`vim\.ui\.input` is not set/) return 1
      if (section == "notifier" && /is not ready/) return 1
      return 0
    }
    /^Snacks\.image ~/ { section="image"; image_disabled=0; next }
    /^Snacks\.input ~/ { section="input"; next }
    /^Snacks\.notifier ~/ { section="notifier"; next }
    /^[^[:space:]].* ~$/ && !/^Snacks\.(image|input|notifier) ~/ { section=""; image_disabled=0 }
    section == "image" && /setup \{disabled\}/ { image_disabled=1; next }
    /ERROR/ { if (should_ignore()) ignored_count++; else actionable++ }
    END { printf "%d %d\n", actionable + 0, ignored_count + 0 }
  ' "$health_file"
}

_dr_check_nvim_dev() {
  local missing=0 path
  _dr_section 'Nvim development tooling'

  for path in \
    "$HOME/.config/nvim/lua/config/mason-policy.lua" \
    "$HOME/.config/nvim/lua/dotfiles/lazyvim_extras/dev.lua" \
    "$HOME/.config/nvim/lua/dotfiles/plugin_overrides/dev-tools.lua" \
    "$HOME/.config/nvim/lua/dotfiles/plugin_overrides/workspace-dev.lua" \
    "$HOME/.config/nvim/lua/dotfiles/final_policy/mason.lua" \
    "$HOME/.config/nvim/lua/plugins/formatting.lua" \
    "$HOME/.config/nvim/lua/plugins/linting.lua"; do
    if [[ -r $path ]]; then
      _dr_ok "${path##*/}" 'configured'
    else
      _dr_fail "${path##*/} missing" "$(_dr_tilde "$path")"
      missing=$((missing + 1))
    fi
  done

  ((missing == 0)) || return 0
  command -v nvim >/dev/null 2>&1 || return 0
  _dr_check_nvim_lsp_policy
}
