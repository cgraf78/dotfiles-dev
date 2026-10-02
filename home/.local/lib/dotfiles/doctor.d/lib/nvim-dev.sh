# shellcheck shell=bash
# dot doctor: development-only Nvim policy.

# Per-probe deadline in seconds, and the timeout(1) or gtimeout that enforces
# it (resolved per run; empty when the host has neither). A healthy query
# finishes in well under a second; a busy Neovim can ignore SIGTERM, so the
# timeout escalates to SIGKILL after a short grace period.
_DR_DEV_NVIM_PROBE_TIMEOUT=8
_DR_DEV_NVIM_TIMEOUT_BIN=''
# Lua run from --cmd to load the probe script; an error escaping --cmd would
# leave headless Neovim waiting for input, so it quits with status 3 instead.
_DR_DEV_NVIM_PROBE_LOADER='local ok, err = pcall(dofile, vim.env.DOT_NVIM_PROBE_SCRIPT); '
_DR_DEV_NVIM_PROBE_LOADER+='if not ok then io.stderr:write(tostring(err), "\n"); vim.cmd("cquit 3") end'

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

# Run one bounded headless Neovim probe on the user's config: DIR SCRIPT.
# Adapted from the editor overlay's _dr_nvim_probe (dotfiles-nvim doctor.d/
# lib/nvim.sh) rather than sourced from it, because the overlays update
# independently and either may be older. SCRIPT runs from --cmd, before
# init.lua, and writes DIR/result in one step.
# - Neovim shares no pipe with doctor (stdin and stdout are /dev/null, stderr
#   goes to DIR/stderr), so a child it leaves behind cannot keep doctor
#   waiting; timeout(1) kills the run's process group at the deadline.
# - Private state, cache, and temp directories under DIR keep the instance
#   out of the user's editor state: Lazy state and logs, lsp.log, and
#   vim.loader's bytecode (one .luac per probe script path) all land there and
#   are removed with DIR. Data stays real: it holds the installed plugins the
#   query reads, and plugin_install_disabled keeps anything from writing it.
# - GIT_ALLOW_PROTOCOL=file makes any clone or fetch fail at once, even when a
#   config.lazy predates plugin_install_disabled; TMUX is unset so Termnav
#   makes no tmux queries.
# REPLY: "complete", "timeout", or the exit status of a run with no result.
_dr_dev_nvim_probe() {
  local dir=$1 script=$2 status=0 started=$SECONDS
  {
    XDG_STATE_HOME=$dir/state XDG_CACHE_HOME=$dir/cache TMPDIR=$dir/tmp \
      GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 \
      DOT_NVIM_PROBE_RESULT=$dir/result DOT_NVIM_PROBE_SCRIPT=$script \
      "$_DR_DEV_NVIM_TIMEOUT_BIN" -k 1 "$_DR_DEV_NVIM_PROBE_TIMEOUT" \
      env -u TMUX -u TMUX_PANE \
      nvim --headless -i NONE --cmd "lua $_DR_DEV_NVIM_PROBE_LOADER" \
      </dev/null >/dev/null 2>"$dir/stderr"
  } 2>/dev/null || status=$?
  # GNU timeout exits 124, or 137 after SIGKILL. BusyBox passes on Neovim's
  # own status, so a run that used up the deadline without a result counts too.
  if [[ $status -eq 124 || $status -eq 137 ]] ||
    [[ ! -f $dir/result && $((SECONDS - started)) -ge $_DR_DEV_NVIM_PROBE_TIMEOUT ]]; then
    REPLY=timeout
  elif [[ -f $dir/result ]]; then
    REPLY=complete
  else
    REPLY=$status
  fi
}

