# shellcheck shell=bash
# Test-only loader for client hooks sourced in fresh Bash subprocesses.

_dot_test_api_source_home=${DOT_TEST_SOURCE_HOME:-${REAL_HOME:-${HOME:-}}}
_dot_test_api_host_home=${DOT_TEST_HOST_HOME:-${HOME:-}}
_dot_test_api_root=${DOT_TEST_DOT_ROOT:-}

if [[ -z $_dot_test_api_root ]]; then
  for _dot_test_api_candidate in \
    "$_dot_test_api_host_home/git/dot" \
    "$_dot_test_api_host_home/.local/share/cgraf78/dot"; do
    [[ -r $_dot_test_api_candidate/lib/dot/extension-worker.sh ]] || continue
    _dot_test_api_root=$(cd -P -- "$_dot_test_api_candidate" && pwd -P) || return
    break
  done
fi
[[ -n $_dot_test_api_root ]] || return 1

DOT_SOURCE_ROOT=$_dot_test_api_root
DOT_EXTENSIONS_DIR=$_dot_test_api_source_home/.local/lib/dotfiles
DOT_EXTENSION_API=1
export DOT_SOURCE_ROOT DOT_EXTENSIONS_DIR DOT_EXTENSION_API

# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/public/xdg.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/log.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/temp.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/merge-block.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/families.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/merge-hooks.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/repos/config.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/repos/overlays.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/extension-trust.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/hook-api.sh"
if ! dot_hook_source merge-hooks.d/lib/compat.sh; then
  # A standalone capability checkout has no base overlay. Reuse the frozen
  # public base contract in test scope so dev hook behavior is still exercised.
  # shellcheck shell=bash
  # Thin adapter for sourceable assets owned by shdeps-managed dependencies.
  #
  # Dotfiles should not know where dependencies are installed. shdeps owns that
  # contract, including local dev-clone precedence, install roots, and dependency
  # filters. These helpers only make the `shdeps dep-*` API convenient from
  # shell startup files, hooks, and small launchers that need to source a file.

  # Directory holding shdeps configuration (dependency lists and install hooks).
  _dot_shdeps_conf_dir() {
    printf '%s\n' "$HOME/.config/shdeps"
  }

  dot_shdeps_dep_file() {
    local conf_dir
    conf_dir="$(_dot_shdeps_conf_dir)"

    if command -v shdeps >/dev/null 2>&1; then
      SHDEPS_CONF_DIR="$conf_dir" command shdeps dep-file "$@"
      return
    fi

    # Fallback for minimal hook environments that have not loaded PATH yet. Treat
    # env-specific hints as candidates rather than hard requirements; test and
    # hook harnesses often carry a temporary SHDEPS_BIN_DIR while the real shdeps
    # CLI still lives at the normal dotfiles install path.
    local shdeps_bin="${SHDEPS_BIN:-}"
    if [ -n "$shdeps_bin" ] && [ -x "$shdeps_bin" ]; then
      SHDEPS_CONF_DIR="$conf_dir" "$shdeps_bin" dep-file "$@"
      return
    fi

    if [ -n "${SHDEPS_BIN_DIR:-}" ] && [ -x "$SHDEPS_BIN_DIR/shdeps" ]; then
      SHDEPS_CONF_DIR="$conf_dir" "$SHDEPS_BIN_DIR/shdeps" dep-file "$@"
      return
    fi

    if [ -x "$HOME/.local/bin/shdeps" ]; then
      SHDEPS_CONF_DIR="$conf_dir" "$HOME/.local/bin/shdeps" dep-file "$@"
      return
    fi

    return 127
  }

  dot_shdeps_dep_source() {
    local asset
    asset=$(dot_shdeps_dep_file "$@") || return
    [ -n "$asset" ] || return 1
    # shellcheck disable=SC1090 # dependency asset path is resolved by shdeps.
    . "$asset"
  }

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
  # The installer and doctor share this cross-repository identity rather than
  # duplicating its literal at each consumer boundary.
  dot_agentguard_opencode_marker() {
    printf '%s\n' '// agentguard-managed:opencode-plugin'
  }
  # shellcheck shell=bash
  # Shared Windows/WSL path discovery helpers.
  #
  # WSL has two user identities in play: the Linux account running dotfiles and
  # the Windows profile that owns GUI apps. They often have the same short name on
  # personal machines, but that is a convenience, not a contract. Keep Windows
  # profile discovery behind this helper so hooks and interactive shell helpers do
  # not drift back to guessing the Windows profile from the Linux username.

  _dot_windows_cmd_exe() {
    local candidate converted

    if [ -n "${DOT_TEST_WINDOWS_CMD_EXE:-}" ]; then
      [ -x "$DOT_TEST_WINDOWS_CMD_EXE" ] || return 1
      REPLY="$DOT_TEST_WINDOWS_CMD_EXE"
      return 0
    fi

    if command -v wslpath >/dev/null 2>&1; then
      converted="$(wslpath 'C:\Windows\System32\cmd.exe' 2>/dev/null)" || converted=""
      if [ -n "$converted" ] && [ -x "$converted" ]; then
        REPLY="$converted"
        return 0
      fi
    fi

    for candidate in /mnt/c/Windows/System32/cmd.exe "$(command -v cmd.exe 2>/dev/null)"; do
      [ -n "$candidate" ] || continue
      [ -x "$candidate" ] || continue
      _dot_windows_is_system_cmd "$candidate" || continue
      REPLY="$candidate"
      return 0
    done

    return 1
  }

  _dot_windows_is_system_cmd() {
    local command_path="$1" windows_path

    # PATH inside WSL can contain stale or fake Windows command shims. Match the
    # stricter VS Code resolver policy: only the real System32 cmd.exe is allowed
    # to tell us which Windows profile owns GUI app state.
    command -v wslpath >/dev/null 2>&1 || return 1
    windows_path="$(wslpath -w "$command_path" 2>/dev/null)" || return 1
    windows_path="${windows_path//\//\\}"
    windows_path="$(printf '%s' "$windows_path" | tr '[:upper:]' '[:lower:]')"
    case "$windows_path" in
      [a-z]:\\windows\\system32\\cmd.exe) return 0 ;;
    esac
    return 1
  }

  # Query a raw Windows environment variable via cmd.exe, with no path
  # conversion. Shared by the path-shaped resolver below and by plain
  # (non-path) vars like USERNAME that wslpath cannot convert.
  _dot_windows_env_raw() {
    local name="$1" cmd cmd_dir output line value=""

    _dot_windows_cmd_exe || return 1
    cmd="$REPLY"
    cmd_dir="$(dirname "$cmd")"

    # Start cmd.exe from a Windows-mounted directory. Otherwise Windows can print
    # a UNC-cwd warning before the real `set` output when dot runs from a Linux
    # path, and first-line parsers silently lose the value.
    output="$(
      cd "$cmd_dir" 2>/dev/null && "$cmd" /D /C "set $name" </dev/null 2>/dev/null | tr -d '\r'
    )" ||
      output=""
    while IFS= read -r line; do
      case "$line" in
        "$name="*)
          value="${line#"$name="}"
          break
          ;;
      esac
    done <<<"$output"
    [ -n "$value" ] || return 1

    REPLY="$value"
  }

  _dot_windows_env_path() {
    local name="$1" converted

    _dot_windows_env_raw "$name" || return 1

    converted="$(wslpath "$REPLY" 2>/dev/null)" || return 1
    [ -n "$converted" ] || return 1

    REPLY="$converted"
  }

  dot_wsl_windows_home() {
    local appdata

    # DOT_WINDOWS_HOME is the generic override for shell hooks. Keep the old test
    # variable for existing tests; VS Code's activation adapter maps this policy
    # and its older compatibility alias into the provider's public namespace.
    if [ -n "${DOT_TEST_WINDOWS_HOME:-}" ]; then
      REPLY="$DOT_TEST_WINDOWS_HOME"
      return 0
    fi
    if [ -n "${DOT_WINDOWS_HOME:-}" ]; then
      REPLY="$DOT_WINDOWS_HOME"
      return 0
    fi

    if [ "${DOT_TEST:-0}" = 1 ]; then
      # WSL exposes the real Windows profile even when tests replace HOME. Tests
      # must opt in explicitly so a unit test never writes into the host profile.
      return 1
    fi

    if _dot_windows_env_path USERPROFILE; then
      return 0
    fi

    if _dot_windows_env_path APPDATA; then
      appdata="$REPLY"
      case "$appdata" in
        */AppData/Roaming)
          REPLY="${appdata%/AppData/Roaming}"
          return 0
          ;;
      esac
    fi

    return 1
  }

  # Whether the current OS account is the one paired with the native Windows
  # profile, i.e. the account GUI apps (VS Code, WezTerm, ...) actually run as.
  # WSL conventionally runs one Linux account per Windows user, but the kernel
  # and the mounted Windows filesystem are shared with any other Linux account
  # on the same distro (root, secondary users). dot_wsl_windows_home() resolves
  # the single shared Windows profile regardless of caller, so if more than one
  # account runs `dot update` and each merges into that same native config file,
  # their unlocked writes race on the same NTFS/9p file and can corrupt it. Guard
  # call sites that write into the native Windows profile with this check.
  #
  # Compares live values instead of a configured or hardcoded account name so
  # the check works on any host no matter what either account is named.
  dot_wsl_is_paired_windows_account() {
    if [ -n "${DOT_TEST_WSL_PAIRED_ACCOUNT:-}" ]; then
      [ "$DOT_TEST_WSL_PAIRED_ACCOUNT" = 1 ]
      return
    fi

    if [ "${DOT_TEST:-0}" = 1 ]; then
      return 1
    fi

    local windows_user linux_user
    _dot_windows_env_raw USERNAME || return 1
    # dot update runs merge hooks under `set -euo pipefail`; a failing id/tr
    # here would abort the whole run (skipping every hook after this one,
    # including ones that have nothing to do with Windows) rather than just
    # treating this account as unpaired. Fall back to empty on failure instead.
    windows_user="$(printf '%s' "$REPLY" | tr '[:upper:]' '[:lower:]')" || windows_user=""
    linux_user="$(id -un 2>/dev/null | tr '[:upper:]' '[:lower:]')" || linux_user=""
    [ -n "$windows_user" ] && [ -n "$linux_user" ] && [ "$windows_user" = "$linux_user" ]
  }

  # dot_wsl_windows_home() itself stays unguarded: reading where the Windows
  # profile lives is safe for any account (e.g. the interactive WINHOME shell
  # aliases in 51-aliases-wsl.sh, usable from any Linux account on the distro).
  # Writing dotfiles-managed config into it is not, since a second account can
  # only get there by resolving the same path and racing the paired account's
  # writes. Route every such write through this wrapper instead of chaining
  # dot_wsl_is_paired_windows_account + dot_wsl_windows_home at each call site
  # by hand — a future call site can forget to add that check, but it cannot
  # get a path out of this function without it.
  dot_wsl_writable_windows_home() {
    dot_wsl_is_paired_windows_account || return 1
    dot_wsl_windows_home
  }
  _dot_tool_command_present() {
    command -v "$1" >/dev/null 2>&1
  }

  _dot_tool_path_exists() {
    [[ -e $1 ]]
  }

  _dot_tool_any_command() {
    local command_name
    for command_name in "$@"; do
      _dot_tool_command_present "$command_name" && return 0
    done
    return 1
  }

  _dot_tool_any_path() {
    local path
    for path in "$@"; do
      _dot_tool_path_exists "$path" && return 0
    done
    return 1
  }

  # Mirror the base compatibility contract without requiring diffutils in the
  # standalone overlay fixture.
  dot_config_files_equal() {
    local left_hash right_hash

    left_hash=$(git hash-object --no-filters -- "$1" 2>/dev/null) || return 1
    right_hash=$(git hash-object --no-filters -- "$2" 2>/dev/null) || return 1
    [[ $left_hash == "$right_hash" ]]
  }

  _dot_account_home() {
    local account entry name _password _uid _gid _gecos home _shell
    local candidate id_command="" getent_command=""

    REPLY=
    for candidate in \
      /data/data/com.termux/files/usr/bin/id \
      /usr/bin/id \
      /bin/id; do
      [[ -x "$candidate" ]] || continue
      id_command=$candidate
      break
    done
    [[ -n "$id_command" ]] || return 1
    account=$("$id_command" -un 2>/dev/null) || return 1
    case "$account" in
      "" | *[!A-Za-z0-9._-]*) return 1 ;;
    esac

    # Account authority must not come from a caller-controlled HOME or PATH.
    for candidate in \
      /usr/bin/getent \
      /bin/getent \
      /data/data/com.termux/files/usr/bin/getent; do
      [[ -x "$candidate" ]] || continue
      getent_command=$candidate
      break
    done
    if [[ -n "$getent_command" ]]; then
      entry=$("$getent_command" passwd "$account" 2>/dev/null) || entry=
      if IFS=: read -r name _password _uid _gid _gecos home _shell <<<"$entry" &&
        [[ "$name" == "$account" ]]; then
        REPLY=$home
      fi
    fi

    if [[ -z "$REPLY" &&
      "$id_command" == /data/data/com.termux/files/usr/bin/id &&
      -d /data/data/com.termux/files/home ]]; then
      REPLY=/data/data/com.termux/files/home
    fi

    if [[ -z "$REPLY" && -x /usr/bin/dscl ]]; then
      entry=$(/usr/bin/dscl /Search -read "/Users/$account" NFSHomeDirectory 2>/dev/null) || entry=
      case "$entry" in
        "NFSHomeDirectory: "*) REPLY=${entry#NFSHomeDirectory: } ;;
      esac
    fi

    if [[ -z "$REPLY" && -r /etc/passwd ]]; then
      while IFS=: read -r name _password _uid _gid _gecos home _shell; do
        [[ "$name" == "$account" ]] || continue
        REPLY=$home
        break
      done </etc/passwd
    fi

    [[ "$REPLY" == /* && -d "$REPLY" ]]
  }

  _dot_account_scoped_command() {
    local label="$1" command_name="$2" test_command="${3:-}"
    local account_home

    if [[ "${DOT_TEST:-0}" == "1" ]]; then
      if [[ -z "$test_command" || ! -x "$test_command" ]]; then
        dot_hook_warn "  warning: $label skipped: test $command_name is not configured"
        return 1
      fi
      REPLY="$test_command"
      return 0
    fi

    if ! _dot_account_home; then
      dot_hook_warn "  warning: $label skipped: account home could not be resolved"
      return 1
    fi
    account_home="$REPLY"
    if [[ ! -d "$HOME" || ! "$HOME" -ef "$account_home" ]]; then
      dot_hook_warn "  warning: $label skipped: HOME is not the account home: $HOME"
      return 1
    fi

    REPLY=$(command -v "$command_name" 2>/dev/null) || return 1
  }

  _dot_tool_platform() {
    local kernel

    if [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSL_INTEROP:-} ]]; then
      printf '%s\n' WSL
      return
    fi

    kernel=$(uname -r 2>/dev/null) || kernel=''
    case ${kernel,,} in
      *microsoft*) printf '%s\n' WSL ;;
      *) uname -s ;;
    esac
  }

  # Logical application presence is client policy. The public API deliberately
  # exposes only literal command/path probes, so platform aliases stay here.
  _dot_tool_present() {
    local tool=$1 platform

    case $tool in
      agent-rules) _dot_tool_any_command agent-rules-sync ;;
      claude) _dot_tool_any_command claude ;;
      codex) _dot_tool_any_command codex ;;
      cron) _dot_tool_any_command crontab ;;
      gemini) _dot_tool_any_command gemini ;;
      gh) _dot_tool_any_command gh ;;
      git) _dot_tool_any_command git ;;
      grafhome-ca) _dot_tool_any_command grafhome-ca ;;
      gstack) _dot_tool_any_command gstack-register ;;
      hive-memory) _dot_tool_any_command hm ;;
      ignore) _dot_tool_any_command rg fd fdfind ;;
      mise) _dot_tool_any_command mise ;;
      muse) _dot_tool_any_command muse ;;
      nvim) _dot_tool_any_command nvim ;;
      opencode) _dot_tool_any_command opencode ;;
      sapling) _dot_tool_any_command sl ;;
      ssh) _dot_tool_any_command ssh ;;
      tmux) _dot_tool_any_command tmux ;;
      iterm2)
        platform=$(_dot_tool_platform)
        [[ $platform == Darwin ]] || return 1
        _dot_tool_any_path /Applications/iTerm.app "$HOME/Applications/iTerm.app"
        ;;
      karabiner)
        platform=$(_dot_tool_platform)
        [[ $platform == Darwin ]] || return 1
        _dot_tool_any_path \
          /Applications/Karabiner-Elements.app \
          "$HOME/Applications/Karabiner-Elements.app" \
          '/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli'
        ;;
      vscode)
        _dot_tool_any_command \
          code code-insiders cursor codium codium-insiders \
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
          /Applications/Cursor.app "$HOME/Applications/Cursor.app" \
          /Applications/VSCodium.app "$HOME/Applications/VSCodium.app"
        ;;
      wezterm)
        _dot_tool_any_command wezterm wezterm.exe && return 0
        platform=$(_dot_tool_platform)
        [[ $platform == Darwin ]] || return 1
        _dot_tool_any_path /Applications/WezTerm.app "$HOME/Applications/WezTerm.app"
        ;;
      *) return 1 ;;
    esac
  }

  _merge_hook_mikefarah_yq() {
    local path_yq='' shdeps_yq='' yq_bin
    path_yq=$(command -v yq 2>/dev/null) || path_yq=''
    shdeps_yq=$HOME/.local/bin/yq
    for yq_bin in "$path_yq" "$shdeps_yq"; do
      [[ -n $yq_bin && -x $yq_bin ]] || continue
      if "$yq_bin" --version 2>/dev/null | grep -qi mikefarah; then
        printf '%s\n' "$yq_bin"
        return 0
      fi
    done
    return 1
  }

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
    if [[ ! -L $destination ]] && cmp -s "$temporary" "$destination" 2>/dev/null; then
      rm -f "$temporary"
      return 0
    fi
    dot_commit_tmp "$temporary" "$destination" || {
      rm -f "$temporary"
      return 1
    }
  }

  # Hooks source the same base-owned compatibility layer after this standalone
  # fixture has installed its equivalent functions. The dev-owned reversible
  # state helper is sourced from this checkout; all other extension lookup
  # still belongs to the public Dot API.
  dot_hook_source() {
    case ${1:-} in
      merge-hooks.d/lib/compat.sh) return 0 ;;
      merge-hooks.d/lib/profile-state.sh)
        # shellcheck source=/dev/null
        . "$DOT_EXTENSIONS_DIR/merge-hooks.d/lib/profile-state.sh"
        ;;
      *) return 1 ;;
    esac
  }
fi

unset _dot_test_api_candidate _dot_test_api_host_home
unset _dot_test_api_root _dot_test_api_source_home
