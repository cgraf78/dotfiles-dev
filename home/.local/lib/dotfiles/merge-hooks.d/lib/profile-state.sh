# shellcheck shell=bash
# Reversible ownership receipts for dev-generated structured configuration.

_dev_profile_state_root() {
  local state_home=${XDG_STATE_HOME:-$HOME/.local/state}
  printf '%s\n' "$state_home/dot/overlays/dev/merge-receipts-v1"
}

_dev_profile_state_engine() {
  local source=${BASH_SOURCE[0]} directory target here
  if [[ -n ${_DEV_PROFILE_STATE_ENGINE:-} ]]; then
    printf '%s\n' "$_DEV_PROFILE_STATE_ENGINE"
    return
  fi
  if declare -F dot_hook_file >/dev/null 2>&1; then
    dot_hook_file merge-hooks.d/lib/profile-state.py || return 1
    printf '%s\n' "$REPLY"
    return
  fi
  while [[ -L $source ]]; do
    directory=$(cd -P -- "${source%/*}" && pwd -P) || return 1
    target=$(readlink "$source") || return 1
    case $target in
      /*) source=$target ;;
      *) source=$directory/$target ;;
    esac
  done
  here=$(cd -P -- "${source%/*}" && pwd -P) || return 1
  printf '%s/profile-state.py\n' "$here"
}

_dev_profile_state_toml_renderer() {
  local source=${BASH_SOURCE[0]} directory target here
  if [[ -n ${_DEV_PROFILE_STATE_TOML_RENDERER:-} ]]; then
    printf '%s\n' "$_DEV_PROFILE_STATE_TOML_RENDERER"
    return
  fi
  if declare -F dot_hook_file >/dev/null 2>&1; then
    dot_hook_file merge-hooks.d/lib/codex/toml-render.py || return 1
    printf '%s\n' "$REPLY"
    return
  fi
  while [[ -L $source ]]; do
    directory=$(cd -P -- "${source%/*}" && pwd -P) || return 1
    target=$(readlink "$source") || return 1
    case $target in
      /*) source=$target ;;
      *) source=$directory/$target ;;
    esac
  done
  here=$(cd -P -- "${source%/*}" && pwd -P) || return 1
  printf '%s/codex/toml-render.py\n' "$here"
}

_dev_profile_state_files_equal() {
  local engine
  engine=$(_dev_profile_state_engine) || return 2
  python3 "$engine" equal --left "$1" --right "$2"
}

_dev_profile_state_path_allowed() {
  local policy=$1 destination=$2
  [[ $destination == /* && $destination != *$'\n'* && $destination != *$'\r'* ]] ||
    return 1
  case $policy in
    test-object) [[ ${DOT_TEST:-0} == 1 && $destination == "$HOME/"* ]] ;;
    claude) [[ $destination == "$HOME/.claude/settings.json" ]] ;;
    gemini) [[ $destination == "$HOME/.gemini/settings.json" ]] ;;
    muse) [[ $destination == "$HOME/.config/muse/settings.json" ]] ;;
    gh) [[ $destination == "$HOME/.config/gh/config.yml" ]] ;;
    codex) [[ $destination == "$HOME/.codex/config.toml" ||
      $destination == "$HOME/.codex/"*.config.toml ]] ;;
    vscode-settings)
      [[ $destination == "$HOME/.config/"*/User/settings.json ||
        $destination == "$HOME/Library/Application Support/"*/User/settings.json ||
        $destination == "$HOME/."*-server/data/Machine/settings.json ||
        $destination == "$HOME/.vscode-remote/data/Machine/settings.json" ||
        (${DOT_TEST:-0} == 1 && $destination == "$HOME/"*/User/settings.json) ||
        $destination == /mnt/[a-zA-Z]/Users/*/AppData/Roaming/*/User/settings.json ]]
      ;;
    vscode-keybindings)
      [[ $destination == "$HOME/.config/"*/User/keybindings.json ||
        $destination == "$HOME/Library/Application Support/"*/User/keybindings.json ||
        (${DOT_TEST:-0} == 1 && $destination == "$HOME/"*/User/keybindings.json) ||
        $destination == /mnt/[a-zA-Z]/Users/*/AppData/Roaming/*/User/keybindings.json ]]
      ;;
    vscode-extensions)
      [[ $destination == "$HOME/."*/extensions/extensions.json ]]
      ;;
    *) return 1 ;;
  esac
}

_dev_profile_state_policy_format_valid() {
  local policy=$1 format=$2
  case $policy:$format in
    test-object:json | claude:json | gemini:json | muse:json | \
      vscode-settings:jsonc | vscode-keybindings:jsonc | \
      vscode-extensions:json | gh:yaml | codex:toml)
      return 0
      ;;
    *) return 1 ;;
  esac
}

_dev_profile_state_publisher_valid() {
  local policy=$1 publisher=$2
  case $publisher in
    atomic) return 0 ;;
    verified-in-place)
      [[ $policy == vscode-settings || $policy == vscode-keybindings ||
        $policy == vscode-extensions ]]
      ;;
    *) return 1 ;;
  esac
}

_dev_profile_state_document_valid() {
  local policy=$1 document=$2 filter
  case $policy in
    vscode-keybindings | vscode-extensions) filter='type == "array"' ;;
    *) filter='type == "object"' ;;
  esac
  jq -e "$filter" "$document" >/dev/null
}

