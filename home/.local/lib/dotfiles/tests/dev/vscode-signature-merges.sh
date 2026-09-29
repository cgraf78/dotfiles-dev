# shellcheck shell=bash
# VS Code merge-hook unchanged-update signature lifecycle, split from
# vscode-merges.sh so `dot test` overlaps these ~16 full merges with that
# suite's serial chain. The cases compare only against the shared fixture and
# state captured right after its full merge, so they need no other part of
# that chain.

# The shared fixture in vscode-merges-setup.sh assigns vscode_home,
# vscode_bin, vscode_mv_log, and the receipt and title expectations; a
# standalone check cannot see those writes.
# shellcheck disable=SC2154

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"
# shellcheck source-path=SCRIPTDIR source=vscode-merges-setup.sh
. "${BASH_SOURCE[0]%/*}/vscode-merges-setup.sh"

dot_dev_vscode_signature_merges_test() {
  _dev_merges_setup || return
  echo "=== VS Code merge signature ==="

  if command -v jq >/dev/null 2>&1; then
    _dev_vscode_merges_fixture
    # The skip and reconverge cases must preserve user-owned bindings, so fail
    # loudly if the fixture ever stops seeding them.
    _assert_contains "vscode signature: fixture seeds user-owned keybindings" \
      'terminalFocus && localTerminalMode' \
      "$(cat "$vscode_home/.config/Code/User/keybindings.json" 2>/dev/null)"
    _dev_vscode_fixture_merge
    _dev_vscode_fixture_expectations
    vscode_settings_before_repeat=$(cat "$vscode_home/.config/Code/User/settings.json")
    vscode_keybindings_before_repeat=$(cat "$vscode_home/.config/Code/User/keybindings.json")

    # Unchanged-update fast path. Each run counts settings-source resolution,
    # which only the full merge performs, so a zero count proves the skip.
    vscode_signature_file=$vscode_home/.cache/dot/merge-vscode-signature-v1
    _vscode_signature_merge() {
      local count_file=$1
      shift
      : >"$count_file"
      # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
      env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
        DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" \
        VSCODE_SETTINGS_SOURCE_COUNT="$count_file" "$@" bash -c '
        set -uo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { return 1; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        dot_hook_log() { printf "%s\n" "$*"; }
        _vscode_variants() {
          printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
        }
        settings_sources_definition=$(declare -f _vscode_settings_sources)
        eval "${settings_sources_definition/_vscode_settings_sources/_vscode_settings_sources_original}"
        _vscode_settings_sources() {
          printf "called\n" >>"$VSCODE_SETTINGS_SOURCE_COUNT"
          _vscode_settings_sources_original
        }
        eval "${VSCODE_SIGNATURE_INJECT:-}"
        merge
      '
    }
    _vscode_signature_full_merges() {
      wc -l <"$1" | tr -d ' '
    }

    vscode_signature_count=$(_tmpfile)
    vscode_settings_receipt_converged=$(cat "$vscode_receipt_root/$vscode_settings_key.json")
    _assert_file_exists "vscode signature: a successful merge records a signature" \
      "$vscode_signature_file"
    vscode_signature_perms=$(stat -c '%a' "$vscode_signature_file" 2>/dev/null ||
      stat -f '%Lp' "$vscode_signature_file" 2>/dev/null)
    _assert_eq "vscode signature: signature file is private" \
      "600" "$vscode_signature_perms"
    vscode_signature_output=$(_vscode_signature_merge "$vscode_signature_count" 2>&1)
    _assert_eq "vscode signature: unchanged update skips the full merge" \
      "0" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    _assert_contains "vscode signature: skipped merge still reports VS Code" \
      "VS Code" "$vscode_signature_output"
    _assert_file_content "vscode signature: skipped merge leaves settings untouched" \
      "$vscode_settings_before_repeat" \
      "$vscode_home/.config/Code/User/settings.json"
    _assert_file_content "vscode signature: skipped merge leaves keybindings untouched" \
      "$vscode_keybindings_before_repeat" \
      "$vscode_home/.config/Code/User/keybindings.json"
    _assert_file_content "vscode signature: skipped merge leaves receipts untouched" \
      "$vscode_settings_receipt_converged" \
      "$vscode_receipt_root/$vscode_settings_key.json"

    _vscode_signature_merge "$vscode_signature_count" DOT_FORCE=1 >/dev/null 2>&1
    _assert_eq "vscode signature: dot update -f forces the full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"

    vscode_signature_probe=$vscode_home/.config/dot/merge-hooks.d/vscode/settings.d/99-signature-probe.json
    printf '{"dotfiles.signatureProbe": true}\n' >"$vscode_signature_probe"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: new source fragment forces the full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    _assert_eq "vscode signature: new source fragment is applied" \
      "true" \
      "$(jq -r '.["dotfiles.signatureProbe"] // empty' "$vscode_home/.config/Code/User/settings.json")"
    printf '{"dotfiles.signatureProbe": false}\n' >"$vscode_signature_probe"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: edited source fragment is applied" \
      "false" \
      "$(jq -r '.["dotfiles.signatureProbe"] | tostring' "$vscode_home/.config/Code/User/settings.json")"
    rm -f "$vscode_signature_probe"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: removed source fragment is retired" \
      "absent" \
      "$(jq -r 'if has("dotfiles.signatureProbe") then "present" else "absent" end' "$vscode_home/.config/Code/User/settings.json")"

    vscode_signature_tampered=$(_tmpfile)
    jq '.["window.title"] = "tampered"' "$vscode_home/.config/Code/User/settings.json" \
      >"$vscode_signature_tampered"
    cp "$vscode_signature_tampered" "$vscode_home/.config/Code/User/settings.json"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: edited destination forces the full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    _assert_eq "vscode signature: edited destination reconverges" \
      "$vscode_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.config/Code/User/settings.json")"

    printf 'corrupt\n' >"$vscode_signature_file"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: corrupt signature forces the full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: full merge repairs a corrupt signature" \
      "0" "$(_vscode_signature_full_merges "$vscode_signature_count")"

    vscode_signature_link=
    for vscode_signature_entry in "$vscode_home"/.vscode/extensions/*; do
      if [[ -L $vscode_signature_entry ]]; then
        vscode_signature_link=$vscode_signature_entry
        break
      fi
    done
    if [[ -n $vscode_signature_link ]]; then
      vscode_signature_link_target=$(readlink "$vscode_signature_link")
      rm -f "$vscode_signature_link"
      _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
      _assert_eq "vscode signature: removed extension link forces the full merge" \
        "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
      _assert_eq "vscode signature: removed extension link is restored" \
        "$vscode_signature_link_target" "$(readlink "$vscode_signature_link" 2>/dev/null)"
    else
      _fail "vscode signature: fixture exposes a local extension link"
    fi

    # Another program (Settings Sync, the editor) may rewrite a destination
    # after its transaction commits but before the signature is recorded. The
    # signature records the committed bytes, so the next update still repairs.
    # shellcheck disable=SC2016 # Evaluated inside the fixture shell.
    _vscode_signature_merge "$vscode_signature_count" DOT_FORCE=1 \
      VSCODE_SIGNATURE_INJECT='
        mcp_ready_definition=$(declare -f _vscode_signature_mcp_ready)
        eval "${mcp_ready_definition/_vscode_signature_mcp_ready/_vscode_signature_mcp_ready_original}"
        _vscode_signature_mcp_ready() {
          jq ".[\"window.title\"] = \"synced-late\"" "$HOME/.config/Code/User/settings.json" \
            >"$HOME/late-sync.json" && mv -f "$HOME/late-sync.json" "$HOME/.config/Code/User/settings.json"
          _vscode_signature_mcp_ready_original
        }' >/dev/null 2>&1
    _assert_eq "vscode signature: late external write survives the recording merge" \
      "synced-late" \
      "$(jq -r '.["window.title"]' "$vscode_home/.config/Code/User/settings.json")"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: late external write forces the next full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    _assert_eq "vscode signature: late external write is repaired" \
      "$vscode_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.config/Code/User/settings.json")"

    # Token generation failure is a warning, so its degraded result must not
    # be cached: the next update has to retry generation.
    vscode_signature_token=$vscode_home/.local/state/dot/vscode-mcp-auth-token
    vscode_signature_token_saved=$(_tmpfile)
    cp "$vscode_signature_token" "$vscode_signature_token_saved"
    rm -f "$vscode_signature_token"
    _vscode_signature_merge "$vscode_signature_count" \
      VSCODE_SIGNATURE_INJECT='_vscode_mcp_auth_generate_token() { return 1; }' \
      >/dev/null 2>&1
    _assert_file_missing "vscode signature: failed token generation records no signature" \
      "$vscode_signature_file"
    # Restore the original token so later fixtures keep their settings bytes.
    cp "$vscode_signature_token_saved" "$vscode_signature_token"
    chmod 600 "$vscode_signature_token"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: update after a token failure runs the full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    _assert_file_content "vscode signature: full merge restores the token setting" \
      "$vscode_settings_before_repeat" \
      "$vscode_home/.config/Code/User/settings.json"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: converged token state skips again" \
      "0" "$(_vscode_signature_full_merges "$vscode_signature_count")"

    # Transactions refuse a symlinked destination even when its bytes match,
    # so an unchanged-looking symlink must not satisfy the signature.
    vscode_signature_real=$vscode_home/settings-real.json
    cp "$vscode_home/.config/Code/User/settings.json" "$vscode_signature_real"
    ln -sf "$vscode_signature_real" "$vscode_home/.config/Code/User/settings.json"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: symlinked destination forces the full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    rm -f "$vscode_home/.config/Code/User/settings.json"
    mv "$vscode_signature_real" "$vscode_home/.config/Code/User/settings.json"

    # An unsafe receipt is rejected by transactions, so it must not match.
    chmod 644 "$vscode_receipt_root/$vscode_settings_key.json"
    _vscode_signature_merge "$vscode_signature_count" >/dev/null 2>&1
    _assert_eq "vscode signature: unsafe receipt mode forces the full merge" \
      "1" "$(_vscode_signature_full_merges "$vscode_signature_count")"
    chmod 600 "$vscode_receipt_root/$vscode_settings_key.json"
    _vscode_signature_merge "$vscode_signature_count" DOT_FORCE=1 >/dev/null 2>&1
  else
    echo "  SKIP: VS Code merge signature assertions (jq unavailable)"
  fi
  _test_summary
}
