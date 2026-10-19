# shellcheck shell=bash
# VS Code merge-hook provider cases, split from vscode-merges.sh so
# `dot test` overlaps them with that suite's serial chain: a server-only
# remote host's Checkrun schema projection, and Termnav provider resolution
# for local extensions. Each case builds its own HOME and borrows only the
# fixture's command shims and schema policy, never its merged state.

# The shared fixture in vscode-merges-setup.sh assigns vscode_home,
# vscode_bin, vscode_mv_log, and the receipt and title expectations; a
# standalone check cannot see those writes.
# shellcheck disable=SC2154

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"
# shellcheck source-path=SCRIPTDIR source=vscode-merges-setup.sh
. "${BASH_SOURCE[0]%/*}/vscode-merges-setup.sh"

dot_dev_vscode_merges_providers_test() {
  _dev_vscode_merges_setup || return
  echo "=== VS Code merge providers ==="

  if command -v jq >/dev/null 2>&1; then
    _dev_vscode_merges_fixture

    vscode_server_only_home=$(_tmpdir)
    mkdir -p "$vscode_server_only_home/.vscode-server"
    # The mock shdeps resolves Checkrun's schema policy under $HOME.
    cp "$vscode_home/checkrun-schema-policy.py" "$vscode_server_only_home/"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_server_only_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_VSCODE_HOSTNAME="server-only-host" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      merge
    '
    vscode_server_only_title_expected="server-only-host\${separator}\${activeRepositoryBranchName}\${separator}\${rootNameShort}\${separator}\${activeEditorShort}"
    _assert_eq "vscode remote settings: server root works without detected variants" \
      "$vscode_server_only_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_server_only_home/.vscode-server/data/Machine/settings.json")"

    # Remote windows run the schema language servers on this host, so its
    # machine settings must carry this host's schema projection: the client's
    # user settings name client paths (/Users/... from a Mac) that are absent here.
    vscode_server_only_settings="$vscode_server_only_home/.vscode-server/data/Machine/settings.json"
    _vscode_server_only_merge() {
      # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
      env HOME="$vscode_server_only_home" REAL_HOME="$REAL_HOME" PATH="$1" \
        DOT_TEST_MV_LOG="$vscode_mv_log" \
        DOT_TEST_VSCODE_HOSTNAME="server-only-host" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { return 1; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        merge
      '
    }
    _assert_vscode_remote_schemas() {
      _assert_eq "vscode remote schemas: $1 JSON schemas use this host's projection" \
        '[{"fileMatch":[".sley/verify.json","**/.sley/verify.json"],"name":"Sley verify registry","url":"file:///mock/sley/verify.schema.json"}]' \
        "$(jq -c '.["json.schemas"]' "$vscode_server_only_settings")"
      _assert_eq "vscode remote schemas: $1 YAML schemas use this host's projection" \
        '{"https://example.invalid/docker-compose.schema.json":["docker-compose.yml","**/docker-compose.yml"]}' \
        "$(jq -c '.["yaml.schemas"]' "$vscode_server_only_settings")"
      _assert_eq "vscode remote schemas: $1 TOML schemas use this host's projection" \
        '{".*/pyproject\\.toml$":"https://example.invalid/pyproject.schema.json"}' \
        "$(jq -c '.["evenBetterToml.schema.associations"]' "$vscode_server_only_settings")"
    }
    _assert_vscode_remote_schemas "server-only host:"
    # Language associations and Sley formatter defaults are host-independent,
    # so they stay in the client's user settings.
    _assert_eq "vscode remote schemas: machine settings take only schema keys" \
      '[]' \
      "$(jq -c '[keys[] | select(. == "files.associations" or startswith("["))]' "$vscode_server_only_settings")"

    # A key set in the Remote settings tab is user-owned. Without Checkrun the
    # projection is empty, so the generated keys are withdrawn while user keys
    # and the window title stay; Checkrun's return restores the projection.
    jq '. + {"editor.fontSize": 13}' "$vscode_server_only_settings" >"$vscode_server_only_settings.tmp"
    mv "$vscode_server_only_settings.tmp" "$vscode_server_only_settings"
    # Shadow checkrun with a stub that fails like an unusable install: its
    # capabilities projection is then empty, exactly as when checkrun is
    # absent. Removing PATH directories instead would also drop tools the merge
    # needs, and mirroring them breaks launchers that load helpers relative to
    # their own location.
    vscode_no_checkrun_bin=$(_tmpdir)
    printf '#!/bin/sh\nexit 127\n' >"$vscode_no_checkrun_bin/checkrun"
    chmod +x "$vscode_no_checkrun_bin/checkrun"
    ln -s "$vscode_bin/shdeps" "$vscode_no_checkrun_bin/shdeps"
    ln -s "$vscode_bin/mv" "$vscode_no_checkrun_bin/mv"
    vscode_no_checkrun_path=$vscode_no_checkrun_bin:$PATH
    _vscode_server_only_merge "$vscode_no_checkrun_path"
    _assert_eq "vscode remote schemas: withdrawn when Checkrun is unusable" \
      '[]' \
      "$(jq -c '[keys[] | select(. == "json.schemas" or . == "yaml.schemas" or . == "evenBetterToml.schema.associations")]' "$vscode_server_only_settings")"
    _assert_eq "vscode remote schemas: withdrawal keeps the user's machine key" \
      '13' "$(jq -c '.["editor.fontSize"]' "$vscode_server_only_settings")"
    _assert_eq "vscode remote schemas: withdrawal keeps the window title" \
      "$vscode_server_only_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_server_only_settings")"
    _vscode_server_only_merge "$vscode_bin:$PATH"
    _assert_vscode_remote_schemas "restored:"
    _assert_eq "vscode remote schemas: restoration keeps the user's machine key" \
      '13' "$(jq -c '.["editor.fontSize"]' "$vscode_server_only_settings")"
    vscode_remote_schema_bytes=$(<"$vscode_server_only_settings")
    # Force the full merge: the signature fast path would skip it entirely.
    # Compare bytes and also check the mv log, since an atomic rewrite with
    # identical bytes would still reach VS Code's file watcher.
    : >"$vscode_mv_log"
    DOT_FORCE=1 _vscode_server_only_merge "$vscode_bin:$PATH"
    _assert_eq "vscode remote schemas: an unchanged full merge keeps the bytes" \
      "$vscode_remote_schema_bytes" "$(<"$vscode_server_only_settings")"
    _assert_not_contains "vscode remote schemas: an unchanged full merge rewrites nothing" \
      "$vscode_server_only_settings" "$(<"$vscode_mv_log")"

    # The schema keys are generated outright. json.schemas is an array with no
    # entry identity, so a hand-added entry cannot be kept beside the
    # projection; the hook replaces the whole value, and must never record the
    # generated entries as user-owned, or withdrawal would restore stale paths.
    jq '.["json.schemas"] += [{"name":"hand-added","url":"file:///hand.schema.json","fileMatch":["hand.json"]}]' \
      "$vscode_server_only_settings" >"$vscode_server_only_settings.tmp"
    mv "$vscode_server_only_settings.tmp" "$vscode_server_only_settings"
    DOT_FORCE=1 _vscode_server_only_merge "$vscode_bin:$PATH"
    _assert_vscode_remote_schemas "after a hand edit:"
    DOT_FORCE=1 _vscode_server_only_merge "$vscode_bin:$PATH"
    # A receipt's `before` is the user-owned baseline that deactivation and
    # withdrawal restore; it must hold the hand-made value at most, never the
    # generated projection.
    vscode_remote_receipts=$(find "$vscode_server_only_home/.local/state/dot/overlays/dev/merge-receipts-v1" \
      -name '*.json' -type f -exec jq -c --arg path "$vscode_server_only_settings" \
      'select(.path == $path)' {} + 2>/dev/null)
    _assert_eq "vscode remote schemas: one receipt tracks the remote settings" \
      '1' "$(jq -s 'length' <<<"$vscode_remote_receipts")"
    vscode_remote_receipt_before=$(jq -c '.before' <<<"$vscode_remote_receipts")
    _assert_not_contains "vscode remote schemas: receipts never record generated schema paths as user-owned" \
      'file:///mock/sley/verify.schema.json' "$vscode_remote_receipt_before"
    _vscode_server_only_merge "$vscode_no_checkrun_path"
    _assert_eq "vscode remote schemas: withdrawal after a hand edit restores no schema paths" \
      '[]' \
      "$(jq -c '[keys[] | select(. == "json.schemas" or . == "yaml.schemas" or . == "evenBetterToml.schema.associations")]' "$vscode_server_only_settings")"

    # A YAML schema dropped from the projection must not linger: yaml.schemas
    # is an object, which recursive merges would otherwise keep key by key.
    _vscode_server_only_merge "$vscode_bin:$PATH"
    sed 's|"https://example.invalid/docker-compose.schema.json"|"https://example.invalid/compose-v2.schema.json"|' \
      "$vscode_server_only_home/checkrun-schema-policy.py" \
      >"$vscode_server_only_home/checkrun-schema-policy.py.new"
    mv "$vscode_server_only_home/checkrun-schema-policy.py.new" \
      "$vscode_server_only_home/checkrun-schema-policy.py"
    chmod +x "$vscode_server_only_home/checkrun-schema-policy.py"
    _vscode_server_only_merge "$vscode_bin:$PATH"
    _assert_eq "vscode remote schemas: a dropped YAML schema key does not linger" \
      '["https://example.invalid/compose-v2.schema.json"]' \
      "$(jq -c '.["yaml.schemas"] | keys' "$vscode_server_only_settings")"

    vscode_inaccessible_remote_home=$(_tmpdir)
    mkdir -p "$vscode_inaccessible_remote_home/.cursor-server"
    if ((EUID == 0)); then
      echo "  SKIP: vscode inaccessible server-root permission fixture (running as root)"
    else
      chmod 000 "$vscode_inaccessible_remote_home/.cursor-server"
      vscode_inaccessible_remote_dirs=""
      # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
      vscode_inaccessible_remote_dirs=$(env \
        HOME="$vscode_inaccessible_remote_home" REAL_HOME="$REAL_HOME" \
        PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" \
        DOT_TEST_VSCODE_HOSTNAME="inaccessible-remote-host" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { return 1; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_remote_settings_dirs
      ')
      chmod 700 "$vscode_inaccessible_remote_home/.cursor-server"
      _assert_eq "vscode remote settings: inaccessible server root is not discovered" \
        "" "$vscode_inaccessible_remote_dirs"
    fi

    # An installed provider that publishes two copies of the adapter has no
    # usable current payload. The opt-out must still unregister the adapter
    # and prune every managed generation in the provider's directory, whatever
    # its folder name, while leaving development links and siblings alone.
    vscode_missing_termnav_home=$(_tmpdir)
    vscode_missing_termnav_managed="$vscode_missing_termnav_home/.local/share/cgraf78/termnav/share/termnav/vscode"
    vscode_missing_termnav_dated=termnav-20261003-134634-9e2a9382
    mkdir -p \
      "$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/local-extensions.d" \
      "$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/variants.d" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions" \
      "$vscode_missing_termnav_home/dev/termnav-9.9.9" \
      "$vscode_missing_termnav_managed/termnav-0.2.0" \
      "$vscode_missing_termnav_managed/$vscode_missing_termnav_dated" \
      "$vscode_missing_termnav_managed/termnav-tools-0.1.0" \
      "$vscode_missing_termnav_managed/termnav-2-tools-0.1.0"
    cat >"$vscode_missing_termnav_managed/termnav-0.2.0/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.2.0"
}
JSON
    cat >"$vscode_missing_termnav_managed/$vscode_missing_termnav_dated/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.3.0"
}
JSON
    cat >"$vscode_missing_termnav_managed/termnav-2-tools-0.1.0/package.json" <<'JSON'
{
  "name": "termnav-2-tools",
  "publisher": "cgraf",
  "version": "0.1.0"
}
JSON
    cat >"$vscode_missing_termnav_managed/termnav-tools-0.1.0/package.json" <<'JSON'
{
  "name": "termnav-tools",
  "publisher": "cgraf",
  "version": "0.1.0"
}
JSON
    cat >"$vscode_missing_termnav_home/dev/termnav-9.9.9/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "9.9.9"
}
JSON
    for vscode_missing_termnav_entry in termnav-0.2.0 termnav-0.1.0 \
      "$vscode_missing_termnav_dated" termnav-tools-0.1.0 termnav-2-tools-0.1.0; do
      ln -s "$vscode_missing_termnav_managed/$vscode_missing_termnav_entry" \
        "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/$vscode_missing_termnav_entry"
    done
    ln -s "$vscode_missing_termnav_home/dev/termnav-9.9.9" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-9.9.9"
    cat >"$vscode_missing_termnav_home/.vscode-no-termnav/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {"id": "cgraf.termnav"},
    "relativeLocation": "termnav-0.2.0",
    "metadata": {"source": "local"}
  }
]
JSON
    cat >"$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/local-extensions.d/10-extensions.tsv" <<'EOF'