_dev_profile_state_tempdir() {
  local parent=${TMPDIR:-/tmp} directory
  case $parent in
    /*) ;;
    *) return 1 ;;
  esac
  [[ -d $parent && ! -L $parent ]] || return 1
  directory=$(mktemp -d "$parent/dev-profile-state.XXXXXX") || return 1
  chmod 0700 "$directory" || {
    rmdir "$directory" 2>/dev/null || true
    return 1
  }
  REPLY=$directory
}

_dev_profile_state_tempdir_remove() {
  local directory=${1:-} parent=${TMPDIR:-/tmp}
  case $directory in
    "$parent"/dev-profile-state.*) ;;
    *) return 1 ;;
  esac
  [[ -d $directory && ! -L $directory && -O $directory ]] || return 1
  rm -rf -- "$directory"
}

_dev_profile_state_private_directory() {
  local directory=$1 mode
  [[ -d $directory && ! -L $directory && -O $directory ]] || return 1
  mode=$(stat -c '%a' "$directory" 2>/dev/null || stat -f '%Lp' "$directory") ||
    return 1
  [[ $mode != *[!0-7]* ]] || return 1
  (((8#$mode & 077) == 0))
}

_dev_profile_state_receipt_safe() {
  local receipt=$1 mode links size
  [[ -f $receipt && ! -L $receipt && -O $receipt ]] || return 1
  mode=$(stat -c '%a' "$receipt" 2>/dev/null || stat -f '%Lp' "$receipt") ||
    return 1
  links=$(stat -c '%h' "$receipt" 2>/dev/null || stat -f '%l' "$receipt") ||
    return 1
  size=$(wc -c <"$receipt" | tr -d '[:space:]') || return 1
  [[ $mode != *[!0-7]* && $links == 1 && $size =~ ^[0-9]+$ ]] || return 1
  (((8#$mode & 077) == 0 && size <= 8388608))
}

_dev_profile_state_private_file_safe() {
  local file=$1 mode links size
  [[ -f $file && ! -L $file && -O $file ]] || return 1
  mode=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file") ||
    return 1
  links=$(stat -c '%h' "$file" 2>/dev/null || stat -f '%l' "$file") ||
    return 1
  size=$(wc -c <"$file" | tr -d '[:space:]') || return 1
  [[ $mode != *[!0-7]* && $links == 1 && $size =~ ^[0-9]+$ ]] || return 1
  (((8#$mode & 077) == 0 && size <= 8388608))
}

_dev_profile_state_key() {
  printf '%s\n%s\n' "$1" "$2" | git hash-object --stdin
}

_dev_profile_state_single_writer() {
  [[ ${DOT_TEST:-0} == 1 || -n ${DOT_UPDATE_LOCK_TOKEN:-} ]]
}

_dev_profile_state_json() {
  local format=$1 source=$2 output=$3 yq_bin
  case $format in
    json) jq -S . "$source" >"$output" ;;
    jsonc)
      LC_ALL=C awk '
        NR == 1 { sub(/^\357\273\277/, "", $0) }
        { sub(/\r$/, "", $0) }
        !/^[[:space:]]*\/\//
      ' "$source" | jq -S . >"$output"
      ;;
    yaml | toml)
      yq_bin=$(_merge_hook_mikefarah_yq) || return 1
      "$yq_bin" eval --input-format "$format" --output-format json '.' \
        "$source" | jq -S . >"$output"
      ;;
    *) return 2 ;;
  esac
}

_dev_profile_state_render() {
  local format=$1 source=$2 destination=$3 temporary yq_bin renderer
  mkdir -p "${destination%/*}" || return 1
  temporary=$(mktemp "${destination}.tmp.XXXXXX") || return 1
  chmod 0600 "$temporary" || {
    rm -f "$temporary"
    return 1
  }
  case $format in
    json | jsonc)
      jq --indent 2 --sort-keys . "$source" >"$temporary" || {
        rm -f "$temporary"
        return 1
      }
      ;;
    yaml)
      yq_bin=$(_merge_hook_mikefarah_yq) || {
        rm -f "$temporary"
        return 1
      }
      "$yq_bin" eval --input-format json --output-format yaml '.' \
        "$source" >"$temporary" || {
        rm -f "$temporary"
        return 1
      }
      ;;
    toml)
      renderer=$(_dev_profile_state_toml_renderer) || {
        rm -f "$temporary"
        return 1
      }
      python3 "$renderer" render-json "$source" >"$temporary" || {
        rm -f "$temporary"
        return 1
      }
      ;;
    *)
      rm -f "$temporary"
      return 2
      ;;
  esac
  REPLY=$temporary
}

_dev_profile_state_install() {
  local publisher=$1 source=$2 destination=$3 engine
  case $publisher in
    atomic) mv -f "$source" "$destination" ;;
    verified-in-place)
      engine=$(_dev_profile_state_engine) || return 1
      python3 "$engine" publish-in-place \
        --source "$source" --destination "$destination" || return 1
      rm -f -- "$source"
      ;;
    *) return 2 ;;
  esac
}

_dev_profile_state_publish() {
  local format=$1 source=$2 destination=$3 publisher=${4:-atomic} temporary
  _dev_profile_state_render "$format" "$source" "$destination" || return 1
  temporary=$REPLY
  _dev_profile_state_install "$publisher" "$temporary" "$destination" || {
    rm -f "$temporary"
    return 1
  }
}

_dev_profile_state_empty_document() {
  case $1 in
    vscode-keybindings | vscode-extensions) printf '[]\n' ;;
    *) printf '{}\n' ;;
  esac
}

_dev_profile_state_document_empty() {
  case $1 in
    vscode-keybindings | vscode-extensions)
      jq -e 'type == "array" and length == 0' "$2" >/dev/null
      ;;
    *) jq -e 'type == "object" and length == 0' "$2" >/dev/null ;;
  esac
}

_dev_profile_state_link_allowed() {
  local path=$1 target=$2 parent name
  [[ $path == /* && $target == "$HOME/"* ]] || return 1
  [[ $path != *$'\n'* && $path != *$'\r'* && $path != *$'\t'* ]] || return 1
  [[ $target != *$'\n'* && $target != *$'\r'* && $target != *$'\t'* ]] || return 1
  parent=${path%/*}
  name=${path##*/}
  [[ ${parent##*/} == extensions && -n $name && $name != . && $name != .. ]]
}

_dev_profile_state_links_valid() {
  local policy=$1 destination=$2 source=$3 path target parent
  jq -e '
    type == "array"
    and ((map(.path) | unique | length) == length)
    and all(.[];
      type == "object"
      and ((.path | type) == "string")
      and ((.path | length) > 0)
      and ((.path | test("[[:cntrl:]]")) | not)
      and ((.target | type) == "string")
      and ((.target | length) > 0)
      and ((.target | test("[[:cntrl:]]")) | not)
    )
  ' "$source" >/dev/null || return 1
  if jq -e 'length > 0' "$source" >/dev/null; then
    [[ $policy == vscode-extensions ]] || return 1
  fi
  parent=${destination%/*}
  while IFS=$'\t' read -r path target; do
    _dev_profile_state_link_allowed "$path" "$target" || return 1
    [[ $path == "$HOME/"* && ${path%/*} == "$parent" ]] || return 1
  done < <(jq -r '.[] | [.path, .target] | @tsv' "$source")
}

_dev_profile_state_restore_file() {
  local source=$1 destination=$2 mode=$3 publisher=${4:-atomic} temporary
  mkdir -p "${destination%/*}" || return 1
  temporary=$(mktemp "${destination}.tmp.XXXXXX") || return 1
  chmod 0600 "$temporary" || {
    rm -f "$temporary"
    return 1
  }
  if ! cp "$source" "$temporary" || ! chmod "$mode" "$temporary" ||
    ! _dev_profile_state_install "$publisher" "$temporary" "$destination"; then
    rm -f "$temporary"
    return 1
  fi
}

_dev_profile_state_pending_recover() {
  local root=$1 key=$2 policy=$3 format=$4 destination=$5 publisher=$6
  local pending=$root/$key.pending.json original=$root/$key.original
  local original_exists original_mode transaction transaction_dir
  [[ -e $pending || -L $pending ]] || return 0
  _dev_profile_state_receipt_safe "$pending" || return 1
  _dev_profile_state_publisher_valid "$policy" "$publisher" || return 1
  jq -e --arg policy "$policy" --arg format "$format" \
    --arg path "$destination" --arg publisher "$publisher" '
      type == "object" and .version == 1 and .phase == "updating"
      and .policy == $policy and .format == $format and .path == $path
      and .publisher == $publisher
      and (.original_exists | type == "boolean")
      and (.original_mode | type == "string")
      and (.transaction | type == "string" and length > 0)
      and (.transaction_dir | type == "string" and length > 0)
    ' "$pending" >/dev/null || return 1
  original_exists=$(jq -r .original_exists "$pending") || return 1
  original_mode=$(jq -r .original_mode "$pending") || return 1
  transaction=$(jq -r .transaction "$pending") || return 1
  transaction_dir=$(jq -r .transaction_dir "$pending") || return 1
  [[ $transaction_dir == "${TMPDIR:-/tmp}/dev-profile-state.$transaction" ]] ||
    return 1
  if [[ -f $root/$key.json && ! -L $root/$key.json ]] &&
    _dev_profile_state_receipt_safe "$root/$key.json" &&
    jq -e --arg transaction "$transaction" --arg policy "$policy" \
      --arg format "$format" --arg path "$destination" \
      --arg publisher "$publisher" '
        .version == 1 and .transaction == $transaction
        and .policy == $policy and .format == $format and .path == $path
        and .publisher == $publisher
      ' "$root/$key.json" >/dev/null; then
    if [[ -e $transaction_dir || -L $transaction_dir ]]; then
      _dev_profile_state_tempdir_remove "$transaction_dir" || return 1
    fi
    rm -f -- "$pending" "$original"
    return 0
  fi
  if [[ $original_exists == true ]]; then
    [[ $original_mode =~ ^[0-7]{3,4}$ ]] || return 1
    _dev_profile_state_private_file_safe "$original" || return 1
    _dev_profile_state_restore_file \
      "$original" "$destination" "$original_mode" "$publisher" || return 1
  else
    [[ $original_mode == '' && ! -e $original && ! -L $original ]] || return 1
    rm -f -- "$destination" || return 1
  fi
  if [[ -e $transaction_dir || -L $transaction_dir ]]; then
    _dev_profile_state_tempdir_remove "$transaction_dir" || return 1
  fi
  rm -f -- "$pending" "$original"
}

_dev_profile_state_pending_write() {
  local pending=$1 policy=$2 format=$3 destination=$4
  local publisher=$5 original_exists=$6 original_mode=$7 transaction=$8
  local transaction_dir=$9 temporary
  temporary=$(mktemp "${pending}.tmp.XXXXXX") || return 1
  chmod 0600 "$temporary" || {
    rm -f "$temporary"
    return 1
  }
  if ! jq -n --sort-keys \
    --arg policy "$policy" --arg format "$format" --arg path "$destination" \
    --arg publisher "$publisher" --arg original_mode "$original_mode" \
    --arg transaction "$transaction" --arg transaction_dir "$transaction_dir" \
    --argjson original_exists "$original_exists" \
    '{version: 1, phase: "updating", policy: $policy, format: $format,
      path: $path, publisher: $publisher, transaction: $transaction,
      transaction_dir: $transaction_dir,
      original_exists: $original_exists,
      original_mode: $original_mode}' >"$temporary" ||
    ! mv -f "$temporary" "$pending"; then
    rm -f "$temporary"
    return 1
  fi
}

_dev_profile_state_receipt_load() {
  local receipt=$1 policy=$2 format=$3 destination=$4 publisher=$5
  local before=$6 applied=$7 links=$8
  _dev_profile_state_policy_format_valid "$policy" "$format" || return 1
  _dev_profile_state_publisher_valid "$policy" "$publisher" || return 1
  _dev_profile_state_receipt_safe "$receipt" || return 1
  jq -e --arg policy "$policy" --arg format "$format" --arg path "$destination" \
    --arg publisher "$publisher" '
    type == "object" and .version == 1 and .policy == $policy
    and .format == $format and .path == $path
    and .publisher == $publisher
    and (.before_exists | type == "boolean")
    and has("before") and has("applied") and has("links")
  ' "$receipt" >/dev/null || return 1
  jq -S .before "$receipt" >"$before" || return 1
  jq -S .applied "$receipt" >"$applied" || return 1
  jq -S .links "$receipt" >"$links" || return 1
  _dev_profile_state_document_valid "$policy" "$before" || return 1
  _dev_profile_state_document_valid "$policy" "$applied" || return 1
  _dev_profile_state_links_valid "$policy" "$destination" "$links" || return 1
  REPLY=$(jq -r .before_exists "$receipt")
}

dev_profile_state_tracked() {
  local policy=$1 format=$2 destination=$3 publisher=${4:-atomic}
  local root key receipt pending
  [[ $# -ge 3 && $# -le 4 ]] || return 2
  _dev_profile_state_single_writer || return 1
  _dev_profile_state_policy_format_valid "$policy" "$format" || return 1
  _dev_profile_state_publisher_valid "$policy" "$publisher" || return 1
  _dev_profile_state_path_allowed "$policy" "$destination" || return 1
  root=$(_dev_profile_state_root) || return 1
  _dev_profile_state_private_directory "$root" || return 1
  _dev_profile_state_retirement_recover "$root" || return 1
  key=$(_dev_profile_state_key "$policy" "$destination") || return 1
  receipt=$root/$key.json
  pending=$root/$key.pending.json
  [[ ! -e $pending && ! -L $pending ]] || return 1
  _dev_profile_state_receipt_safe "$receipt" || return 1
  jq -e --arg policy "$policy" --arg format "$format" \
    --arg path "$destination" --arg publisher "$publisher" '
      type == "object" and .version == 1 and .policy == $policy
      and .format == $format and .path == $path
      and .publisher == $publisher
      and (.before_exists | type == "boolean")
      and has("before") and has("applied") and has("links")
    ' "$receipt" >/dev/null
}

dev_profile_state_begin() {
  local policy=$1 format=$2 destination=$3 managed=$4 publisher=${5:-atomic}
  local root key receipt pending original_state engine current before applied
  local baseline original managed_json receipt_links transaction_dir transaction temporary
  local original_mode='' current_valid=1
  [[ $# -ge 4 && $# -le 5 ]] || return 2
  _dev_profile_state_single_writer || return 1
  [[ ${_DEV_PROFILE_STATE_ACTIVE:-0} != 1 ]] || return 1
  _dev_profile_state_policy_format_valid "$policy" "$format" || return 2
  _dev_profile_state_publisher_valid "$policy" "$publisher" || return 2
  _dev_profile_state_path_allowed "$policy" "$destination" || return 1
  command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 &&
    command -v python3 >/dev/null 2>&1 || return 1
  engine=$(_dev_profile_state_engine) || return 1
  [[ -r $engine ]] || return 1
  root=$(_dev_profile_state_root) || return 1
  if [[ ! -d $root ]]; then
    (umask 077 && mkdir -p "$root") || return 1
  fi
  _dev_profile_state_private_directory "$root" || return 1
  _dev_profile_state_retirement_recover "$root" || return 1
  key=$(_dev_profile_state_key "$policy" "$destination") || return 1
  receipt=$root/$key.json
  pending=$root/$key.pending.json
  original_state=$root/$key.original
  _dev_profile_state_pending_recover \
    "$root" "$key" "$policy" "$format" "$destination" "$publisher" || return 1
  [[ ! -e $original_state && ! -L $original_state ]] || return 1

  _dev_profile_state_tempdir || return 1
  transaction_dir=$REPLY
  transaction=${transaction_dir##*.}
  managed_json=$transaction_dir/managed.json
  current=$transaction_dir/current.json
  before=$transaction_dir/before.json
  applied=$transaction_dir/applied.json
  receipt_links=$transaction_dir/receipt-links.json
  baseline=$transaction_dir/baseline.json
  original=$transaction_dir/original
  if ! _dev_profile_state_json "$format" "$managed" "$managed_json" ||
    ! _dev_profile_state_document_valid "$policy" "$managed_json"; then
    _dev_profile_state_tempdir_remove "$transaction_dir" || true
    return 1
  fi

  _DEV_PROFILE_STATE_ORIGINAL_EXISTS=0
  if [[ -e $destination || -L $destination ]]; then
    [[ -f $destination && ! -L $destination ]] || {
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    }
    original_mode=$(stat -c '%a' "$destination" 2>/dev/null ||
      stat -f '%Lp' "$destination") || {
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    }
    [[ $original_mode =~ ^[0-7]{3,4}$ ]] || {
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    }
    cp "$destination" "$original" || {
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    }
    _DEV_PROFILE_STATE_ORIGINAL_EXISTS=1
    if ! _dev_profile_state_json "$format" "$destination" "$current" ||
      ! _dev_profile_state_document_valid "$policy" "$current"; then
      current_valid=0
    fi
  else
    _dev_profile_state_empty_document "$policy" >"$current"
  fi

  if ((current_valid == 0)) && [[ $policy != codex ]]; then
    _dev_profile_state_tempdir_remove "$transaction_dir" || true
    return 1
  fi

  _DEV_PROFILE_STATE_BEFORE_EXISTS=$_DEV_PROFILE_STATE_ORIGINAL_EXISTS
  if [[ -e $receipt || -L $receipt ]]; then
    _dev_profile_state_receipt_load \
      "$receipt" "$policy" "$format" "$destination" "$publisher" \
      "$before" "$applied" "$receipt_links" ||
      {
        _dev_profile_state_tempdir_remove "$transaction_dir" || true
        return 1
      }
    _DEV_PROFILE_STATE_BEFORE_EXISTS=$REPLY
    if [[ $_DEV_PROFILE_STATE_ORIGINAL_EXISTS -eq 0 ]]; then
      _dev_profile_state_empty_document "$policy" >"$baseline"
      _DEV_PROFILE_STATE_BEFORE_EXISTS=false
    elif ((current_valid == 0)); then
      cp "$before" "$baseline" || {
        _dev_profile_state_tempdir_remove "$transaction_dir" || true
        return 1
      }
    else
      python3 "$engine" capture --policy "$policy" --before "$before" \
        --applied "$applied" --current "$current" --output "$baseline" ||
        {
          _dev_profile_state_tempdir_remove "$transaction_dir" || true
          return 1
        }
    fi
  else
    if ((current_valid == 0)); then
      _dev_profile_state_empty_document "$policy" >"$baseline"
    else
      python3 "$engine" adopt --policy "$policy" --managed "$managed_json" \
        --current "$current" --output "$baseline" || {
        _dev_profile_state_tempdir_remove "$transaction_dir" || true
        return 1
      }
    fi
    cp "$baseline" "$before" || {
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    }
    if ((current_valid == 0)); then
      _DEV_PROFILE_STATE_BEFORE_EXISTS=false
    elif [[ $_DEV_PROFILE_STATE_ORIGINAL_EXISTS -eq 1 ]] &&
      _dev_profile_state_document_empty "$policy" "$current"; then
      _DEV_PROFILE_STATE_BEFORE_EXISTS=true
    elif _dev_profile_state_document_empty "$policy" "$baseline"; then
      _DEV_PROFILE_STATE_BEFORE_EXISTS=false
    else
      _DEV_PROFILE_STATE_BEFORE_EXISTS=true
    fi
  fi

  if [[ $_DEV_PROFILE_STATE_ORIGINAL_EXISTS -eq 1 ]]; then
    temporary=$(mktemp "${original_state}.tmp.XXXXXX") || {
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    }
    chmod 0600 "$temporary" || {
      rm -f "$temporary"
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    }
    # BusyBox cp replaces the mode of an existing destination with the source
    # mode. Reassert privacy after copying so recovery accepts the staged state
    # consistently across GNU and BusyBox implementations.
    if ! cp "$original" "$temporary" || ! chmod 0600 "$temporary" ||
      ! mv -f "$temporary" "$original_state"; then
      rm -f "$temporary"
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    fi
  fi
  if ! _dev_profile_state_pending_write "$pending" "$policy" "$format" \
    "$destination" "$publisher" \
    "$([[ $_DEV_PROFILE_STATE_ORIGINAL_EXISTS -eq 1 ]] && printf true || printf false)" \
    "$original_mode" "$transaction" "$transaction_dir"; then
    rm -f -- "$original_state"
    _dev_profile_state_tempdir_remove "$transaction_dir" || true
    return 1
  fi

  if [[ $_DEV_PROFILE_STATE_BEFORE_EXISTS == true ]]; then
    if ! _dev_profile_state_publish \
      "$format" "$baseline" "$destination" "$publisher"; then
      _dev_profile_state_pending_recover \
        "$root" "$key" "$policy" "$format" "$destination" "$publisher" || true
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    fi
  else
    if ! rm -f -- "$destination"; then
      _dev_profile_state_pending_recover \
        "$root" "$key" "$policy" "$format" "$destination" "$publisher" || true
      _dev_profile_state_tempdir_remove "$transaction_dir" || true
      return 1
    fi
  fi
  _DEV_PROFILE_STATE_POLICY=$policy
  _DEV_PROFILE_STATE_FORMAT=$format
  _DEV_PROFILE_STATE_DESTINATION=$destination
  _DEV_PROFILE_STATE_PUBLISHER=$publisher
  _DEV_PROFILE_STATE_RECEIPT=$receipt
  _DEV_PROFILE_STATE_PENDING=$pending
  _DEV_PROFILE_STATE_ORIGINAL_STATE=$original_state
  _DEV_PROFILE_STATE_BEFORE=$before
  _DEV_PROFILE_STATE_BASELINE=$baseline
  _DEV_PROFILE_STATE_TRANSACTION_DIR=$transaction_dir
  _DEV_PROFILE_STATE_TRANSACTION=$transaction
  _DEV_PROFILE_STATE_ACTIVE=1
}

dev_profile_state_abort() {
  [[ ${_DEV_PROFILE_STATE_ACTIVE:-0} == 1 ]] || return 0
  local root key
  root=${_DEV_PROFILE_STATE_RECEIPT%/*}
  key=${_DEV_PROFILE_STATE_RECEIPT##*/}
  key=${key%.json}
  _dev_profile_state_pending_recover "$root" "$key" \
    "$_DEV_PROFILE_STATE_POLICY" "$_DEV_PROFILE_STATE_FORMAT" \
    "$_DEV_PROFILE_STATE_DESTINATION" "$_DEV_PROFILE_STATE_PUBLISHER" || return 1
  _DEV_PROFILE_STATE_ACTIVE=0
}

dev_profile_state_commit() {
  [[ ${_DEV_PROFILE_STATE_ACTIVE:-0} == 1 ]] || return 1
  local links=${1:-} applied=$_DEV_PROFILE_STATE_TRANSACTION_DIR/applied.json
  local empty_links=$_DEV_PROFILE_STATE_TRANSACTION_DIR/links.json receipt_tmp
  [[ $# -le 1 ]] || return 2
  if [[ -z $links ]]; then
    printf '[]\n' >"$empty_links"
    links=$empty_links
  fi
  _dev_profile_state_links_valid \
    "$_DEV_PROFILE_STATE_POLICY" "$_DEV_PROFILE_STATE_DESTINATION" "$links" ||
    return 1
  _dev_profile_state_json "$_DEV_PROFILE_STATE_FORMAT" \
    "$_DEV_PROFILE_STATE_DESTINATION" "$applied" || return 1
  _dev_profile_state_document_valid "$_DEV_PROFILE_STATE_POLICY" "$applied" ||
    return 1
  receipt_tmp=$(mktemp "${_DEV_PROFILE_STATE_PENDING}.tmp.XXXXXX") || return 1
  chmod 0600 "$receipt_tmp" || {
    rm -f "$receipt_tmp"
    return 1
  }
  if ! jq -n --sort-keys \
    --arg policy "$_DEV_PROFILE_STATE_POLICY" \
    --arg format "$_DEV_PROFILE_STATE_FORMAT" \
    --arg path "$_DEV_PROFILE_STATE_DESTINATION" \
    --arg publisher "$_DEV_PROFILE_STATE_PUBLISHER" \
    --arg transaction "$_DEV_PROFILE_STATE_TRANSACTION" \
    --argjson before_exists "$_DEV_PROFILE_STATE_BEFORE_EXISTS" \
    --slurpfile before "$_DEV_PROFILE_STATE_BASELINE" \
    --slurpfile applied "$applied" \
    --slurpfile links "$links" \
    '{version: 1, transaction: $transaction,
      policy: $policy, format: $format, path: $path, publisher: $publisher,
      before_exists: $before_exists, before: $before[0], applied: $applied[0],
      links: $links[0]}' \
    >"$receipt_tmp"; then
    rm -f "$receipt_tmp"
    return 1
  fi
  if ! mv -f "$receipt_tmp" "$_DEV_PROFILE_STATE_RECEIPT"; then
    rm -f "$receipt_tmp"
    return 1
  fi
  rm -f -- "$_DEV_PROFILE_STATE_PENDING" "$_DEV_PROFILE_STATE_ORIGINAL_STATE"
  _dev_profile_state_tempdir_remove "$_DEV_PROFILE_STATE_TRANSACTION_DIR" || true
  _DEV_PROFILE_STATE_ACTIVE=0
}

_dev_profile_state_recover_all_pending() {
  local root=$1 pending base key policy format destination publisher
  local nullglob_was_set=0
  local -a pending_files=()
  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  pending_files=("$root"/*.pending.json)
  ((nullglob_was_set == 1)) || shopt -u nullglob
  for pending in "${pending_files[@]}"; do
    base=${pending##*/}
    [[ $base =~ ^([0-9a-f]{40})\.pending\.json$ ]] || return 1
    key=${BASH_REMATCH[1]}
    _dev_profile_state_receipt_safe "$pending" || return 1
    policy=$(jq -r .policy "$pending") || return 1
    format=$(jq -r .format "$pending") || return 1
    destination=$(jq -r .path "$pending") || return 1
    publisher=$(jq -r .publisher "$pending") || return 1
    _dev_profile_state_policy_format_valid "$policy" "$format" || return 1
    _dev_profile_state_publisher_valid "$policy" "$publisher" || return 1
    _dev_profile_state_path_allowed "$policy" "$destination" || return 1
    [[ $key == "$(_dev_profile_state_key "$policy" "$destination")" ]] ||
      return 1
    _dev_profile_state_pending_recover \
      "$root" "$key" "$policy" "$format" "$destination" "$publisher" || return 1
  done
}

_dev_profile_state_remove_files() {
  local file status=0
  for file in "$@"; do
    [[ -n $file ]] || continue
    rm -f -- "$file" || status=1
  done
  return "$status"
}

_dev_profile_state_retirement_dir_clear() {
  local directory=$1 entry links
  local nullglob_was_set=0
  local -a entries=()
  [[ -e $directory || -L $directory ]] || return 0
  _dev_profile_state_private_directory "$directory" || return 1
  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  entries=("$directory"/*)
  ((nullglob_was_set == 1)) || shopt -u nullglob
  for entry in "${entries[@]}"; do
    [[ -f $entry && ! -L $entry && -O $entry ]] || return 1
    links=$(stat -c '%h' "$entry" 2>/dev/null || stat -f '%l' "$entry") ||
      return 1
    [[ $links == 1 ]] || return 1
    rm -f -- "$entry" || return 1
  done
  rmdir "$directory"
}

_dev_profile_state_retirement_manifest_update() {
  local manifest=$1 phase=$2 temporary
  temporary=$(mktemp "${manifest}.tmp.XXXXXX") || return 1
  chmod 0600 "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }
  if ! jq --arg phase "$phase" '.phase = $phase' "$manifest" >"$temporary" ||
    ! mv -f -- "$temporary" "$manifest"; then
    rm -f -- "$temporary"
    return 1
  fi
}

_dev_profile_state_retirement_link_paths_valid() {
  local path=$1 target=$2 quarantine=$3 parent quarantine_dir
  _dev_profile_state_link_allowed "$path" "$target" || return 1
  [[ $path == "$HOME/"* ]] || return 1
  parent=${path%/*}
  quarantine_dir=${quarantine%/*}
  [[ ${quarantine_dir%/*} == "$parent" ]] || return 1
  [[ ${quarantine_dir##*/} == .dot-profile-retire.* ]]
}

_dev_profile_state_retirement_recover() {
  local root=$1 manifest phase
  local directory=$root/.retiring
  local policy path publisher operation mode backup expected target quarantine receipt
  local status=0
  [[ -e $directory || -L $directory ]] || return 0
  _dev_profile_state_private_directory "$directory" || return 1
  manifest=$directory/manifest.json
  if [[ ! -e $manifest && ! -L $manifest ]]; then
    _dev_profile_state_retirement_dir_clear "$directory"
    return
  fi
  _dev_profile_state_private_file_safe "$manifest" || return 1
  jq -e '
    type == "object" and .version == 1
    and (.phase == "publishing" or .phase == "committed")
    and (.configs | type == "array")
    and (.links | type == "array")
    and (.receipts | type == "array")
  ' "$manifest" >/dev/null || return 1
  phase=$(jq -r .phase "$manifest") || return 1

  if [[ $phase == publishing ]]; then
    while IFS=$'\t' read -r policy path publisher operation mode backup expected; do
      _dev_profile_state_path_allowed "$policy" "$path" || return 1
      _dev_profile_state_publisher_valid "$policy" "$publisher" || return 1
      case $operation in
        none) continue ;;
        delete | replace) ;;
        *) return 1 ;;
      esac
      [[ $mode =~ ^[0-7]{3,4}$ ]] || return 1
      _dev_profile_state_private_file_safe "$backup" || return 1
      if [[ -f $path && ! -L $path ]] &&
        _dev_profile_state_files_equal "$path" "$backup"; then
        continue
      fi
      if [[ $operation == replace ]]; then
        _dev_profile_state_private_file_safe "$expected" || return 1
        [[ -f $path && ! -L $path ]] &&
          _dev_profile_state_files_equal "$path" "$expected" ||
          return 1
      else
        [[ ! -e $path && ! -L $path ]] || return 1
      fi
      _dev_profile_state_restore_file "$backup" "$path" "$mode" "$publisher" ||
        return 1
    done < <(jq -r '.configs | reverse[] |
      [.policy, .path, .publisher, .operation, .mode, .backup, .expected] | @tsv' \
      "$manifest")

    while IFS=$'\t' read -r path target quarantine; do
      _dev_profile_state_retirement_link_paths_valid \
        "$path" "$target" "$quarantine" || return 1
      if [[ -e $quarantine || -L $quarantine ]]; then
        [[ ! -e $path && ! -L $path ]] || return 1
        mv -- "$quarantine" "$path" || return 1
        rmdir "${quarantine%/*}" || return 1
      elif [[ -L $path && $(readlink "$path") == "$target" ]]; then
        continue
      elif [[ ! -e $path && ! -L $path ]]; then
        return 1
      else
        return 1
      fi
    done < <(jq -r '.links[] | [.path, .target, .quarantine] | @tsv' "$manifest")
    _dev_profile_state_retirement_dir_clear "$directory"
    return
  fi

  # A committed journal means live configuration is already retired. Only
  # finish deleting quarantined managed links and the now-inert receipts.
  while IFS=$'\t' read -r path target quarantine; do
    _dev_profile_state_retirement_link_paths_valid \
      "$path" "$target" "$quarantine" || return 1
    if [[ -e $quarantine || -L $quarantine ]]; then
      [[ -L $quarantine && $(readlink "$quarantine") == "$target" ]] || return 1
      rm -f -- "$quarantine" || status=1
      rmdir "${quarantine%/*}" 2>/dev/null || status=1
    fi
  done < <(jq -r '.links[] | [.path, .target, .quarantine] | @tsv' "$manifest")
  while IFS= read -r receipt; do
    [[ ${receipt%/*} == "$root" &&
      ${receipt##*/} =~ ^[0-9a-f]{40}\.json$ ]] || return 1
    if [[ -e $receipt || -L $receipt ]]; then
      _dev_profile_state_receipt_safe "$receipt" || return 1
      rm -f -- "$receipt" || status=1
    fi
  done < <(jq -r '.receipts[]' "$manifest")
  ((status == 0)) || return 1
  _dev_profile_state_retirement_dir_clear "$directory"
}

