# shellcheck shell=bash
# VS Code merge-hook units, split from vscode-merges.sh so `dot test`
# overlaps them with that suite's serial chain: the keybinding retirement
# history guard, the hook helpers and single-file merges, the MCP token
# edge cases, variant overlays, and tracked-config convergence. None of
# them reads the chain's fixture merges; the cases that borrow the fixture
# home as HOME run before any merge, exactly as they did in the chain.

# The shared fixture in vscode-merges-setup.sh assigns vscode_home,
# vscode_bin, vscode_mv_log, and the receipt and title expectations; a
# standalone check cannot see those writes.
# shellcheck disable=SC2154

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"
# shellcheck source-path=SCRIPTDIR source=vscode-merges-setup.sh
. "${BASH_SOURCE[0]%/*}/vscode-merges-setup.sh"

dot_dev_vscode_merges_units_test() {
  _dev_vscode_merges_setup || return
  echo "=== VS Code merge hook units ==="

  if command -v jq >/dev/null 2>&1; then
    _vscode_test_append_jsonc_array() {
      local aggregate="$1" source="$2" family="$3"
      local layer next

      layer=$(_tmpfile)
      next=$(_tmpfile)
      # Match production's comment/BOM/CRLF handling. The history guard must
      # compare semantic objects, not formatting, or harmless editor changes
      # would demand false retirement records.
      if ! LC_ALL=C awk '
        NR == 1 { sub(/^\357\273\277/, "", $0) }
        { sub(/\r$/, "", $0) }
        !/^[[:space:]]*\/\//
      ' "$source" |
        jq -s -e --arg family "$family" '
          if length == 1 and (.[0] | type == "array")
          then .[0] | map({family: $family, binding: .})
          else error("expected one array")
          end
        ' >"$layer"; then
        return 1
      fi
      if ! jq -n --slurpfile a "$aggregate" --slurpfile b "$layer" \
        '$a[0] + $b[0]' >"$next"; then
        return 1
      fi
      mv "$next" "$aggregate"
    }

    _vscode_test_retirement_report() {
      local old="$1" current="$2"

      # Keep the invariant calculation separate from Git/materialization so
      # focused negative fixtures can prove each destructive-policy guard. The
      # Family provenance wraps each binding instead of adding a temporary
      # property to it. Exact comparison includes arbitrary user properties;
      # mutating the object here could let the guard pass a retirement that
      # production would never match.
      jq -nc \
        --arg retire "dotfiles.retire" \
        --arg proof "dotfiles.retire-proof" \
        --arg review_proof "review-build:7030e8e" \
        --arg legacy_proof "legacy-local:280f7f8" \
        --slurpfile old "$old" \
        --slurpfile current "$current" '
        def retired_targets($records):
          $records
          | map(select(.binding[$retire] == true)
            | .binding | del(.[$retire], .[$proof]))
          | unique;
        def retirement_directives($records):
          $records
          | map(select(.binding[$retire] == true)
            | .binding | del(.[$retire]))
          | unique;
        def proof_targets($records; $proof_value):
          $records
          | map(select(
              .binding[$retire] == true
              and .binding[$proof] == $proof_value
            ) | .binding | del(.[$retire], .[$proof]))
          | unique;
        def review_oracle:
          [
            {key: "ctrl+.", command: "editor.action.quickFix", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+/", command: "editor.action.commentLine", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+\\", command: "workbench.action.splitEditor", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+e", command: "workbench.view.explorer", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+f", command: "workbench.view.search", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+m", command: "workbench.actions.view.problems", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+p", command: "workbench.action.showCommands", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "shift+cmd+f", command: "workbench.view.search", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "shift+cmd+p", command: "workbench.action.showCommands", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+v", command: "workbench.action.terminal.paste", when: "terminalFocus && !termnav.nvimFocused"},
            {key: "ctrl+shift+v", command: "editor.action.clipboardPasteAction", when: "textInputFocus && !editorReadonly && !terminalFocus"},
            {key: "cmd+/", command: "editor.action.commentLine", when: "terminalFocus && !termnav.nvimFocused"}
          ] | unique;
        def legacy_oracle:
          [
            {
              key: "ctrl+tab",
              command: "workbench.action.terminal.focusNext",
              when: "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
            },
            {
              key: "ctrl+shift+tab",
              command: "workbench.action.terminal.focusPrevious",
              when: "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
            }
          ] | unique;
        def effective($records; $platform; $termnav):
          $records
          | map(select(.binding[$retire] != true))
          | map(select(
              .family == "all"
              or .family == $platform
              or (.family == "termnav" and $termnav)
            ))
          | map(.binding)
          | unique;
        def active_union($records):
          $records
          | map(select(.binding[$retire] != true) | .binding)
          | unique;
        (retired_targets($old[0])) as $old_retired |
        (retired_targets($current[0])) as $current_retired |
        (retirement_directives($old[0])) as $old_directives |
        (retirement_directives($current[0])) as $current_directives |
        (proof_targets($current[0]; $review_proof)) as $reviewed |
        (proof_targets($current[0]; $legacy_proof)) as $legacy |
        (review_oracle) as $review_oracle |
        (legacy_oracle) as $legacy_oracle |
        ($reviewed - ($reviewed - $review_oracle)) as $authorized_reviewed |
        ($legacy - ($legacy - $legacy_oracle)) as $authorized_legacy |
        {
          missing: {
            linux: (
              effective($old[0]; "linux"; true)
              - effective($current[0]; "linux"; true)
              - $current_retired
            ),
            macos: (
              effective($old[0]; "macos"; true)
              - effective($current[0]; "macos"; true)
              - $current_retired
            ),
            windows: (
              effective($old[0]; "windows"; true)
              - effective($current[0]; "windows"; true)
              - $current_retired
            ),
            linux_no_termnav: (
              effective($old[0]; "linux"; false)
              - effective($current[0]; "linux"; false)
              - $current_retired
            ),
            macos_no_termnav: (
              effective($old[0]; "macos"; false)
              - effective($current[0]; "macos"; false)
              - $current_retired
            ),
            windows_no_termnav: (
              effective($old[0]; "windows"; false)
              - effective($current[0]; "windows"; false)
              - $current_retired
            )
          },
          removed: ($old_directives - $current_directives),
          misplaced: (
            $current[0]
            | map(select(
                .binding[$retire] == true
                and .family != "all"
              ))
          ),
          unproven: (
            ($current_retired - $old_retired)
            - active_union($old[0])
            - $authorized_reviewed
            - $authorized_legacy
          ),
          review_proof_extra: ($reviewed - $review_oracle),
          review_proof_missing: ($review_oracle - $reviewed),
          legacy_proof_extra: ($legacy - $legacy_oracle),
          legacy_proof_missing: ($legacy_oracle - $legacy),
          invalid_proofs: (
            $current[0]
            | map(select(
                (.binding | has($proof))
                and (
                  .binding[$retire] != true
                  or (
                    .binding[$proof] != $review_proof
                    and .binding[$proof] != $legacy_proof
                  )
                )
              ))
          )
        }
      '
    }

    _assert_vscode_retirement_history() {
      local repo="$1"
      local rel=.config/dot/merge-hooks.d/vscode/keybindings
      local git_root git_prefix git_rel head origin base base_sha path deploy_path old_root
      local source family report report_family
      local old_all current_all history_deferred=0
      origin=""
      base=""

      # Runtime merging must not depend on Git: deployed dotfiles may be
      # exported, shallow, or split across overlays. This is deliberately a
      # development-time guard. It compares the proposed source with the event
      # base (or the last landed commit during local/main runs) and turns a
      # forgotten retirement into a failing test before the unsafe edit ships.
      if ! git_root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null); then
        _pass "vscode keybindings: retirement history guard skipped outside Git"
        return
      fi
      git_prefix=$(git -C "$repo" rev-parse --show-prefix 2>/dev/null) || return
      git_rel=$git_prefix$rel

      head=$(git -C "$git_root" rev-parse HEAD 2>/dev/null || true)
      base_sha="${DOT_VSCODE_KEYBINDING_BASE_SHA:-}"
      if [[ -n "$base_sha" && "$base_sha" != "0000000000000000000000000000000000000000" ]]; then
        if [[ "$base_sha" == "$head" ]] &&
          git -C "$git_root" diff --quiet HEAD -- "$git_rel" 2>/dev/null; then
          _fail "vscode keybindings: event base must precede a clean checkout"
          return
        fi
        if git -C "$git_root" cat-file -e "$base_sha^{commit}" 2>/dev/null; then
          base="$base_sha"
        else
          _fail "vscode keybindings: event base commit was not fetched"
          return
        fi
      else
        origin=$(git -C "$git_root" rev-parse --verify --quiet \
          'origin/main^{commit}' 2>/dev/null || true)
      fi

      if [[ -z "${base:-}" && -n "$origin" && "$origin" != "$head" ]]; then
        # Local feature worktrees compare with the merge base of their fetched
        # base branch. The branch tip can advance during review and may no
        # longer be an ancestor of this checkout; comparing directly with that
        # unrelated future tip would invent removals and hide the immutable
        # predecessor generation. CI takes the event-SHA path above.
        base=$(git -C "$git_root" merge-base "$origin" "$head" 2>/dev/null || true)
      elif [[ -z "${base:-}" ]] &&
        ! git -C "$git_root" diff --quiet HEAD -- "$git_rel" 2>/dev/null; then
        base="$head"
      elif [[ -z "${base:-}" ]]; then
        # --verify keeps an unresolvable parent empty. Plain rev-parse echoes
        # the literal `HEAD^` on a shallow or root commit, which then read as
        # an empty history and passed the guard instead of deferring it.
        base=$(git -C "$git_root" rev-parse --verify --quiet 'HEAD^' 2>/dev/null || true)
      fi

      if [[ -z "$base" ]]; then
        if [[ $(git -C "$git_root" rev-parse --is-shallow-repository 2>/dev/null) == true ]]; then
          # Only the comparison with history needs a base. The checks that
          # read the current tree alone still run below.
          history_deferred=1
        else
          _fail "vscode keybindings: retirement history guard requires a Git base"
          return
        fi
      fi
      old_all=$(_tmpfile)
      current_all=$(_tmpfile)
      old_root=$(_tmpdir)
      printf '[]\n' >"$old_all"
      printf '[]\n' >"$current_all"

      # Materialize only the historical source subtree. Reusing the production
      # family selector against this temporary HOME preserves `.replace`
      # semantics; a raw recursive scan could validate a fragment that the
      # runtime would never load and mask a real per-platform disappearance.
      while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ "$path" == *.jsonc ]] || continue
        deploy_path=${path#"$git_prefix"}
        mkdir -p "$old_root/$(dirname "$deploy_path")"
        if ! git -C "$git_root" show "$base:$path" >"$old_root/$deploy_path"; then
          _fail "vscode keybindings: historical JSONC must be readable"
          return
        fi
      done < <(
        ((history_deferred)) ||
          git -C "$git_root" ls-tree -r --name-only "$base" -- "$git_rel" |
          LC_ALL=C sort
      )

      # all + the three platform families are the runtime union. termnav is
      # retained here only as the explicitly removed historical family.
      for family in all termnav linux macos windows; do
        report_family="$family"
        while IFS= read -r source; do
          if ! _vscode_test_append_jsonc_array \
            "$old_all" "$source" "$report_family"; then
            _fail "vscode keybindings: historical JSONC must parse completely"
            return
          fi
        done < <(
          HOME="$old_root" _merge_hook_family_files_matching \
            "vscode/keybindings/$family.d" \
            '*.jsonc' '*.replace/*.jsonc'
        )
        if [[ "$family" == "termnav" ]]; then
          # The historical scan above proves this migration's removals. Runtime
          # no longer loads the family, so this current scan only prevents an
          # unreachable fragment from becoming future retirement provenance.
          while IFS= read -r source; do
            [[ -n "$source" ]] || continue
            _fail "vscode keybindings: obsolete termnav family stays removed"
            return
          done < <(
            HOME="$repo" _merge_hook_family_files_matching \
              vscode/keybindings/termnav.d \
              '*.jsonc' '*.replace/*.jsonc'
          )
          continue
        fi
        while IFS= read -r source; do
          if ! _vscode_test_append_jsonc_array \
            "$current_all" "$source" "$report_family"; then
            _fail "vscode keybindings: current JSONC must parse completely"
            return
          fi
        done < <(
          HOME="$repo" _merge_hook_family_files_matching \
            "vscode/keybindings/$family.d" \
            '*.jsonc' '*.replace/*.jsonc'
        )
      done

      # An active object that disappears is a change or deletion. Requiring its
      # exact old form in retirement lets any machine jump directly from the
      # base to this generation, even if Settings Sync delivered an intervening
      # file. Retirement itself is append-only for the same skipped-release
      # reason.
      report=$(_tmpfile)
      _vscode_test_retirement_report "$old_all" "$current_all" >"$report"
      if ((history_deferred)); then
        # Against the empty stand-in history these would pass vacuously.
        _pass "vscode keybindings: dynamic retirement history guard deferred to full-history CI"
      else
        _assert_eq "vscode linux keybindings: changed and deleted bindings enter retirement history" \
          '[]' "$(jq -c '.missing.linux' "$report")"
        _assert_eq "vscode macos keybindings: changed and deleted bindings enter retirement history" \
          '[]' "$(jq -c '.missing.macos' "$report")"
        _assert_eq "vscode windows keybindings: changed and deleted bindings enter retirement history" \
          '[]' "$(jq -c '.missing.windows' "$report")"
        _assert_eq "vscode linux no-termnav keybindings: capability moves enter retirement history" \
          '[]' "$(jq -c '.missing.linux_no_termnav' "$report")"
        _assert_eq "vscode macos no-termnav keybindings: capability moves enter retirement history" \
          '[]' "$(jq -c '.missing.macos_no_termnav' "$report")"
        _assert_eq "vscode windows no-termnav keybindings: capability moves enter retirement history" \
          '[]' "$(jq -c '.missing.windows_no_termnav' "$report")"
        _assert_eq "vscode keybindings: retirement history is append-only" \
          '[]' "$(jq -c '.removed' "$report")"
      fi

      # All platforms consume all.d, making it the only safe home for an exact
      # retirement synchronized across machines. A platform-local retirement
      # would pass that platform's history check but strand the same generated
      # object after Settings Sync carries it elsewhere.
      _assert_eq "vscode keybindings: retirement records are globally available from all.d" \
        '[]' "$(jq -c '.misplaced' "$report")"
      _assert_eq "vscode keybindings: PR 90 review-build proof adds no other targets" \
        '[]' "$(jq -c '.review_proof_extra' "$report")"
      _assert_eq "vscode keybindings: PR 90 review-build proof retains every canonical target" \
        '[]' "$(jq -c '.review_proof_missing' "$report")"
      _assert_eq "vscode keybindings: legacy local proof adds no other targets" \
        '[]' "$(jq -c '.legacy_proof_extra' "$report")"
      _assert_eq "vscode keybindings: legacy local proof retains both canonical targets" \
        '[]' "$(jq -c '.legacy_proof_missing' "$report")"
      _assert_eq "vscode keybindings: retirement proof labels stay allowlisted" \
        '[]' "$(jq -c '.invalid_proofs' "$report")"
      if ((! history_deferred)) && [[ -n ${DOT_TEST_VSCODE_HISTORY_MARKER:-} ]]; then
        printf 'executed\n' >"$DOT_TEST_VSCODE_HISTORY_MARKER"
      fi
    }

    _assert_vscode_retirement_history "$REAL_HOME"

    # Negative fixtures protect the safety validator itself. These are kept
    # small and semantic so a future refactor cannot silently turn a missing,
    # removed, misplaced, or invented retirement into a passing repository
    # check while the much larger end-to-end fixture remains green.
    vscode_guard_old=$(_tmpfile)
    vscode_guard_current=$(_tmpfile)
    vscode_guard_report=$(_tmpfile)
    cat >"$vscode_guard_old" <<'JSON'