# extension_id	dependency	disabled_by_variant_options
cgraf.termnav	cgraf78/termnav	no-termnav
EOF
    cat >"$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/variants.d/10-variants.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Linux	$HOME/.vscode-no-termnav/extensions	$HOME/.vscode-no-termnav/extensions	-	no-termnav
EOF
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_missing_termnav_output=$(env HOME="$vscode_missing_termnav_home" \
      REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      # This synthetic profile uses a nonstandard extension directory so the
      # generic host detector cannot infer VS Code. Keep the cleanup test about
      # Termnav ownership instead of whichever editor happens to be installed.
      _vscode_present() { return 0; }
      merge
    ' 2>&1)
    _assert_contains "vscode termnav: duplicate provider payloads warn" \
      "publishes 2 copies of VS Code extension cgraf.termnav" \
      "$vscode_missing_termnav_output"
    _assert_eq \
      "vscode termnav: opt-out unregisters adapter when the payload is ambiguous" \
      '[]' \
      "$(jq -c '[.[].identifier.id]' \
        "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/extensions.json")"
    _assert_file_missing \
      "vscode termnav: opt-out removes older adapter when the payload is ambiguous" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.2.0"
    if [[ ! -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/$vscode_missing_termnav_dated" ]]; then
      _pass "vscode termnav: opt-out removes a non-semver managed generation by manifest"
    else
      _fail "vscode termnav: opt-out removes a non-semver managed generation by manifest"
    fi
    if [[ ! -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.1.0" ]]; then
      _pass "vscode termnav: opt-out removes broken managed adapter generations"
    else
      _fail "vscode termnav: opt-out removes broken managed adapter generations"
    fi
    if [[ -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-9.9.9" ]]; then
      _pass "vscode termnav: opt-out preserves same-ID development symlink"
    else
      _fail "vscode termnav: opt-out preserves same-ID development symlink"
    fi
    if [[ -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-tools-0.1.0" ]]; then
      _pass "vscode termnav: opt-out preserves same-parent prefix sibling"
    else
      _fail "vscode termnav: opt-out preserves same-parent prefix sibling"
    fi
    if [[ -L "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-2-tools-0.1.0" ]]; then
      _pass "vscode termnav: opt-out preserves numeric-prefix sibling"
    else
      _fail "vscode termnav: opt-out preserves numeric-prefix sibling"
    fi

    # Provider folder names are packaging choices: the hook must select the
    # payload by manifest identity under whatever directory shdeps resolves,
    # including a date-like name, and ignore folders whose manifest names
    # another extension or publisher. The provider root is deliberately outside
    # shdeps' default install layout so no spelled path can satisfy the
    # resolution.
    vscode_dynamic_home=$(_tmpdir)
    vscode_dynamic_roots="$vscode_dynamic_home/providers"
    vscode_dynamic_vscode="$vscode_dynamic_roots/cgraf78/termnav/share/termnav/vscode"
    vscode_dynamic_alias="$vscode_dynamic_home/providers-alias/cgraf78/termnav/share/termnav/vscode"
    vscode_dynamic_ext="$vscode_dynamic_home/.vscode-dynamic/extensions"
    mkdir -p \
      "$vscode_dynamic_home/.config/dot/merge-hooks.d/vscode/local-extensions.d" \
      "$vscode_dynamic_home/.config/dot/merge-hooks.d/vscode/variants.d" \
      "$vscode_dynamic_ext" \
      "$vscode_dynamic_vscode/$vscode_missing_termnav_dated" \
      "$vscode_dynamic_vscode/termnav-0.9.9" \
      "$vscode_dynamic_vscode/termnav-fork" \
      "$vscode_dynamic_vscode/notes"
    cat >"$vscode_dynamic_vscode/$vscode_missing_termnav_dated/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.3.0"
}
JSON
    cat >"$vscode_dynamic_vscode/termnav-0.9.9/package.json" <<'JSON'
{
  "name": "termnav-legacy",
  "publisher": "cgraf",
  "version": "0.9.9"
}
JSON
    cat >"$vscode_dynamic_vscode/termnav-fork/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "someone-else",
  "version": "0.3.0"
}
JSON
    # Links already reaching the provider through another spelling of the same
    # root (shdeps' checkout link versus its development clone) belong to it:
    # the current one is respelled so the ownership receipt can record it, and
    # a dangling older generation is pruned.
    ln -s "$vscode_dynamic_roots" "$vscode_dynamic_home/providers-alias"
    ln -s "$vscode_dynamic_alias/$vscode_missing_termnav_dated" \
      "$vscode_dynamic_ext/$vscode_missing_termnav_dated"
    ln -s "$vscode_dynamic_alias/termnav-0.2.0" "$vscode_dynamic_ext/termnav-0.2.0"
    # Sley is absent (no provider root), a supported state that must stay
    # silent. The ghost row names an installed provider that publishes no such
    # extension, the retired row keeps the old path-based format, and the
    # dotdot row is a name only shdeps itself rejects.
    cat >"$vscode_dynamic_home/.config/dot/merge-hooks.d/vscode/local-extensions.d/10-extensions.tsv" <<'EOF'
# extension_id	dependency	disabled_by_variant_options
cgraf.sley-tools	cgraf78/sley	no-sley
cgraf.termnav	cgraf78/termnav	no-termnav
cgraf.ghost	cgraf78/termnav	-
cgraf.retired	$HOME/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.3.0	-
cgraf.dotdot	cgraf78/..	-
EOF
    cat >"$vscode_dynamic_home/.config/dot/merge-hooks.d/vscode/variants.d/10-variants.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Linux	$HOME/.vscode-dynamic/extensions	$HOME/.vscode-dynamic/extensions	-
EOF
    # Args: $1 = provider root shdeps reports, $2 = HOME (default: the
    # dynamic fixture). VSCODE_TEST_FAIL_COMMIT=1 fails the extension commit.
    _run_vscode_dynamic_merge() {
      # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
      env HOME="${2:-$vscode_dynamic_home}" REAL_HOME="$REAL_HOME" \
        PATH="$vscode_bin:$PATH" VSCODE_TEST_DEP_ROOT="$1" \
        VSCODE_TEST_FAIL_COMMIT="${VSCODE_TEST_FAIL_COMMIT:-0}" \
        DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
        set -uo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { return 1; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_present() { return 0; }
        if [[ $VSCODE_TEST_FAIL_COMMIT == 1 ]]; then
          _vscode_commit_tracked() { return 1; }
        fi
        merge
        printf "merge-rc=%s\n" "$?"
      ' 2>&1
    }

    # A failed commit rolls the respelled link back to its original spelling.
    vscode_dynamic_output=$(VSCODE_TEST_FAIL_COMMIT=1 \
      _run_vscode_dynamic_merge "$vscode_dynamic_roots")
    _assert_contains "vscode local extensions: injected commit failure fails the merge" \
      "merge-rc=1" "$vscode_dynamic_output"
    _assert_eq "vscode local extensions: rollback restores the respelled link" \
      "$vscode_dynamic_alias/$vscode_missing_termnav_dated" \
      "$(readlink "$vscode_dynamic_ext/$vscode_missing_termnav_dated")"

    vscode_dynamic_output=$(_run_vscode_dynamic_merge "$vscode_dynamic_roots")
    _assert_contains "vscode local extensions: dynamic merge succeeds" \
      "merge-rc=0" "$vscode_dynamic_output"
    _assert_eq "vscode local extensions: links the manifest-matched folder" \
      "$vscode_dynamic_vscode/$vscode_missing_termnav_dated" \
      "$(readlink "$vscode_dynamic_ext/$vscode_missing_termnav_dated")"
    _assert_eq "vscode local extensions: registers the date-named folder" \
      "[\"$vscode_missing_termnav_dated\"]" \
      "$(jq -c '[.[] | select(.identifier.id == "cgraf.termnav") | .relativeLocation]' \
        "$vscode_dynamic_ext/extensions.json")"
    _assert_eq "vscode local extensions: version comes from the manifest" \
      "0.3.0" \
      "$(jq -r '.[] | select(.identifier.id == "cgraf.termnav") | .version' \
        "$vscode_dynamic_ext/extensions.json")"
    _assert_file_missing "vscode local extensions: mismatched manifest is ignored" \
      "$vscode_dynamic_ext/termnav-0.9.9"
    _assert_file_missing "vscode local extensions: another publisher's same name is ignored" \
      "$vscode_dynamic_ext/termnav-fork"
    if [[ ! -L "$vscode_dynamic_ext/termnav-0.2.0" ]]; then
      _pass "vscode local extensions: older generation under another root spelling is pruned"
    else
      _fail "vscode local extensions: older generation under another root spelling is pruned"
    fi
    _assert_eq "vscode local extensions: only resolvable extensions register" \
      '["cgraf.termnav"]' \
      "$(jq -c '[.[] | select(.metadata.source == "local") | .identifier.id]' \
        "$vscode_dynamic_ext/extensions.json")"
    _assert_not_contains "vscode local extensions: absent provider stays silent" \
      "sley" "$vscode_dynamic_output"
    _assert_contains "vscode local extensions: missing provider payload warns" \
      "cgraf78/termnav publishes no VS Code extension cgraf.ghost" \
      "$vscode_dynamic_output"
    _assert_contains "vscode local extensions: retired path rows warn" \
      "cgraf.retired names an invalid dependency" "$vscode_dynamic_output"
    _assert_contains "vscode local extensions: names shdeps rejects warn" \
      "shdeps rejects dependency cgraf78/.. for VS Code local extension cgraf.dotdot" \
      "$vscode_dynamic_output"
    _assert_not_contains "vscode local extensions: unique match does not warn" \
      "copies of VS Code extension cgraf.termnav" "$vscode_dynamic_output"

    # A provider update that renames the folder moves the link and the
    # registration, and retires the previous generation.
    rm -rf "${vscode_dynamic_vscode:?}/$vscode_missing_termnav_dated"
    mkdir -p "$vscode_dynamic_vscode/termnav-next"
    cat >"$vscode_dynamic_vscode/termnav-next/package.json" <<'JSON'
{
  "name": "Termnav",
  "publisher": "CGraf",
  "version": "0.4.0"
}
JSON
    _run_vscode_dynamic_merge "$vscode_dynamic_roots" >/dev/null
    _assert_eq "vscode local extensions: renamed provider folder is linked" \
      "$vscode_dynamic_vscode/termnav-next" \
      "$(readlink "$vscode_dynamic_ext/termnav-next")"
    if [[ ! -L "$vscode_dynamic_ext/$vscode_missing_termnav_dated" ]]; then
      _pass "vscode local extensions: previous folder generation is pruned"
    else
      _fail "vscode local extensions: previous folder generation is pruned"
    fi
    _assert_eq "vscode local extensions: renamed folder replaces the registration" \
      '[{"dir":"termnav-next","version":"0.4.0"}]' \
      "$(jq -c '[.[] | select(.identifier.id == "cgraf.termnav")
        | {dir: .relativeLocation, version}]' "$vscode_dynamic_ext/extensions.json")"

    # Shdeps can start resolving another root (a development clone appears)
    # while every old link stays live. Only the resolved records change, so the
    # unchanged-update signature must still force the full merge.
    vscode_dynamic_moved="$vscode_dynamic_home/providers-moved/cgraf78/termnav/share/termnav/vscode/termnav-moved"
    mkdir -p "$vscode_dynamic_moved"
    cp "$vscode_dynamic_vscode/termnav-next/package.json" "$vscode_dynamic_moved/package.json"
    _run_vscode_dynamic_merge "$vscode_dynamic_home/providers-moved" >/dev/null
    _assert_eq "vscode local extensions: a newly resolved root invalidates the signature" \
      '["termnav-moved"]' \
      "$(jq -c '[.[] | select(.identifier.id == "cgraf.termnav") | .relativeLocation]' \
        "$vscode_dynamic_ext/extensions.json")"
    _assert_eq "vscode local extensions: newly resolved root is linked" \
      "$vscode_dynamic_moved" "$(readlink "$vscode_dynamic_ext/termnav-moved")"

    # Shdeps reports canonical paths, so a provider reached through a moved
    # (symlinked) directory resolves outside HOME. The merge still links and
    # records it rather than failing.
    vscode_outside_home="$vscode_dynamic_home/inner-home"
    mkdir -p \
      "$vscode_outside_home/.config/dot/merge-hooks.d/vscode/local-extensions.d" \
      "$vscode_outside_home/.vscode-dynamic/extensions"
    cp -R "$vscode_dynamic_home/.config/dot/merge-hooks.d/vscode/variants.d" \
      "$vscode_outside_home/.config/dot/merge-hooks.d/vscode/variants.d"
    printf 'cgraf.termnav\tcgraf78/termnav\tno-termnav\n' \
      >"$vscode_outside_home/.config/dot/merge-hooks.d/vscode/local-extensions.d/10-extensions.tsv"
    vscode_outside_output=$(_run_vscode_dynamic_merge \
      "$vscode_dynamic_roots" "$vscode_outside_home")
    _assert_contains "vscode local extensions: provider outside HOME merges cleanly" \
      "merge-rc=0" "$vscode_outside_output"
    _assert_eq "vscode local extensions: provider outside HOME is linked" \
      "$vscode_dynamic_vscode/termnav-next" \
      "$(readlink "$vscode_outside_home/.vscode-dynamic/extensions/termnav-next")"
  else
    echo "  SKIP: VS Code merge provider assertions (jq unavailable)"
  fi
  _test_summary
}