dev_profile_state_retire_all() {
  local root receipt policy format destination publisher before applied links current output key
  local before_exists expected backup mode index rollback_index nullglob_was_set=0
  local link_path link_target link_index quarantine quarantine_dir retired_dir
  local configs_log links_log receipts_log manifest manifest_tmp
  local publish_status=0 rollback_status=0
  local -a receipts=() policies=() destinations=() expected_files=() backups=()
  local -a operations=() publishers=() modes=() changed=()
  local -a link_paths=() link_targets=() link_operations=() link_quarantines=()
  local -A seen_destinations=() seen_links=()
  _dev_profile_state_single_writer || return 1
  root=$(_dev_profile_state_root) || return 1
  [[ -e $root || -L $root ]] || return 0
  _dev_profile_state_private_directory "$root" || return 1
  _dev_profile_state_retirement_recover "$root" || return 1
  _dev_profile_state_recover_all_pending "$root" || return 1
  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  receipts=("$root"/*.json)
  ((nullglob_was_set == 1)) || shopt -u nullglob
  ((${#receipts[@]} > 0)) || return 0

  retired_dir=$root/.retiring
  (umask 077 && mkdir "$retired_dir") || return 1
  configs_log=$retired_dir/configs.jsonl
  links_log=$retired_dir/links.jsonl
  receipts_log=$retired_dir/receipts.jsonl
  manifest=$retired_dir/manifest.json
  : >"$configs_log"
  : >"$links_log"
  : >"$receipts_log"
  chmod 0600 "$configs_log" "$links_log" "$receipts_log" || {
    _dev_profile_state_retirement_dir_clear "$retired_dir" || true
    return 1
  }

  # Compute and render every replacement before changing any destination. A
  # downgrade can touch several independent applications, so a late conflict
  # or renderer failure must leave the entire active profile intact.
  for receipt in "${receipts[@]}"; do
    [[ ${receipt##*/} =~ ^[0-9a-f]{40}\.json$ ]] || {
      publish_status=1
      break
    }
    _dev_profile_state_receipt_safe "$receipt" || publish_status=1
    ((publish_status == 0)) || break
    policy=$(jq -r .policy "$receipt") || publish_status=1
    format=$(jq -r .format "$receipt") || publish_status=1
    destination=$(jq -r .path "$receipt") || publish_status=1
    publisher=$(jq -r .publisher "$receipt") || publish_status=1
    ((publish_status == 0)) || break
    case $format in json | jsonc | yaml | toml) ;; *)
      publish_status=1
      break
      ;;
    esac
    _dev_profile_state_publisher_valid "$policy" "$publisher" || {
      publish_status=1
      break
    }
    _dev_profile_state_path_allowed "$policy" "$destination" || {
      publish_status=1
      break
    }
    key=$(_dev_profile_state_key "$policy" "$destination") || {
      publish_status=1
      break
    }
    [[ $receipt == "$root/$key.json" ]] || {
      publish_status=1
      break
    }
    [[ -z ${seen_destinations[$destination]+x} ]] || {
      publish_status=1
      break
    }
    seen_destinations[$destination]=1
    policies+=("$policy")
    destinations+=("$destination")
    publishers+=("$publisher")
    changed+=(0)
    index=$((${#destinations[@]} - 1))
    before=$retired_dir/config-$index.before
    applied=$retired_dir/config-$index.applied-receipt
    links=$retired_dir/config-$index.links
    _dev_profile_state_receipt_load \
      "$receipt" "$policy" "$format" "$destination" "$publisher" \
      "$before" "$applied" "$links" ||
      publish_status=1
    ((publish_status == 0)) || break
    before_exists=$REPLY
    while IFS=$'\t' read -r link_path link_target; do
      [[ -z ${seen_links[$link_path]+x} ]] || {
        publish_status=1
        break
      }
      seen_links[$link_path]=1
      link_paths+=("$link_path")
      link_targets+=("$link_target")
      if [[ -L $link_path && $(readlink "$link_path") == "$link_target" ]]; then
        link_operations+=(delete)
        quarantine_dir=${link_path%/*}/.dot-profile-retire.$key-${#link_paths[@]}
        [[ ! -e $quarantine_dir && ! -L $quarantine_dir ]] || {
          publish_status=1
          break
        }
        link_quarantines+=("$quarantine_dir/${link_path##*/}")
      else
        link_operations+=(none)
        link_quarantines+=("")
      fi
    done < <(jq -r '.[] | [.path, .target] | @tsv' "$links")
    ((publish_status == 0)) || break
    if [[ ! -e $destination && ! -L $destination ]]; then
      operations+=(none)
      expected_files+=("")
      backups+=("")
      modes+=("")
      continue
    fi
    [[ -f $destination && ! -L $destination ]] || {
      publish_status=1
      break
    }
    current=$retired_dir/config-$index.current
    output=$retired_dir/config-$index.output
    _dev_profile_state_json "$format" "$destination" "$current" ||
      publish_status=1
    ((publish_status == 0)) || break
    python3 "$(_dev_profile_state_engine)" reverse --policy "$policy" \
      --before "$before" --applied "$applied" --current "$current" \
      --output "$output" || publish_status=1
    ((publish_status == 0)) || break
    mode=$(stat -c '%a' "$destination" 2>/dev/null ||
      stat -f '%Lp' "$destination") || {
      publish_status=1
      break
    }
    [[ $mode =~ ^[0-7]{3,4}$ ]] || {
      publish_status=1
      break
    }
    backup=$retired_dir/config-$index.backup
    backups+=("$backup")
    if ! cp -- "$destination" "$backup" || ! chmod 0600 "$backup"; then
      publish_status=1
      break
    fi
    modes+=("$mode")
    if [[ $before_exists == false ]] &&
      _dev_profile_state_document_empty "$policy" "$output"; then
      operations+=(delete)
      expected_files+=("")
    else
      expected=$retired_dir/config-$index.expected
      _dev_profile_state_render "$format" "$output" "$expected" || {
        publish_status=1
        break
      }
      operations+=(replace)
      expected_files+=("$REPLY")
    fi
  done

  if ((publish_status != 0)); then
    _dev_profile_state_retirement_dir_clear "$retired_dir" || true
    return 1
  fi

  for index in "${!destinations[@]}"; do
    jq -cn \
      --arg policy "${policies[index]}" \
      --arg path "${destinations[index]}" \
      --arg publisher "${publishers[index]}" \
      --arg operation "${operations[index]}" \
      --arg mode "${modes[index]}" \
      --arg backup "${backups[index]}" \
      --arg expected "${expected_files[index]}" \
      '{policy: $policy, path: $path, publisher: $publisher,
        operation: $operation, mode: $mode, backup: $backup,
        expected: $expected}' >>"$configs_log" || publish_status=1
  done
  for link_index in "${!link_paths[@]}"; do
    [[ ${link_operations[link_index]} == delete ]] || continue
    jq -cn --arg path "${link_paths[link_index]}" \
      --arg target "${link_targets[link_index]}" \
      --arg quarantine "${link_quarantines[link_index]}" \
      '{path: $path, target: $target, quarantine: $quarantine}' \
      >>"$links_log" || publish_status=1
  done
  for receipt in "${receipts[@]}"; do
    jq -cn --arg path "$receipt" '$path' >>"$receipts_log" || publish_status=1
  done
  manifest_tmp=$retired_dir/manifest.tmp
  if ! jq -n --sort-keys --slurpfile configs "$configs_log" \
    --slurpfile links "$links_log" --slurpfile receipts "$receipts_log" \
    '{version: 1, phase: "publishing", configs: $configs,
      links: $links, receipts: $receipts}' >"$manifest_tmp" ||
    ! chmod 0600 "$manifest_tmp" || ! mv -f -- "$manifest_tmp" "$manifest"; then
    publish_status=1
  fi
  if ((publish_status != 0)); then
    _dev_profile_state_retirement_dir_clear "$retired_dir" || true
    return 1
  fi

  for index in "${!destinations[@]}"; do
    case ${operations[index]} in
      none) ;;
      delete)
        if rm -f -- "${destinations[index]}"; then
          changed[index]=1
        else
          publish_status=1
        fi
        ;;
      replace)
        if _dev_profile_state_restore_file "${expected_files[index]}" \
          "${destinations[index]}" "${modes[index]}" \
          "${publishers[index]}"; then
          changed[index]=1
        else
          publish_status=1
        fi
        ;;
    esac
    ((publish_status == 0)) || break
  done

  if ((publish_status == 0)); then
    for link_index in "${!link_paths[@]}"; do
      [[ ${link_operations[link_index]} == delete ]] || continue
      link_path=${link_paths[link_index]}
      link_target=${link_targets[link_index]}
      quarantine=${link_quarantines[link_index]}
      quarantine_dir=${quarantine%/*}
      mkdir "$quarantine_dir" || {
        publish_status=1
        break
      }
      # Rename first, then inspect the exact directory entry moved. This avoids
      # a check-then-unlink race that could otherwise delete a replacement file.
      if ! mv -- "$link_path" "$quarantine" 2>/dev/null; then
        rmdir "$quarantine_dir" 2>/dev/null || true
        if [[ ! -e $link_path && ! -L $link_path ]]; then
          continue
        fi
        publish_status=1
        break
      fi
      link_quarantines[link_index]=$quarantine
      if [[ ! -L $quarantine || $(readlink "$quarantine") != "$link_target" ]]; then
        if [[ ! -e $link_path && ! -L $link_path ]] &&
          mv -- "$quarantine" "$link_path"; then
          link_quarantines[link_index]=
          rmdir "$quarantine_dir" 2>/dev/null || true
          publish_status=1
          break
        fi
        publish_status=1
        break
      fi
    done
  fi

  if ((publish_status == 0)); then
    _dev_profile_state_retirement_manifest_update "$manifest" committed ||
      publish_status=1
  fi

  if ((publish_status != 0)); then
    # Restore managed links before their registry/configuration. This keeps a
    # failed downgrade from leaving a registry entry that points nowhere.
    for ((rollback_index = ${#link_paths[@]} - 1; rollback_index >= 0; rollback_index--)); do
      [[ ${link_operations[rollback_index]} == delete ]] || continue
      link_path=${link_paths[rollback_index]}
      link_target=${link_targets[rollback_index]}
      quarantine=${link_quarantines[rollback_index]}
      if [[ -n $quarantine && (-e $quarantine || -L $quarantine) ]]; then
        if [[ ! -e $link_path && ! -L $link_path ]] &&
          mv -- "$quarantine" "$link_path"; then
          link_quarantines[rollback_index]=
          rmdir "${quarantine%/*}" 2>/dev/null || rollback_status=1
        else
          rollback_status=1
        fi
      elif [[ -L $link_path && $(readlink "$link_path") == "$link_target" ]]; then
        continue
      else
        rollback_status=1
      fi
    done
    # Published replacements are atomic per file. Roll back every destination
    # already changed so callers never observe a partially retired profile.
    for ((rollback_index = ${#destinations[@]} - 1; rollback_index >= 0; rollback_index--)); do
      [[ ${changed[rollback_index]} == 1 ]] || continue
      if ! _dev_profile_state_restore_file "${backups[rollback_index]}" \
        "${destinations[rollback_index]}" "${modes[rollback_index]}" \
        "${publishers[rollback_index]}"; then
        rollback_status=1
      fi
    done
    if ((rollback_status != 0)); then
      printf 'dotfiles-dev: profile retirement rollback failed; recovery files remain beside affected destinations\n' >&2
      return 1
    fi
    _dev_profile_state_retirement_dir_clear "$retired_dir" || return 1
    return 1
  fi

  if ! _dev_profile_state_retirement_recover "$root"; then
    printf 'dotfiles-dev: profile retirement committed; receipt cleanup remains pending\n' >&2
    return 1
  fi
}