[
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+1",
      "command": "fixture.mustRetire"
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+2",
      "command": "fixture.oldRetirement",
      "dotfiles.retire": true
    }
  }
]
JSON
    cat >"$vscode_guard_current" <<'JSON'
[
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+2",
      "command": "fixture.oldRetirement"
    }
  },
  {
    "family": "macos",
    "binding": {
      "key": "ctrl+alt+3",
      "command": "fixture.misplacedRetirement",
      "dotfiles.retire": true
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+4",
      "command": "fixture.unprovenRetirement",
      "dotfiles.retire": true
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+5",
      "command": "fixture.invalidRetirementProof",
      "dotfiles.retire": true,
      "dotfiles.retire-proof": "review-build:invented"
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+6",
      "command": "fixture.substitutedReviewTarget",
      "dotfiles.retire": true,
      "dotfiles.retire-proof": "review-build:7030e8e"
    }
  },
  {
    "family": "all",
    "binding": {
      "key": "ctrl+alt+7",
      "command": "fixture.substitutedLegacyTarget",
      "dotfiles.retire": true,
      "dotfiles.retire-proof": "legacy-local:280f7f8"
    }
  }
]
JSON
    _vscode_test_retirement_report \
      "$vscode_guard_old" "$vscode_guard_current" >"$vscode_guard_report"
    _assert_eq "vscode history guard: missing retirement is rejected" \
      "1" "$(jq '.missing.linux | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: removed retirement is rejected" \
      "1" "$(jq '.removed | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: platform-local retirement is rejected" \
      "1" "$(jq '.misplaced | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: unproven retirement is rejected" \
      "5" "$(jq '.unproven | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: unknown retirement proof is rejected" \
      "1" "$(jq '.invalid_proofs | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: substituted review target is rejected" \
      "1" "$(jq '.review_proof_extra | length' "$vscode_guard_report")"
    _assert_eq "vscode history guard: substituted legacy target is rejected" \
      "1" "$(jq '.legacy_proof_extra | length' "$vscode_guard_report")"

    vscode_base_guard_repo=$(_tmpdir)
    mkdir -p \
      "$vscode_base_guard_repo/.config/dot/merge-hooks.d/vscode/keybindings/all.d"
    printf '[]\n' \
      >"$vscode_base_guard_repo/.config/dot/merge-hooks.d/vscode/keybindings/all.d/10-keybindings.jsonc"
    git -C "$vscode_base_guard_repo" init -q
    git -C "$vscode_base_guard_repo" add .
    git -C "$vscode_base_guard_repo" \
      -c user.name=dot-fixture -c user.email=dot.fixture.invalid \
      commit -q --no-verify -m base
    vscode_self_base_rc=0
    (
      set -e
      _fail() { return 23; }
      export DOT_VSCODE_KEYBINDING_BASE_SHA
      DOT_VSCODE_KEYBINDING_BASE_SHA=$(
        git -C "$vscode_base_guard_repo" rev-parse HEAD
      )
      _assert_vscode_retirement_history "$vscode_base_guard_repo"
    ) || vscode_self_base_rc=$?
    _assert_eq "vscode history guard: clean checkout cannot compare with itself" \
      "23" "$vscode_self_base_rc"

    # A clean checkout without an event base falls back to HEAD's parent. When
    # that parent is unavailable, the guard must defer its history checks
    # (shallow) or fail (root commit) rather than compare against an empty
    # history and pass; checks of the current tree alone still run.
    _vscode_guard_fallback_outcome() (
      local repo=$1
      unset DOT_VSCODE_KEYBINDING_BASE_SHA DOT_TEST_VSCODE_HISTORY_MARKER
      _pass() { printf 'pass: %s\n' "$1"; }
      _fail() { printf 'fail: %s\n' "$1"; }
      _assert_eq() { printf 'assert: %s\n' "$1"; }
      _assert_vscode_retirement_history "$repo" 2>&1
    )
    git -C "$vscode_base_guard_repo" \
      -c user.name=dot-fixture -c user.email=dot.fixture.invalid \
      commit -q --no-verify --allow-empty -m second
    vscode_shallow_guard_repo=$(_tmpdir)/shallow
    git -c protocol.file.allow=always clone -q --depth 1 \
      "file://$vscode_base_guard_repo" "$vscode_shallow_guard_repo"
    vscode_shallow_outcome=$(_vscode_guard_fallback_outcome "$vscode_shallow_guard_repo")
    _assert_contains "vscode history guard: shallow clean checkout defers history checks" \
      "pass: vscode keybindings: dynamic retirement history guard deferred to full-history CI" \
      "$vscode_shallow_outcome"
    _assert_not_contains "vscode history guard: shallow checkout skips history comparisons" \
      "enter retirement history" "$vscode_shallow_outcome"
    _assert_contains "vscode history guard: shallow checkout still runs tree-only checks" \
      "assert: vscode keybindings: retirement records are globally available from all.d" \
      "$vscode_shallow_outcome"
    _assert_not_contains "vscode history guard: shallow checkout reads no missing parent" \
      "fatal:" "$vscode_shallow_outcome"

    vscode_root_guard_repo=$(_tmpdir)
    cp -R "$vscode_base_guard_repo/.config" "$vscode_root_guard_repo/.config"
    git -C "$vscode_root_guard_repo" init -q
    git -C "$vscode_root_guard_repo" add .
    git -C "$vscode_root_guard_repo" \
      -c user.name=dot-fixture -c user.email=dot.fixture.invalid \
      commit -q --no-verify -m root
    _assert_eq "vscode history guard: root commit without a base fails" \
      "fail: vscode keybindings: retirement history guard requires a Git base" \
      "$(_vscode_guard_fallback_outcome "$vscode_root_guard_repo")"

    _dev_vscode_merges_fixture

    # The hook computes parents in-process; it must agree with the platform's
    # dirname on edge cases, including trailing and repeated slashes.
    # shellcheck disable=SC2016 # The inner shell expands its own variables.
    vscode_dirname_mismatches=$(env REAL_HOME="$REAL_HOME" bash -c '
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      for path in "" / // /a /a/ /a//b/ a a/ a/b "a b/c d" -x/y ///a /a//; do
        _vscode_dirname "$path"
        [[ $REPLY == "$(dirname -- "$path")" ]] || printf "[%s] " "$path"
      done
    ')
    _assert_eq "vscode dirname helper matches dirname" "" "$vscode_dirname_mismatches"

    vscode_variants_home=$(_tmpdir)
    mkdir -p \
      "$vscode_variants_home/.vscode/extensions" \
      "$vscode_variants_home/.config/Code/User" \
      "$vscode_variants_home/.vscode-insiders/extensions" \
      "$vscode_variants_home/.config/Code - Insiders/User" \
      "$vscode_variants_home/.cursor/extensions" \
      "$vscode_variants_home/.config/Cursor/User" \
      "$vscode_variants_home/.config/dot/merge-hooks.d"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_variants_home/.config/dot/merge-hooks.d/vscode"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_default_linux_variants=$(env HOME="$vscode_variants_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants | sort
    ')
    vscode_expected_linux_variants=$(printf '%s\n' \
      "$vscode_variants_home/.vscode/extensions	$vscode_variants_home/.config/Code/User" \
      "$vscode_variants_home/.vscode-insiders/extensions	$vscode_variants_home/.config/Code - Insiders/User" \
      "$vscode_variants_home/.cursor/extensions	$vscode_variants_home/.config/Cursor/User" |
      sort)
    _assert_eq "vscode variants: default Linux variants include Code, Insiders, and Cursor" \
      "$vscode_expected_linux_variants" \
      "$vscode_default_linux_variants"

    vscode_variants_macos_home=$(_tmpdir)
    mkdir -p \
      "$vscode_variants_macos_home/Applications/Visual Studio Code.app" \
      "$vscode_variants_macos_home/Applications/Visual Studio Code - Insiders.app" \
      "$vscode_variants_macos_home/Applications/VS Code @ FB.app" \
      "$vscode_variants_macos_home/Applications/VS Code @ FB - Insiders.app" \
      "$vscode_variants_macos_home/Applications/Cursor.app" \
      "$vscode_variants_macos_home/Library/Application Support/Code/User" \
      "$vscode_variants_macos_home/Library/Application Support/Code - Insiders/User" \
      "$vscode_variants_macos_home/Library/Application Support/VS Code @ FB/User" \
      "$vscode_variants_macos_home/Library/Application Support/VS Code @ FB - Insiders/User" \
      "$vscode_variants_macos_home/Library/Application Support/Cursor/User" \
      "$vscode_variants_macos_home/.config/dot/merge-hooks.d"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_variants_macos_home/.config/dot/merge-hooks.d/vscode"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_default_macos_variants=$(env HOME="$vscode_variants_macos_home" \
      REAL_HOME="$REAL_HOME" \
      DOT_TEST_VSCODE_APPLICATIONS_DIR="$vscode_variants_macos_home/Applications" \
      bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Darwin\n"; }
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants | sort
    ')
    vscode_expected_macos_variants=$(printf '%s\n' \
      "$vscode_variants_macos_home/.cursor/extensions	$vscode_variants_macos_home/Library/Application Support/Cursor/User" \
      "$vscode_variants_macos_home/.vscode/extensions	$vscode_variants_macos_home/Library/Application Support/Code/User" \
      "$vscode_variants_macos_home/.vscode-fb-insiders-mkt/extensions	$vscode_variants_macos_home/Library/Application Support/VS Code @ FB - Insiders/User" \
      "$vscode_variants_macos_home/.vscode-fb-mkt/extensions	$vscode_variants_macos_home/Library/Application Support/VS Code @ FB/User" \
      "$vscode_variants_macos_home/.vscode-insiders/extensions	$vscode_variants_macos_home/Library/Application Support/Code - Insiders/User" |
      sort)
    _assert_eq "vscode variants: default macOS variants include Code, FB Code, and Cursor" \
      "$vscode_expected_macos_variants" \
      "$vscode_default_macos_variants"

    vscode_variant_override_home=$(_tmpdir)
    mkdir -p \
      "$vscode_variant_override_home/Applications/Editor A.app" \
      "$vscode_variant_override_home/Applications/Editor B.app" \
      "$vscode_variant_override_home/shared/User" \
      "$vscode_variant_override_home/variants.d"
    cat >"$vscode_variant_override_home/variants.d/10-defaults.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Darwin	${VSCODE_APPLICATIONS_DIR}/Editor A.app	$HOME/editor-a/extensions	$HOME/shared/User	initial-policy