_dr_check_nvim_lsp_policy() {
  local probe_dir output enabled covered drift missing stale error data_dir
  local lock stderr_line
  local label='nvim LSP fallback policy'

  # Stat-level preconditions first, so a host that cannot answer costs no
  # Neovim start. The data and lock paths follow the editor overlay's
  # config.lazy and config.lazy-update-lock.
  data_dir=${XDG_DATA_HOME:-$HOME/.local/share}/${NVIM_APPNAME:-nvim}
  if [[ ! -d $data_dir/lazy/lazy.nvim ]]; then
    _dr_skip "$label" 'lazy.nvim is not installed; start nvim once to install plugins'
    return 0
  fi
  lock=$data_dir/lazy/lazy.nvim.update.lock
  if [[ -e $lock ]]; then
    # init.lua waits up to five minutes on this lock; report, never wait. An
    # older lock outlived its updater; the editor overlay's Neovim section
    # owns that warning, so only the reason for skipping differs here.
    if [[ -n $(find "$lock" -mmin +5 2>/dev/null) ]]; then
      _dr_skip "$label" "stale Lazy update lock $(_dr_tilde "$lock")"
    else
      _dr_skip "$label" 'a Lazy plugin update is running'
    fi
    return 0
  fi
  _DR_DEV_NVIM_TIMEOUT_BIN=''
  if command -v timeout >/dev/null 2>&1; then
    _DR_DEV_NVIM_TIMEOUT_BIN=timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    _DR_DEV_NVIM_TIMEOUT_BIN=gtimeout
  fi
  if [[ -z $_DR_DEV_NVIM_TIMEOUT_BIN ]]; then
    # The query runs user code; without a deadline it could hang doctor.
    _dr_skip "$label" 'timeout command not available'
    return 0
  fi
  probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/dot-nvim-lsp-policy.XXXXXX" 2>/dev/null) || {
    _dr_warn "$label check failed" 'could not create temp directory'
    return 0
  }
  if ! mkdir "$probe_dir/state" "$probe_dir/cache" "$probe_dir/tmp" 2>/dev/null; then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_warn "$label check failed" 'could not create temp directory'
    return 0
  fi

  # The script runs from --cmd, before init.lua: it switches off plugin and
  # Mason installs and session restore, then runs the query once startup has
  # settled. The query itself runs under pcall and only a run that reaches
  # the end writes the completion sentinel, so a crash can never read as two
  # matching (empty) server lists.
  if ! cat 2>/dev/null >"$probe_dir/probe.lua" <<'LUA'
local result = assert(vim.env.DOT_NVIM_PROBE_RESULT)
vim.g.plugin_install_disabled = true
vim.g.disable_session_restore = true
vim.g.mason_disabled = true

local function query()
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
  return {
    "enabled=" .. table.concat(enabled, " "),
    "covered=" .. table.concat(covered, " "),
    "dot_doctor_query=complete",
  }
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(function()
      vim.schedule(function()
        local ok, lines = pcall(query)
        if not ok then
          -- One bounded line: doctor details are single-line and the full
          -- require() search path would bury the reason.
          lines = { "dot_doctor_error=" .. tostring(lines):gsub("%s+", " "):sub(1, 200) }
        end
        vim.fn.writefile(lines, result)
        vim.cmd("qall!")
      end)
    end, 0)
  end,
})
LUA
  then
    rm -rf "$probe_dir" 2>/dev/null || true
    _dr_warn "$label check failed" 'could not write the probe script'
    return 0
  fi

  _dr_dev_nvim_probe "$probe_dir" "$probe_dir/probe.lua"
  case $REPLY in
    complete) output=$(<"$probe_dir/result") ;;
    timeout)
      rm -rf "$probe_dir" 2>/dev/null || true
      _dr_warn "$label check timed out" "no result within ${_DR_DEV_NVIM_PROBE_TIMEOUT}s"
      return 0
      ;;
    *)
      # The first stderr line (a loader error, for one) is the best clue.
      stderr_line=
      IFS= read -r stderr_line <"$probe_dir/stderr" 2>/dev/null || true
      stderr_line=${stderr_line:0:200}
      stderr_line=${stderr_line//[$'\t\r']/ }
      rm -rf "$probe_dir" 2>/dev/null || true
      _dr_warn "$label check failed" \
        "nvim exited with status $REPLY${stderr_line:+: $stderr_line}"
      return 0
      ;;
  esac
  rm -rf "$probe_dir" 2>/dev/null || true

  if [[ $(_dr_dev_value dot_doctor_query "$output") != complete ]]; then
    # Not _dr_dev_value: Lua error text may itself contain '='.
    error=
    if [[ $output == *dot_doctor_error=* ]]; then
      error=${output#*dot_doctor_error=}
      error=${error%%$'\n'*}
    fi
    _dr_warn "$label check failed" \
      "${error:-query did not complete; run nvim headless with Mason disabled to debug}"
    return 0
  fi
  enabled=$(_dr_dev_value enabled "$output")
  covered=$(_dr_dev_value covered "$output")
  drift=$(_dr_lsp_policy_diff "$enabled" "$covered")
  missing=$(_dr_dev_value missing "$drift")
  stale=$(_dr_dev_value stale "$drift")
  if [[ -z $missing && -z $stale ]]; then
    _dr_ok "$label in sync"
  else
    local -a details=()
    [[ -z $missing ]] || details+=("missing fallback policy for enabled server(s): $missing")
    [[ -z $stale ]] || details+=("fallback policy for disabled server(s): $stale")
    _dr_warn "$label drift" "$(_dr_dev_csv "${details[@]}")"
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
