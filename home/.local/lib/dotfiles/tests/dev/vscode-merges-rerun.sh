# shellcheck shell=bash
# VS Code merge-hook reruns, split from vscode-merges.sh so `dot test`
# overlaps them with that suite's serial chain: a forced repeat merge, live
# projection, signature, and keybinding failures, variant failure
# aggregation, and shared-config reconciliation. Every case starts from the
# fixture's first full merge, which this suite repeats exactly; the failure
# cases restore that state, and none of the chain's later steps reads what
# these merges leave behind.

# The shared fixture in vscode-merges-setup.sh assigns vscode_home,
# vscode_bin, vscode_mv_log, and the receipt and title expectations; a
# standalone check cannot see those writes.
# shellcheck disable=SC2154

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"
# shellcheck source-path=SCRIPTDIR source=vscode-merges-setup.sh
. "${BASH_SOURCE[0]%/*}/vscode-merges-setup.sh"

dot_dev_vscode_merges_rerun_test() {
  _dev_vscode_merges_setup || return
  echo "=== VS Code merge reruns ==="

  if command -v jq >/dev/null 2>&1; then
    _dev_vscode_merges_fixture
    _dev_vscode_fixture_merge
    _dev_vscode_fixture_expectations
    # The repeat merge checks that the token stays stable;
    # dev-vscode-merges-test asserts the post-merge token itself.
    vscode_mcp_token_setting=$(jq -r '.["vscode-mcp-server.authToken"] // empty' "$vscode_home/.config/Code/User/settings.json")

    vscode_settings_before_repeat=$(cat "$vscode_home/.config/Code/User/settings.json")
    vscode_keybindings_before_repeat=$(cat "$vscode_home/.config/Code/User/keybindings.json")
    vscode_settings_source_count=$vscode_home/settings-source-count
    vscode_checkrun_capability_count=$vscode_home/checkrun-capability-count
    vscode_checkrun_schema_count=$vscode_home/checkrun-schema-count
    vscode_keybinding_family_count=$vscode_home/keybinding-family-count
    : >"$vscode_settings_source_count"
    : >"$vscode_checkrun_capability_count"
    : >"$vscode_checkrun_schema_count"
    : >"$vscode_keybinding_family_count"
    # Force the full merge: these counters guard its once-per-config
    # resolution, which an unchanged update would otherwise skip entirely.
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_FORCE=1 \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" \
      VSCODE_SETTINGS_SOURCE_COUNT="$vscode_settings_source_count" \
      VSCODE_CHECKRUN_CAPABILITY_COUNT="$vscode_checkrun_capability_count" \
      VSCODE_CHECKRUN_SCHEMA_COUNT="$vscode_checkrun_schema_count" \
      VSCODE_KEYBINDING_FAMILY_COUNT="$vscode_keybinding_family_count" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      settings_sources_definition=$(declare -f _vscode_settings_sources)
      eval "${settings_sources_definition/_vscode_settings_sources/_vscode_settings_sources_original}"
      _vscode_settings_sources() {
        printf "called\n" >>"$VSCODE_SETTINGS_SOURCE_COUNT"
        _vscode_settings_sources_original
      }
      checkrun_capabilities_definition=$(declare -f _vscode_checkrun_capabilities)
      eval "${checkrun_capabilities_definition/_vscode_checkrun_capabilities/_vscode_checkrun_capabilities_original}"
      _vscode_checkrun_capabilities() {
        printf "called\n" >>"$VSCODE_CHECKRUN_CAPABILITY_COUNT"
        _vscode_checkrun_capabilities_original "$@"
      }
      checkrun_schema_definition=$(declare -f _vscode_checkrun_schema_config)
      eval "${checkrun_schema_definition/_vscode_checkrun_schema_config/_vscode_checkrun_schema_config_original}"
      _vscode_checkrun_schema_config() {
        printf "called\n" >>"$VSCODE_CHECKRUN_SCHEMA_COUNT"
        _vscode_checkrun_schema_config_original "$@"
      }
      keybinding_families_definition=$(declare -f _vscode_keybinding_families)
      eval "${keybinding_families_definition/_vscode_keybinding_families/_vscode_keybinding_families_original}"
      _vscode_keybinding_families() {
        printf "called\n" >>"$VSCODE_KEYBINDING_FAMILY_COUNT"
        _vscode_keybinding_families_original "$@"
      }
      merge
    '
    _assert_eq "vscode mcp auth: token is stable across repeat merges" \
      "$vscode_mcp_token_setting" \
      "$(jq -r '.["vscode-mcp-server.authToken"] // empty' "$vscode_home/.config/Code/User/settings.json")"
    _assert_file_content "vscode settings: repeat merge is byte-identical" \
      "$vscode_settings_before_repeat" \
      "$vscode_home/.config/Code/User/settings.json"
    _assert_file_content "vscode keybindings: repeat merge is byte-identical" \
      "$vscode_keybindings_before_repeat" \
      "$vscode_home/.config/Code/User/keybindings.json"
    _assert_eq "vscode warm merge: settings sources resolve once per config" \
      "1" "$(wc -l <"$vscode_settings_source_count" | tr -d ' ')"
    _assert_eq "vscode warm merge: Checkrun capabilities project once per config" \
      "1" "$(wc -l <"$vscode_checkrun_capability_count" | tr -d ' ')"
    _assert_eq "vscode warm merge: Checkrun schemas project once per config" \
      "1" "$(wc -l <"$vscode_checkrun_schema_count" | tr -d ' ')"
    _assert_eq "vscode warm merge: keybinding families aggregate once per config" \
      "1" "$(wc -l <"$vscode_keybinding_family_count" | tr -d ' ')"

    vscode_signature_file=$vscode_home/.cache/dot/merge-vscode-signature-v1
    vscode_settings_receipt_before=$(cat "$vscode_receipt_root/$vscode_settings_key.json")
    vscode_projection_failure_tmp=$(_tmpdir)
    vscode_projection_failure_rc=0
    # The injected failure is an in-process function override that no file
    # signature can observe, so force the full merge past the fast path.
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      TMPDIR="$vscode_projection_failure_tmp" DOT_FORCE=1 \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      settings_apply_definition=$(declare -f _vscode_apply_settings_projection)
      eval "${settings_apply_definition/_vscode_apply_settings_projection/_vscode_apply_settings_projection_original}"
      _vscode_apply_settings_projection() {
        return 1
      }
      merge
    ' >/dev/null 2>&1 || vscode_projection_failure_rc=$?
    _assert_eq "vscode settings: live projection failure propagates" \
      "1" "$vscode_projection_failure_rc"
    _assert_file_content "vscode settings: live projection failure restores prior settings" \
      "$vscode_settings_before_repeat" \
      "$vscode_home/.config/Code/User/settings.json"
    _assert_file_content "vscode settings: live projection failure preserves receipt" \
      "$vscode_settings_receipt_before" \
      "$vscode_receipt_root/$vscode_settings_key.json"
    _assert_eq "vscode settings: live projection failure cleans transaction state" \
      "0" \
      "$(find "$vscode_projection_failure_tmp" -maxdepth 1 -type d \
        -name 'dev-profile-state.*' -print | wc -l | tr -d ' ')"

    # Only a fully successful merge may record a signature; otherwise the next
    # update would skip a destination that never converged.
    rm -f "$vscode_signature_file"
    vscode_signature_failure_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      _vscode_apply_settings_projection() {
        return 1
      }
      merge
    ' >/dev/null 2>&1 || vscode_signature_failure_rc=$?
    _assert_eq "vscode signature: failed merge reports failure" \
      "1" "$vscode_signature_failure_rc"
    _assert_file_missing "vscode signature: failed merge records no signature" \
      "$vscode_signature_file"

    vscode_valid_keybindings=$(_tmpfile)
    cp "$vscode_home/.config/Code/User/keybindings.json" \
      "$vscode_valid_keybindings"
    printf '[invalid\n' \
      >"$vscode_home/.config/Code/User/keybindings.json"
    vscode_invalid_keybindings_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/.config/Code/User"
      }
      merge
    ' >/dev/null 2>&1 || vscode_invalid_keybindings_rc=$?
    _assert_eq "vscode keybindings: reconciliation failure propagates" \
      "1" "$vscode_invalid_keybindings_rc"
    cp "$vscode_valid_keybindings" \
      "$vscode_home/.config/Code/User/keybindings.json"

    # The real merge runner does not make errexit a dependable contract. Model
    # two variants without it so a later success cannot erase an earlier
    # reconciliation failure from the hook's explicit aggregate status.
    vscode_variant_failure_home=$(_tmpdir)
    mkdir -p \
      "$vscode_variant_failure_home/.config/dot/merge-hooks.d" \
      "$vscode_variant_failure_home/failing/User" \
      "$vscode_variant_failure_home/succeeding/User"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_variant_failure_home/.config/dot/merge-hooks.d/vscode"
    printf '[invalid\n' \
      >"$vscode_variant_failure_home/failing/User/keybindings.json"
    printf '[]\n' \
      >"$vscode_variant_failure_home/succeeding/User/keybindings.json"
    vscode_variant_failure_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_variant_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      # The hook installs the real host presence probe. This fixture
      # deliberately has no editor marker because it exercises variant
      # failure aggregation, so select the hook explicitly rather than
      # depending on an ambient VS Code binary from the CI host.
      _vscode_present() { return 0; }
      _vscode_local_extensions() { :; }
      _vscode_variants() {
        printf "%s\t%s\n" \
          "$HOME/failing/extensions" "$HOME/failing/User" \
          "$HOME/succeeding/extensions" "$HOME/succeeding/User"
      }
      merge
    ' >/dev/null 2>&1 || vscode_variant_failure_rc=$?
    _assert_eq "vscode keybindings: an earlier variant failure survives a later success" \
      "1" "$vscode_variant_failure_rc"
    _assert_eq "vscode keybindings: later variant still reconciles after an earlier failure" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus && !termnav.nvimFocused"
      )] | length' \
        "$vscode_variant_failure_home/succeeding/User/keybindings.json")"

    # Extension hosts are independent, but their user config directory need
    # not be. Stable and insiders builds can share one settings/keybindings
    # target, so exercise the complete merge dispatcher: every extension host
    # must still be visited, while only the last declaration for a shared
    # config target may perform the expensive reconciliation.
    vscode_shared_config_log=$(_tmpfile)
    # shellcheck disable=SC2016 # The inner shell expands its fixture variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" \
      VSCODE_SHARED_CONFIG_LOG="$vscode_shared_config_log" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_install_declared_extensions() { :; }
      _merge_vscode_remote_configs_tracked() { :; }
      _vscode_local_extensions() { :; }
      _vscode_variants() {
        printf "%s\t%s\t%s\n" \
          "$HOME/stable/extensions" "$HOME/shared/User" "old-policy" \
          "$HOME/insiders/extensions" "$HOME/shared/User" "final-policy" \
          "$HOME/other/extensions" "$HOME/other/User" "other-policy" \
          "$HOME/remote/extensions" "" "extension-only"
      }
      _prune_vscode_local_extensions() {
        printf "extension\t%s\n" "$1" >>"$VSCODE_SHARED_CONFIG_LOG"
      }
      _merge_vscode_config_tracked() {
        printf "config\t%s\t%s\n" "$1" "$2" >>"$VSCODE_SHARED_CONFIG_LOG"
      }
      merge
    '
    _assert_file_content "vscode variants: shared config reconciles once with final policy" \
      "$(printf '%s\n' \
        "extension	$vscode_home/stable/extensions/extensions.json" \
        "extension	$vscode_home/insiders/extensions/extensions.json" \
        "extension	$vscode_home/other/extensions/extensions.json" \
        "extension	$vscode_home/remote/extensions/extensions.json" \
        "config	$vscode_home/shared/User	final-policy" \
        "config	$vscode_home/other/User	other-policy")" \
      "$vscode_shared_config_log"

    # The dispatcher test above proves call selection. This integration check
    # proves the stronger premise behind it: replaying an earlier policy before
    # the final no-sley policy produces byte-identical managed config to running
    # that final policy alone. A future additive-only merge would fail here.
    vscode_shared_sequence_dir="$vscode_home/shared-sequence/User"
    vscode_shared_final_dir="$vscode_home/shared-final/User"
    mkdir -p "$vscode_shared_sequence_dir" "$vscode_shared_final_dir"
    # shellcheck disable=SC2016 # The inner shell expands its fixture variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" \
      VSCODE_SHARED_SEQUENCE_DIR="$vscode_shared_sequence_dir" \
      VSCODE_SHARED_FINAL_DIR="$vscode_shared_final_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_config "$VSCODE_SHARED_SEQUENCE_DIR" ""
      _merge_vscode_config "$VSCODE_SHARED_SEQUENCE_DIR" "no-sley"
      _merge_vscode_config "$VSCODE_SHARED_FINAL_DIR" "no-sley"
    '
    _assert_file_content "vscode variants: final-only settings equal replayed shared policy" \
      "$(cat "$vscode_shared_sequence_dir/settings.json")" \
      "$vscode_shared_final_dir/settings.json"
    _assert_file_content "vscode variants: final-only keybindings equal replayed shared policy" \
      "$(cat "$vscode_shared_sequence_dir/keybindings.json")" \
      "$vscode_shared_final_dir/keybindings.json"
    # This variant deliberately installs no local extensions. The static
    # clauses must encode VS Code's documented undefined-context behavior:
    # negation selects the host route while the positive nvim route is dormant.
    # Actual context evaluation is covered by live acceptance with Termnav
    # absent; these assertions intentionally check the generated contract.
    _assert_file_missing "vscode keybindings: extensionless variant has no local extension registry" \
      "$vscode_variant_failure_home/succeeding/extensions/extensions.json"
    _assert_file_missing "vscode keybindings: extensionless variant has no Termnav symlink" \
      "$vscode_variant_failure_home/succeeding/extensions/termnav-0.3.0"
    _assert_eq "vscode keybindings: extensionless config includes negated host fallback" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus && !termnav.nvimFocused"
      )] | length' \
        "$vscode_variant_failure_home/succeeding/User/keybindings.json")"
    _assert_eq "vscode keybindings: extensionless config gates nvim route positively" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.terminal.sendSequence"
        and .when == "terminalFocus && termnav.nvimFocused"
      )] | length' \
        "$vscode_variant_failure_home/succeeding/User/keybindings.json")"
  else
    echo "  SKIP: VS Code merge rerun assertions (jq unavailable)"
  fi
  _test_summary
}