Darwin	${VSCODE_APPLICATIONS_DIR}/Editor B.app	$HOME/editor-b/extensions	$HOME/shared/User	middle-policy
EOF
    cat >"$vscode_variant_override_home/variants.d/80-local.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Darwin	${VSCODE_APPLICATIONS_DIR}/Editor A.app	$HOME/editor-a/extensions	$HOME/shared/User	final-policy
EOF
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_variant_override_output=$(env HOME="$vscode_variant_override_home" \
      REAL_HOME="$REAL_HOME" \
      DOT_TEST_VSCODE_APPLICATIONS_DIR="$vscode_variant_override_home/Applications" \
      VSCODE_VARIANT_DIR="$vscode_variant_override_home/variants.d" \
      bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Darwin\n"; }
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variant_sources() {
        printf "%s\n" "$VSCODE_VARIANT_DIR/10-defaults.tsv" \
          "$VSCODE_VARIANT_DIR/80-local.tsv"
      }
      variants=()
      while IFS= read -r variant; do
        variants+=("$variant")
        printf "variant\t%s\n" "$variant"
      done < <(_vscode_variants)
      while IFS= read -r variant; do
        printf "config\t%s\n" "$variant"
      done < <(_vscode_config_variants "${variants[@]}")
    ')
    vscode_expected_variant_override_output=$(printf '%s\n' \
      "variant	$vscode_variant_override_home/editor-b/extensions	$vscode_variant_override_home/shared/User	middle-policy" \
      "variant	$vscode_variant_override_home/editor-a/extensions	$vscode_variant_override_home/shared/User	final-policy" \
      "config	$vscode_variant_override_home/editor-a/extensions	$vscode_variant_override_home/shared/User	final-policy")
    _assert_eq "vscode variants: later duplicate keeps final ordering and config policy" \
      "$vscode_expected_variant_override_output" \
      "$vscode_variant_override_output"

    vscode_extension_variant_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_extension_variant_output=$(env HOME="$vscode_variant_override_home" \
      REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      variants=()
      printf -v variant "%s\t%s\t%s" \
        "$HOME/editor-a/extensions" "$HOME/config-a" shared-policy
      variants+=("$variant")
      printf -v variant "%s\t%s\t%s" \
        "$HOME/editor-b/extensions" "$HOME/shared/User" middle-policy
      variants+=("$variant")
      printf -v variant "%s\t%s\t%s" \
        "$HOME/editor-a/extensions" "$HOME/config-b" shared-policy
      variants+=("$variant")
      printf -v variant "%s\t%s\t%s" \
        "$HOME/editor-a/extensions" "$HOME/config-c" final-policy
      variants+=("$variant")
      _vscode_extension_variants "${variants[@]}"
    ' 2>/dev/null) || vscode_extension_variant_rc=$?
    _assert_eq "vscode extensions: target deduplicator is available" \
      "0" "$vscode_extension_variant_rc"
    vscode_expected_extension_variant_output=$(printf '%s\t%s\t%s\n' \
      "$vscode_variant_override_home/editor-b/extensions" \
      "$vscode_variant_override_home/shared/User" middle-policy \
      "$vscode_variant_override_home/editor-a/extensions" \
      "$vscode_variant_override_home/config-b" shared-policy \
      "$vscode_variant_override_home/editor-a/extensions" \
      "$vscode_variant_override_home/config-c" final-policy)
    _assert_eq "vscode extensions: duplicate target and options keep final ordering" \
      "$vscode_expected_extension_variant_output" \
      "$vscode_extension_variant_output"

    vscode_local_extension_count=$vscode_variant_override_home/local-extension-count
    vscode_extension_reconcile_log=$vscode_variant_override_home/extension-reconcile-log
    : >"$vscode_local_extension_count"
    : >"$vscode_extension_reconcile_log"
    vscode_local_extension_cache_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_variant_override_home" REAL_HOME="$REAL_HOME" \
      COUNT_FILE="$vscode_local_extension_count" \
      RECONCILE_FILE="$vscode_extension_reconcile_log" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_present() { return 0; }
      _vscode_install_declared_extensions() { :; }
      _vscode_variants() {
        printf "%s\t%s\t%s\n" \
          "$HOME/editor-a/extensions" "$HOME/config-a" shared-policy
        printf "%s\t%s\t%s\n" \
          "$HOME/editor-b/extensions" "$HOME/config-b" middle-policy
        printf "%s\t%s\t%s\n" \
          "$HOME/editor-a/extensions" "$HOME/config-c" shared-policy
      }
      _vscode_local_extensions() {
        printf "called\n" >>"$COUNT_FILE"
        printf "%s\t%s\t%s\n" \
          fixture.extension "$HOME/missing-extension" -
      }
      _merge_vscode_remote_configs_tracked() { :; }
      _merge_vscode_config_tracked() { :; }
      _vscode_merge_extensions_tracked() {
        printf "%s\n" "$1" >>"$RECONCILE_FILE"
        [[ ${2:-} == -- ]]
      }
      merge
    ' || vscode_local_extension_cache_rc=$?
    _assert_eq "vscode extensions: cached declaration merge succeeds" \
      "0" "$vscode_local_extension_cache_rc"
    _assert_eq "vscode extensions: local declarations resolve once per merge" \
      "1" "$(wc -l <"$vscode_local_extension_count" | tr -d ' ')"
    vscode_expected_extension_reconcile_output=$(printf '%s\t%s\t%s\n' \
      "$vscode_variant_override_home/editor-b/extensions" \
      "$vscode_variant_override_home/config-b" middle-policy \
      "$vscode_variant_override_home/editor-a/extensions" \
      "$vscode_variant_override_home/config-c" shared-policy)
    _assert_eq "vscode extensions: merge reconciles each target and policy once" \
      "$vscode_expected_extension_reconcile_output" \
      "$(cat "$vscode_extension_reconcile_log")"

    partial_mv_bin=$(_tmpdir)/bin
    partial_commit_dir=$(_tmpdir)
    mkdir -p "$partial_mv_bin"
    cat >"$partial_mv_bin/mv" <<'EOF'
#!/usr/bin/env python3
import os
import sys

args = sys.argv[1:]
if args[:1] == ["-f"]:
    args = args[1:]
if args[:1] == ["--"]:
    args = args[1:]
src, dst = args
data = open(src, "rb").read()
with open(dst, "wb") as handle:
    handle.write(data[:32])
os.unlink(src)
EOF
    chmod +x "$partial_mv_bin/mv"
    python3 - <<PY
from pathlib import Path
expected = '{"value": "' + ('x' * 400) + '"}\n'
Path("$partial_commit_dir/settings.json").write_text('{"old": true}\n')
Path("$partial_commit_dir/settings.json.tmp").write_text(expected)
Path("$partial_commit_dir/settings.json.tmp.expected").write_text(expected)
PY
    partial_commit_rc=0
    # shellcheck disable=SC2016 # The inner shell expands temp-path env variables.
    env PATH="$partial_mv_bin:$PATH" \
      REAL_HOME="$REAL_HOME" \
      PARTIAL_TMP="$partial_commit_dir/settings.json.tmp" \
      PARTIAL_DST="$partial_commit_dir/settings.json" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { [[ $1 == wsl ]]; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_commit_tmp "$PARTIAL_TMP" "$PARTIAL_DST"
    ' || partial_commit_rc=$?
    _assert_eq "vscode commit: WSL partial replacement exits cleanly" \
      "0" "$partial_commit_rc"
    partial_expected=$(
      python3 - <<PY
from pathlib import Path
print(Path("$partial_commit_dir/settings.json.tmp.expected").read_text(), end="")
PY
    )
    partial_actual=$(cat "$partial_commit_dir/settings.json")
    _assert_eq "vscode commit: WSL partial replacement writes complete file" \
      "$partial_expected" "$partial_actual"

    # WSL cannot fall back to the native rename path: an open Windows file can
    # turn that apparent success into a truncated config. If the verified
    # writer is unavailable, keep both the destination and retryable temp file
    # rather than gambling with user configuration.
    wsl_missing_python_dir=$(_tmpdir)
    printf '%s\n' '{"old":true}' \
      >"$wsl_missing_python_dir/keybindings.json"
    printf '%s\n' '{"new":true}' \
      >"$wsl_missing_python_dir/keybindings.json.tmp"
    wsl_missing_python_rc=0
    # shellcheck disable=SC2016 # The inner shell owns the command override.
    env REAL_HOME="$REAL_HOME" WSL_FAILURE_DIR="$wsl_missing_python_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { [[ $1 == wsl ]]; }
      command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "python3" ]]; then
          return 1
        fi
        builtin command "$@"
      }
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_commit_tmp \
        "$WSL_FAILURE_DIR/keybindings.json.tmp" \
        "$WSL_FAILURE_DIR/keybindings.json"
    ' || wsl_missing_python_rc=$?
    _assert_eq "vscode commit: WSL missing verified writer fails" \
      "1" "$wsl_missing_python_rc"
    _assert_file_content "vscode commit: WSL failure preserves destination" \
      '{"old":true}' "$wsl_missing_python_dir/keybindings.json"
    _assert_file_content "vscode commit: WSL failure retains retryable temp" \
      '{"new":true}' "$wsl_missing_python_dir/keybindings.json.tmp"

    # A machine can skip the migration release and arrive after a focus-aware
    # replacement was itself deleted. Exact source retirement, rather than
    # today's active actions, must still identify the old generated rule.
    vscode_delayed_upgrade_dir=$(_tmpdir)
    cat >"$vscode_delayed_upgrade_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+p",
    "command": "workbench.action.quickOpen",
    "when": "terminalFocus",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "old"},
    "when": "fixture.retiredExact",
    "dotfiles.retire": true,
    "dotfiles.retire-proof": "review-build:7030e8e"
  }
]
JSON
    cat >"$vscode_delayed_upgrade_dir/keybindings.json" <<'JSON'
