# shellcheck shell=bash
# dot doctor: development-only Nvim policy.

_DR_NVIM_DEV_SESSION_GUARD=(--cmd 'lua vim.g.disable_session_restore = true')

_dr_dev_csv() {
  local IFS=,
  printf '%s' "$*"
}

# Read the first keyed field without an early-exiting pipeline: verbose Nvim
# output can otherwise make the producer hit SIGPIPE under the doctor's
# inherited pipefail policy.
_dr_dev_value() {
  local key=$1 content=$2 line value
  while IFS= read -r line; do
    case $line in
      "$key="*)
        value=${line#*=}
        printf '%s' "${value%%=*}"
        return 0
        ;;
    esac
  done <<<"$content"
  return 0
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
  local query_file output status enabled covered drift missing stale error
  query_file=$(mktemp "${TMPDIR:-/tmp}/dot-nvim-lsp-policy.XXXXXX") || {
    _dr_warn 'nvim LSP fallback policy check failed' 'could not create temp file'
    return 0
  }
  # `+luafile` reports a Lua error on stderr but Nvim still exits 0, and an
  # empty answer reads as two empty, matching lists. Run the query under pcall
  # and require its closing sentinel, so only a query that ran to completion
  # can report "in sync".
  cat >"$query_file" <<'LUA'
local ok, err = pcall(function()
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
end)
if ok then
  print("dot_doctor_query=complete")
else
  -- One bounded line: doctor details are single-line and the full require()
  -- search path would bury the reason.
  print("dot_doctor_error=" .. tostring(err):gsub("%s+", " "):sub(1, 200))
end
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
  if [[ $(_dr_dev_value dot_doctor_query "$output") != complete ]]; then
    # Not _dr_dev_value: Lua error text may itself contain '='.
    error=
    if [[ $output == *dot_doctor_error=* ]]; then
      error=${output#*dot_doctor_error=}
      error=${error%%$'\n'*}
    fi
    _dr_warn 'nvim LSP fallback policy check failed' \
      "${error:-query did not complete; run nvim headless with Mason disabled to debug}"
    return 0
  fi
  enabled=$(_dr_dev_value enabled "$output")
  covered=$(_dr_dev_value covered "$output")
  drift=$(_dr_lsp_policy_diff "$enabled" "$covered")
  missing=$(_dr_dev_value missing "$drift")
  stale=$(_dr_dev_value stale "$drift")
  if [[ -z $missing && -z $stale ]]; then
    _dr_ok 'nvim LSP fallback policy in sync'
  else
    local -a details=()
    [[ -z $missing ]] || details+=("missing fallback policy for enabled server(s): $missing")
    [[ -z $stale ]] || details+=("fallback policy for disabled server(s): $stale")
    _dr_warn 'nvim LSP fallback policy drift' "$(_dr_dev_csv "${details[@]}")"
  fi
}

_dr_check_nvim_dev() {
  local missing=0 module_path
  _dr_section 'Nvim development tooling'

  # Report only absent modules: present ones are already covered by core's
  # overlay link check, and a row per healthy file was noise.
  for module_path in \
    "$HOME/.config/nvim/lua/config/mason-policy.lua" \
    "$HOME/.config/nvim/lua/dotfiles/lazyvim_extras/dev.lua" \
    "$HOME/.config/nvim/lua/dotfiles/plugin_overrides/dev-tools.lua" \
    "$HOME/.config/nvim/lua/dotfiles/plugin_overrides/workspace-dev.lua" \
    "$HOME/.config/nvim/lua/dotfiles/final_policy/mason.lua" \
    "$HOME/.config/nvim/lua/plugins/formatting.lua" \
    "$HOME/.config/nvim/lua/plugins/linting.lua"; do
    if [[ ! -r $module_path ]]; then
      _dr_fail "${module_path##*/} missing" "$(_dr_tilde "$module_path")"
      missing=$((missing + 1))
    fi
  done

  ((missing == 0)) || return 0
  if ! command -v nvim >/dev/null 2>&1; then
    _dr_skip 'nvim LSP fallback policy' 'nvim not installed'
    return 0
  fi
  _dr_check_nvim_lsp_policy
}