[
  {
    "key": "ctrl+p",
    "command": "workbench.action.quickOpen",
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "old"},
    "when": "fixture.retiredExact"
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "local"},
    "when": "fixture.retiredExact"
  },
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retiredExact",
    "args": {"text": "old"},
    "when": "fixture.retiredExact",
    "localOnly": true
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      HOME_DELAYED="$vscode_delayed_upgrade_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$HOME_DELAYED/source.json" \
        "$HOME_DELAYED/keybindings.json" \
        linux
    '
    _assert_eq "vscode keybindings: delayed upgrade retires source-owned baseline" \
      "0" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus"
      )] | length' "$vscode_delayed_upgrade_dir/keybindings.json")"
    _assert_eq "vscode keybindings: proven retirement preserves args and property near-matches" \
      '[{"args":{"text":"local"},"command":"fixture.retiredExact","key":"ctrl+alt+4","when":"fixture.retiredExact"},{"args":{"text":"old"},"command":"fixture.retiredExact","key":"ctrl+alt+4","localOnly":true,"when":"fixture.retiredExact"}]' \
      "$(jq -c '[.[] | select(.command == "fixture.retiredExact")]' \
        "$vscode_delayed_upgrade_dir/keybindings.json")"

    # Target B never runs generation V2 locally; it receives A's plain JSON
    # artifact through a divergent Settings Sync merge. V3's exact retirement
    # record must remove V2 without relying on comments or sibling metadata.
    vscode_sync_a=$(_tmpdir)
    vscode_sync_b=$(_tmpdir)
    cat >"$vscode_sync_a/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+1",
    "command": "fixture.syncV1",
    "when": "fixture.syncV1"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" SYNC_DIR="$vscode_sync_a" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$SYNC_DIR/source.json" "$SYNC_DIR/keybindings.json" macos
    '
    cat >"$vscode_sync_a/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+1",
    "command": "fixture.syncV1",
    "when": "fixture.syncV1",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+2",
    "command": "fixture.syncV2",
    "when": "fixture.syncV2"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" SYNC_DIR="$vscode_sync_a" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$SYNC_DIR/source.json" "$SYNC_DIR/keybindings.json" macos
    '
    # Model a Windows editor transporting the macOS generation with both a BOM
    # and CRLF. The retirement policy lives in source, so transport formatting
    # cannot erase the provenance needed by the target machine.
    {
      printf '\357\273\277'
      awk '{ printf "%s\r\n", $0 }' \
        "$vscode_sync_a/keybindings.json"
    } >"$vscode_sync_b/keybindings.json"
    cat >"$vscode_sync_b/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+2",
    "command": "fixture.syncV2",
    "when": "fixture.syncV2",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+3",
    "command": "fixture.syncV3",
    "when": "fixture.syncV3"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" SYNC_DIR="$vscode_sync_b" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$SYNC_DIR/source.json" "$SYNC_DIR/keybindings.json" linux
    '
    _assert_eq "vscode keybindings: source history retires synced generation unseen by target" \
      '["fixture.syncV3"]' \
      "$(jq -c '[.[] | .command | select(startswith("fixture.sync"))]' \
        "$vscode_sync_b/keybindings.json")"

    # A brand-new profile receives only active bindings. Retirement directives
    # must never leak into VS Code, where they would be invalid shortcuts.
    vscode_first_run_dir=$(_tmpdir)
    cat >"$vscode_first_run_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+1",
    "command": "fixture.firstRun",
    "when": "fixture.firstRun"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      FIRST_RUN_DIR="$vscode_first_run_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$FIRST_RUN_DIR/source.json" \
        "$FIRST_RUN_DIR/keybindings.json" \
        linux
    '
    _assert_eq "vscode keybindings: first run creates managed binding" \
      '["fixture.firstRun"]' \
      "$(jq -c '[.[] | .command | select(startswith("fixture."))]' \
        "$vscode_first_run_dir/keybindings.json")"
    _assert_not_contains "vscode keybindings: first run omits source retirement directives" \
      'dotfiles.retire' \
      "$(cat "$vscode_first_run_dir/keybindings.json")"

    # Losing a source layer could discard either an active binding or the exact
    # retirement that protects a skipped-release migration. Force the
    # intermediate rename to fail before any artifact is written.
    vscode_aggregate_failure_home=$(_tmpdir)
    mkdir -p "$vscode_aggregate_failure_home/.config/dot/merge-hooks.d"
    cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
      "$vscode_aggregate_failure_home/.config/dot/merge-hooks.d/vscode"
    vscode_aggregate_failure_marker=$vscode_aggregate_failure_home/mv-failed
    vscode_aggregate_failure_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_aggregate_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_MV_FAIL_ONCE_MARKER="$vscode_aggregate_failure_marker" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_settings_sources() { :; }
      _vscode_checkrun_settings() { printf "{}\n" >"$1"; }
      _remove_vscode_generated_checkrun_settings() { :; }
      _merge_vscode_settings() { :; }
      _merge_vscode_window_title() { :; }
      _merge_vscode_mcp_auth() { :; }
      _merge_vscode_config "$HOME/User"
    ' >/dev/null 2>&1 || vscode_aggregate_failure_rc=$?
    _assert_eq "vscode keybindings: aggregate rename failure propagates" \
      "1" "$vscode_aggregate_failure_rc"
    _assert_file_missing "vscode keybindings: aggregate failure writes no artifact" \
      "$vscode_aggregate_failure_home/User/keybindings.json"

    # A fragment is one reconciliation unit. Silently accepting only the first
    # of two JSON documents could drop active or retirement policy.
    cat >"$vscode_aggregate_failure_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid.jsonc" <<'JSON'
[]
[
  {
    "key": "ctrl+alt+9",
    "command": "fixture.hiddenSecondDocument",
    "when": "fixture.hiddenSecondDocument"
  }
]
JSON
    vscode_multi_fragment_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_aggregate_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_settings_sources() { :; }
      _vscode_checkrun_settings() { printf "{}\n" >"$1"; }
      _remove_vscode_generated_checkrun_settings() { :; }
      _merge_vscode_settings() { :; }
      _merge_vscode_window_title() { :; }
      _merge_vscode_mcp_auth() { :; }
      _merge_vscode_config "$HOME/User"
    ' >/dev/null 2>&1 || vscode_multi_fragment_rc=$?
    _assert_eq "vscode keybindings: multi-document source fragment fails closed" \
      "1" "$vscode_multi_fragment_rc"
    _assert_file_missing "vscode keybindings: invalid source fragment writes no artifact" \
      "$vscode_aggregate_failure_home/User/keybindings.json"

    printf '// comments only\n' \
      >"$vscode_aggregate_failure_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid.jsonc"
    vscode_empty_fragment_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_aggregate_failure_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_settings_sources() { :; }
      _vscode_checkrun_settings() { printf "{}\n" >"$1"; }
      _remove_vscode_generated_checkrun_settings() { :; }
      _merge_vscode_settings() { :; }
      _merge_vscode_window_title() { :; }
      _merge_vscode_mcp_auth() { :; }
      _merge_vscode_config "$HOME/User"
    ' >/dev/null 2>&1 || vscode_empty_fragment_rc=$?
    _assert_eq "vscode keybindings: empty source fragment fails closed" \
      "1" "$vscode_empty_fragment_rc"

    # A failed atomic replacement must leave the entire old generation intact;
    # the retry can then install V2 without reasoning about a partial array.
    vscode_destination_failure_dir=$(_tmpdir)
    cat >"$vscode_destination_failure_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+3",
    "command": "fixture.attemptedV1",
    "when": "fixture.attemptedV1"
  }
]
JSON
    printf '[]\n' \
      >"$vscode_destination_failure_dir/keybindings.json"
    vscode_destination_failure_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_MV_FAIL_SUFFIX="/keybindings.json" \
      DESTINATION_FAILURE_DIR="$vscode_destination_failure_dir" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$DESTINATION_FAILURE_DIR/source.json" \
        "$DESTINATION_FAILURE_DIR/keybindings.json" \
        linux
    ' >/dev/null 2>&1 || vscode_destination_failure_rc=$?
    _assert_eq "vscode keybindings: destination write failure propagates" \
      "1" "$vscode_destination_failure_rc"
    _assert_file_content "vscode keybindings: destination failure leaves old file intact" \
      '[]' \
      "$vscode_destination_failure_dir/keybindings.json"
    cat >"$vscode_destination_failure_dir/source.json" <<'JSON'
[
  {
    "key": "ctrl+alt+4",
    "command": "fixture.retriedV2",
    "when": "fixture.retriedV2"
  }
]
JSON
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" \
      DESTINATION_FAILURE_DIR="$vscode_destination_failure_dir" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _merge_vscode_keybindings \
        "$DESTINATION_FAILURE_DIR/source.json" \
        "$DESTINATION_FAILURE_DIR/keybindings.json" \
        linux
    '
    _assert_eq "vscode keybindings: retry installs latest generation only" \
      '["fixture.retriedV2"]' \
      "$(jq -c '[.[] | .command | select(startswith("fixture."))]' \
        "$vscode_destination_failure_dir/keybindings.json")"

    # --- MCP auth edge cases: scoping, corruption recovery, race safety ---
    vscode_mcp_edge_home=$(_tmpdir)

    # Cursor never installs nabheet.vscode-ide-mcp (the declarative marketplace
    # profiles target editor = "vscode"), so it must never receive the secret
    # setting.
    vscode_mcp_applicable_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_applicable "$HOME/Library/Application Support/Cursor/User/settings.json" && exit 1
      _vscode_mcp_auth_applicable "$HOME/.cursor-server/data/Machine/settings.json" && exit 1
      _vscode_mcp_auth_applicable "$HOME/.config/Code/User/settings.json" || exit 1
      exit 0
    ' || vscode_mcp_applicable_rc=$?
    _assert_eq "vscode mcp auth: Cursor variants are excluded from token injection" \
      "0" "$vscode_mcp_applicable_rc"

    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_mcp_relative_path=$(env HOME="$vscode_mcp_edge_home" \
      XDG_STATE_HOME=relative/state REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token_path
      printf "%s" "$REPLY"
    ')
    _assert_eq "vscode mcp auth: relative XDG state uses HOME fallback" \
      "$vscode_mcp_edge_home/.local/state/dot/vscode-mcp-auth-token" \
      "$vscode_mcp_relative_path"

    vscode_mcp_missing_path_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env -u HOME -u XDG_STATE_HOME REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token_path
    ' >/dev/null 2>&1 || vscode_mcp_missing_path_rc=$?
    _assert_eq "vscode mcp auth: missing state roots fail closed" \
      "1" "$vscode_mcp_missing_path_rc"

    vscode_mcp_newline_state=$(_tmpdir)/state$'\n'
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env -u HOME XDG_STATE_HOME="$vscode_mcp_newline_state" \
      REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token
    '
    _assert_file_exists "vscode mcp auth: absolute XDG state works without HOME" \
      "$vscode_mcp_newline_state/dot/vscode-mcp-auth-token"
    _assert_file_missing "vscode mcp auth: XDG trailing newline is not truncated" \
      "${vscode_mcp_newline_state%$'\n'}/dot/vscode-mcp-auth-token"

    # A partial write (disk-full, crash mid-printf) leaves a short, non-empty,
    # garbage token. A bare non-empty check would trust it forever; shape
    # validation must regenerate a proper 64-char hex token instead.
    mkdir -p "$vscode_mcp_edge_home/.local/state/dot"
    printf 'a3f' >"$vscode_mcp_edge_home/.local/state/dot/vscode-mcp-auth-token"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_mcp_malformed_token=$(env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token
      printf "%s" "$REPLY"
    ')
    if [[ "$vscode_mcp_malformed_token" =~ ^[0-9a-f]{64}$ ]]; then
      _pass "vscode mcp auth: malformed existing token is regenerated as valid hex64"
    else
      _fail "vscode mcp auth: malformed existing token is regenerated as valid hex64"
    fi

    # Race safety: launch two real concurrent processes racing on first-run
    # creation against the same fresh path (the cron + interactive dot
    # update scenario). The mkdir-based mutex should serialize them so both
    # observe the same final token rather than each installing a different
    # value into whatever settings.json happens to read it.
    rm -rf "$vscode_mcp_edge_home/.local/state/dot"
    vscode_mcp_race_out="$vscode_mcp_edge_home/race-out.txt"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" \
      TMPDIR="$_DOT_TEST_TMP_ROOT" bash -c '
      set -uo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      out1=$(mktemp); out2=$(mktemp)
      ( _vscode_mcp_auth_token && printf "%s" "$REPLY" >"$out1" ) &
      pid1=$!
      ( _vscode_mcp_auth_token && printf "%s" "$REPLY" >"$out2" ) &
      pid2=$!
      wait "$pid1" "$pid2"
      cat "$out1"; printf "\n"; cat "$out2"
      rm -f "$out1" "$out2"
    ' >"$vscode_mcp_race_out" 2>/dev/null
    vscode_mcp_race_line1=$(sed -n 1p "$vscode_mcp_race_out")
    vscode_mcp_race_line2=$(sed -n 2p "$vscode_mcp_race_out")
    _assert_eq "vscode mcp auth: concurrent first-run creation converges on one shared token" \
      "$vscode_mcp_race_line1" "$vscode_mcp_race_line2"
    if [[ "$vscode_mcp_race_line1" =~ ^[0-9a-f]{64}$ ]]; then
      _pass "vscode mcp auth: concurrent creation still produces a valid hex64 token"
    else
      _fail "vscode mcp auth: concurrent creation still produces a valid hex64 token"
    fi

    # Lock ownership: a process that times out waiting for a lock it never
    # acquired must NOT rmdir it out from under whoever actually holds it —
    # that would let a third racer sneak in and break their mutual exclusion
    # too. Pre-hold the lock with a fresh mtime (not stale) so the callee is
    # forced through the ~2s give-up-and-proceed-unlocked path, then assert
    # the lock this process never owned is still standing afterward.
    rm -rf "$vscode_mcp_edge_home/.local/state/dot"
    mkdir -p "$vscode_mcp_edge_home/.local/state/dot"
    vscode_mcp_foreign_lock="$vscode_mcp_edge_home/.local/state/dot/vscode-mcp-auth-token.lock"
    mkdir "$vscode_mcp_foreign_lock"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { :; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token || true
    '
    if [[ -d "$vscode_mcp_foreign_lock" ]]; then
      _pass "vscode mcp auth: giving up on a foreign lock does not release it"
    else
      _fail "vscode mcp auth: giving up on a foreign lock does not release it"
    fi
    rmdir "$vscode_mcp_foreign_lock" 2>/dev/null

    # A silent {} on generation failure would leave the extension installed
    # and unauthenticated with no trace. The security gap must be _warn'd.
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    vscode_mcp_warn_output=$(env HOME="$vscode_mcp_edge_home" REAL_HOME="$REAL_HOME" \
      TMPDIR="$_DOT_TEST_TMP_ROOT" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      _warn() { printf "%s\n" "$*"; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_mcp_auth_token() { return 1; }
      out=$(mktemp)
      _vscode_mcp_auth_settings "$out"
      cat "$out"
      rm -f "$out"
    ' 2>&1)
    _assert_contains "vscode mcp auth: generation failure is warned, not silent" \
      "warning: could not generate vscode-mcp-server auth token" "$vscode_mcp_warn_output"
    _assert_contains "vscode mcp auth: generation failure still emits a valid empty settings layer" \
      '{}' "$vscode_mcp_warn_output"

    # Regression: VS Code variant overlays can declare a WSL-platform
    # variant with an arbitrary config_dir (that's the whole point of the
    # mechanism — see merge-hooks.d/README.md). A future overlay pointing one
    # at the native Windows profile must not bypass account pairing just
    # because it comes through this overlay path instead of the built-in
    # appdata resolver.
    vscode_native_variant_home=$(_tmpdir)
    mkdir -p "$vscode_native_variant_home/.config/dot/merge-hooks.d/vscode/variants.d"
    native_marker="$vscode_native_variant_home/native-marker"
    native_ext_dir="$vscode_native_variant_home/native-ext"
    native_cfg_dir="$vscode_native_variant_home/native-cfg"
    touch "$native_marker"
    mkdir -p "$native_cfg_dir"
    cat >"$vscode_native_variant_home/.config/dot/merge-hooks.d/vscode/variants.d/80-native-test.tsv" <<EOF
# platform	marker	extensions_dir	config_dir	options
WSL	$native_marker	$native_ext_dir	$native_cfg_dir	-
EOF

    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    native_variant_paired=$(HOME="$vscode_native_variant_home" REAL_HOME="$REAL_HOME" \
      DOT_TEST=1 DOT_TEST_WSL_PAIRED_ACCOUNT=1 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_variants
      ')
    _assert_contains "vscode wsl variant overlay: paired account sees native-platform TSV variant" \
      "$native_cfg_dir" "$native_variant_paired"

    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    native_variant_unpaired=$(HOME="$vscode_native_variant_home" REAL_HOME="$REAL_HOME" \
      DOT_TEST=1 DOT_TEST_WSL_PAIRED_ACCOUNT=0 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_variants
      ')
    _assert_not_contains "vscode wsl variant overlay: unpaired account skips native-platform TSV variant" \
      "$native_cfg_dir" "$native_variant_unpaired"

    # Regression: _vscode_expand_path's ~ and ~/* case patterns were
    # unescaped, so bash tilde-expanded them to the live $HOME before pattern
    # matching. That made them also match an already-absolute path that
    # simply happens to live under $HOME (exactly what a TSV overlay author
    # would write instead of the $HOME/~ placeholder syntax), silently
    # double-prefixing it with $HOME again.
    expand_path_home=$(_tmpdir)
    expand_path_absolute="$expand_path_home/.vscode/extensions"
    expand_path_result=$(HOME="$expand_path_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_expand_path "$1"
    ' _ "$expand_path_absolute")
    _assert_eq "vscode expand path: absolute path under HOME is left unchanged" \
      "$expand_path_absolute" "$expand_path_result"

    expand_path_tilde_result=$(HOME="$expand_path_home" REAL_HOME="$REAL_HOME" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_expand_path "~/.vscode/extensions"
    ')
    _assert_eq "vscode expand path: ~/ placeholder still expands to HOME" \
      "$expand_path_home/.vscode/extensions" "$expand_path_tilde_result"

    # Regression: tracked config transactions used to publish the
    # managed-stripped baseline to the live files on every run, so file
    # watchers (VS Code's restart prompt) saw managed settings vanish and
    # reappear each cycle. Converged runs must leave both files untouched.
    vscode_tracked_home=$(_tmpdir)
    vscode_tracked_cfg=$vscode_tracked_home/.config/Code/User
    mkdir -p \
      "$vscode_tracked_cfg" \
      "$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/settings.d" \
      "$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d" \
      "$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/keybindings/linux.d" \
      "$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/keybindings/macos.d" \
      "$vscode_tracked_home/.local/state"
    cat >"$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/settings.d/10-tracked.json" <<'JSON'
{
  "fixture.managed": true
}
JSON
    cat >"$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/10-tracked.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+9",
    "command": "fixture.trackedBinding"
  }
]
JSON
    printf '[]\n' >"$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/keybindings/linux.d/10-tracked.jsonc"
    printf '[]\n' >"$vscode_tracked_home/.config/dot/merge-hooks.d/vscode/keybindings/macos.d/10-tracked.jsonc"
    printf '%s\n' '{"fixture.local":1}' >"$vscode_tracked_cfg/settings.json"
    printf '[]\n' >"$vscode_tracked_cfg/keybindings.json"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    HOME="$vscode_tracked_home" REAL_HOME="$REAL_HOME" DOT_TEST=1 \
      XDG_STATE_HOME="$vscode_tracked_home/.local/state" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _merge_vscode_config_tracked "$HOME/.config/Code/User" ""
      '
    _assert_eq "vscode tracked config: managed settings converge" \
      "true" "$(jq -r '."fixture.managed"' "$vscode_tracked_cfg/settings.json")"
    _assert_eq "vscode tracked config: local settings survive" \
      "1" "$(jq -r '."fixture.local"' "$vscode_tracked_cfg/settings.json")"
    vscode_tracked_settings_identity=$(stat -c '%i:%Y' "$vscode_tracked_cfg/settings.json" 2>/dev/null ||
      stat -f '%i:%m' "$vscode_tracked_cfg/settings.json")
    vscode_tracked_keybindings_identity=$(stat -c '%i:%Y' "$vscode_tracked_cfg/keybindings.json" 2>/dev/null ||
      stat -f '%i:%m' "$vscode_tracked_cfg/keybindings.json")
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    HOME="$vscode_tracked_home" REAL_HOME="$REAL_HOME" DOT_TEST=1 \
      XDG_STATE_HOME="$vscode_tracked_home/.local/state" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _merge_vscode_config_tracked "$HOME/.config/Code/User" ""
      '
    _assert_eq "vscode tracked config: converged rerun leaves settings.json untouched" \
      "$vscode_tracked_settings_identity" "$(stat -c '%i:%Y' "$vscode_tracked_cfg/settings.json" 2>/dev/null ||
        stat -f '%i:%m' "$vscode_tracked_cfg/settings.json")"
    _assert_eq "vscode tracked config: converged rerun leaves keybindings.json untouched" \
      "$vscode_tracked_keybindings_identity" "$(stat -c '%i:%Y' "$vscode_tracked_cfg/keybindings.json" 2>/dev/null ||
        stat -f '%i:%m' "$vscode_tracked_cfg/keybindings.json")"

    # Same no-churn guarantee for the remote Machine settings transaction,
    # which stages title and token settings through the same deferred flow.
    vscode_tracked_remote_home=$(_tmpdir)
    vscode_tracked_remote_cfg=$vscode_tracked_remote_home/.vscode-remote/data/Machine
    mkdir -p "$vscode_tracked_remote_cfg" "$vscode_tracked_remote_home/.local/state"
    printf '%s\n' '{"fixture.local":1}' >"$vscode_tracked_remote_cfg/settings.json"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    HOME="$vscode_tracked_remote_home" REAL_HOME="$REAL_HOME" DOT_TEST=1 \
      XDG_STATE_HOME="$vscode_tracked_remote_home/.local/state" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _merge_vscode_remote_settings_tracked "$HOME/.vscode-remote/data/Machine"
      '
    _assert_eq "vscode tracked remote config: window title converges" \
      "true" "$(jq -r 'has("window.title")' "$vscode_tracked_remote_cfg/settings.json")"
    _assert_eq "vscode tracked remote config: local settings survive" \
      "1" "$(jq -r '."fixture.local"' "$vscode_tracked_remote_cfg/settings.json")"
    vscode_tracked_remote_identity=$(stat -c '%i:%Y' "$vscode_tracked_remote_cfg/settings.json" 2>/dev/null ||
      stat -f '%i:%m' "$vscode_tracked_remote_cfg/settings.json")
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    HOME="$vscode_tracked_remote_home" REAL_HOME="$REAL_HOME" DOT_TEST=1 \
      XDG_STATE_HOME="$vscode_tracked_remote_home/.local/state" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _merge_vscode_remote_settings_tracked "$HOME/.vscode-remote/data/Machine"
      '
    _assert_eq "vscode tracked remote config: converged rerun leaves settings.json untouched" \
      "$vscode_tracked_remote_identity" "$(stat -c '%i:%Y' "$vscode_tracked_remote_cfg/settings.json" 2>/dev/null ||
        stat -f '%i:%m' "$vscode_tracked_remote_cfg/settings.json")"
  else
    echo "  SKIP: VS Code merge hook unit assertions (jq unavailable)"
  fi
  _test_summary
}
