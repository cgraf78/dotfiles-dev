# shellcheck shell=bash
# VS Code merge-hook lifecycle: the serial chain of full merges on one
# fixture home, from the first merge through the history retirement, the
# macOS, extension-only, and opt-out variants, and the WSL pairing cases.
# Each step reads the state the previous ones left, so the chain stays in
# one suite. Cases that need only the fresh fixture or its first merge run
# in sibling suites that `dot test` overlaps with this one:
#   - vscode-merges-rerun.sh: repeat, failure, and shared-config merges
#     from the state right after the first merge;
#   - vscode-merges-units.sh: the retirement guard and the hook units;
#   - vscode-merges-providers.sh: remote schemas and provider extensions;
#   - vscode-signature-merges.sh: the unchanged-update signature.

# The shared fixture in vscode-merges-setup.sh assigns vscode_home,
# vscode_bin, vscode_mv_log, and the receipt and title expectations; a
# standalone check cannot see those writes.
# shellcheck disable=SC2154

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"
# shellcheck source-path=SCRIPTDIR source=vscode-merges-setup.sh
. "${BASH_SOURCE[0]%/*}/vscode-merges-setup.sh"

dot_dev_vscode_merges_test() {
  _dev_vscode_merges_setup || return
  echo "=== VS Code Sley merge hook ==="

  if command -v jq >/dev/null 2>&1; then
    _assert_vscode_macos_ctrl_arrow_keybindings() {
      local keybindings_file="$1"
      local keybindings

      keybindings=$(
        jq -c '
          map(select(.when == "editorTextFocus"))
          | map(select(.key as $key | [
              "ctrl+left",
              "ctrl+right",
              "ctrl+shift+left",
              "ctrl+shift+right",
              "ctrl+shift+up",
              "ctrl+shift+down"
            ] | index($key)))
        ' "$keybindings_file"
      )

      _assert_contains "vscode mac editor: Ctrl+Left moves word-left" \
        '{"command":"cursorWordStartLeft","key":"ctrl+left","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Right moves word-right" \
        '{"command":"cursorWordEndRight","key":"ctrl+right","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Shift+Left selects word-left" \
        '{"command":"cursorWordStartLeftSelect","key":"ctrl+shift+left","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Shift+Right selects word-right" \
        '{"command":"cursorWordEndRightSelect","key":"ctrl+shift+right","when":"editorTextFocus"}' \
        "$keybindings"
      _assert_contains "vscode mac editor: Ctrl+Shift+Up extends selection up" \
        '{"command":"cursorUpSelect","key":"ctrl+shift+up","when":"editorTextFocus"}' \
        "$keybindings"
      ctrl_shift_down_expected=$(
        jq -nc --arg key "ctrl+shift+down" \
          '{"command":"cursorDownSelect","key":$key,"when":"editorTextFocus"}'
      )
      _assert_contains "vscode mac editor: Ctrl+Shift+Down extends selection down" \
        "$ctrl_shift_down_expected" \
        "$keybindings"
    }

    _assert_vscode_macos_karabiner_terminal_keybindings() {
      local keybindings_file="$1"

      _assert_eq "vscode mac terminal: Karabiner Ctrl controls stay terminal-native" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "cmd+a", text: "\u0001"},
              {key: "cmd+b", text: "\u0002"},
              {key: "cmd+l", text: "\u000c"},
              {key: "cmd+n", text: "\u000e"},
              {key: "cmd+r", text: "\u0012"},
              {key: "cmd+u", text: "\u0015"},
              {key: "cmd+w", text: "\u0017"},
              {key: "cmd+z", text: "\u001a"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
      _assert_eq "vscode mac editor: Cmd+B keeps the native sidebar binding" \
        "0" \
        "$(jq '[.[] | select(
          .key == "cmd+b"
          and (
            .command == "-workbench.action.toggleSidebarVisibility"
            or .command == "workbench.action.toggleSidebarVisibility"
          )
        )] | length' "$keybindings_file")"

      _assert_eq "vscode mac terminal: Cmd+V pastes outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+v" and .command == "workbench.action.terminal.paste" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+V reaches nvim after Karabiner translates Ctrl+V" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+v" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0016")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Ctrl+Shift+V transport pastes without focused nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "f20" and .command == "workbench.action.terminal.paste" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode mac editor: Ctrl+Shift+V transport preserves Windows-style paste" \
        "1" \
        "$(jq '[.[] | select(.key == "f20" and .command == "editor.action.clipboardPasteAction" and .when == "textInputFocus && !editorReadonly && !terminalFocus")] | length' "$keybindings_file")"
      _assert_eq "vscode mac: native Shift+Cmd+V stays unmanaged" \
        "0" \
        "$(jq '[.[] | select(.key == "shift+cmd+v")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+C copies a Karabiner-translated selection" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+c" and .command == "workbench.action.terminal.copySelection" and .when == "terminalFocus && terminalTextSelected")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+C reaches nvim when no text is selected" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+c" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && !terminalTextSelected" and .args.text == "\u0003")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+P opens VS Code quick open outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+p" and .command == "workbench.action.quickOpen" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Cmd+P reaches nvim after Karabiner translates Ctrl+P" \
        "1" \
        "$(jq '[.[] | select(.key == "cmd+p" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0010")] | length' "$keybindings_file")"
      _assert_eq "vscode mac terminal: every Karabiner-translated Ctrl letter reaches focused nvim" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "cmd+f", text: "\u0006"},
              {key: "cmd+g", text: "\u0007"},
              {key: "cmd+i", text: "\u0009"},
              {key: "cmd+o", text: "\u000f"},
              {key: "cmd+p", text: "\u0010"},
              {key: "cmd+s", text: "\u0013"},
              {key: "cmd+t", text: "\u0014"},
              {key: "cmd+v", text: "\u0016"},
              {key: "cmd+x", text: "\u0018"},
              {key: "cmd+y", text: "\u0019"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus && termnav.nvimFocused"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
      _assert_eq "vscode mac terminal: Karabiner-translated shifted chords reach focused nvim" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "shift+cmd+f", text: "\u001b[102;6u"},
              {key: "shift+cmd+g", text: "\u001b[103;6u"},
              {key: "shift+cmd+p", text: "\u001b[112;6u"},
              {key: "f20", text: "\u001b[118;6u"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus && termnav.nvimFocused"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
    }

    _assert_vscode_macos_pane_move_keybindings() {
      local keybindings_file="$1"

      _assert_eq "vscode mac terminal: Karabiner pane transports send exact escape sequences" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "f16", text: "\u001bH"},
                {key: "f17", text: "\u001bJ"},
                {key: "f18", text: "\u001bK"},
                {key: "f19", text: "\u001bL"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode mac editor: Karabiner pane transports move editor groups" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "f16", command: "workbench.action.moveActiveEditorGroupLeft"},
                {key: "f17", command: "workbench.action.moveActiveEditorGroupDown"},
                {key: "f18", command: "workbench.action.moveActiveEditorGroupUp"},
                {key: "f19", command: "workbench.action.moveActiveEditorGroupRight"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == $wanted.command
                    and .when == "editorFocus && !terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode mac: F16-F19 have only terminal and editor pane routes" \
        "8" \
        "$(jq '[.[] | select(.key == "f16" or .key == "f17" or .key == "f18" or .key == "f19")] | length' "$keybindings_file")"
    }

    _assert_vscode_focus_fallback_keybindings() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: tmux prefix is extension-independent" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+b"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u0002"
          and .when == "terminalFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: tmux prefix has no focus-only duplicate" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+b"
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: explicit tmux pane controls are extension-independent" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "ctrl+h", text: "\u0008"},
                {key: "ctrl+k", text: "\u000b"},
                {key: "ctrl+l", text: "\u000c"},
                {key: "ctrl+\\", text: "\u001c"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+J avoids sendSequence newline normalization" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+j"
          and .command == "workbench.action.terminal.sendSequence"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: tmux pane navigation has no focus-only duplicates" \
        "0" \
        "$(jq '[.[] | select(
          (.key == "ctrl+h" or .key == "ctrl+j" or .key == "ctrl+k" or .key == "ctrl+l" or .key == "ctrl+\\")
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: pane movement has exact escape transports" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "alt+shift+h", text: "\u001bH"},
                {key: "alt+shift+j", text: "\u001bJ"},
                {key: "alt+shift+k", text: "\u001bK"},
                {key: "alt+shift+l", text: "\u001bL"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      if [[ $platform == "macOS" ]]; then
        _assert_vscode_macos_pane_move_keybindings "$keybindings_file"
      else
        _assert_eq "vscode $platform: macOS pane transport keys stay absent" \
          "0" \
          "$(jq '[.[] | select(.key == "f16" or .key == "f17" or .key == "f18" or .key == "f19")] | length' "$keybindings_file")"
      fi
      _assert_eq "vscode $platform terminal: Ctrl+/ transport is extension-independent" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "ctrl+/", text: "\u001f"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+/ transport has no focus-only duplicate" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+/"
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: synced macOS Ctrl+/ generation is retired" \
        "0" \
        "$(jq '[.[] | select(
          .key == "cmd+/"
          and .command == "workbench.action.terminal.sendSequence"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"

      if [[ "$platform" == "macOS" ]]; then
        _assert_eq "vscode macOS terminal: Cmd+J keeps native workbench ownership" \
          "0" \
          "$(jq '[.[] | select(
            .key == "cmd+j"
            and ((.when // "") | contains("terminalFocus"))
          )] | length' "$keybindings_file")"
        _assert_eq "vscode macOS terminal: Ctrl-backslash needs no invented Cmd translation" \
          "0" \
          "$(jq '[.[] | select(
            .key == "cmd+\\"
            and .command == "workbench.action.terminal.sendSequence"
          )] | length' "$keybindings_file")"
        _assert_eq "vscode macOS terminal: Karabiner-translated Ctrl+/ is extension-independent" \
          "1" \
          "$(jq '[.[] | select(
            .key == "cmd+/"
            and .command == "workbench.action.terminal.sendSequence"
            and .args.text == "\u001f"
            and .when == "terminalFocus"
          )] | length' "$keybindings_file")"
      fi

      _assert_eq "vscode terminal toggle: editor route excludes terminal focus" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.terminal.focus"
          and .when == "terminalIsOpen && !terminalFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode terminal toggle: host route excludes focused nvim" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.focusActiveEditorGroup"
          and .when == "terminalFocus && terminalIsOpen && !termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode terminal toggle: focused nvim receives Ctrl+backtick" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u001b[96;5u"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode terminal toggle: focused nvim has no legacy NUL route" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+`"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u0000"
          and .when == "terminalFocus && termnav.nvimFocused"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform fallback: negated Termnav routes stay allowlisted" \
        '[]' \
        "$(jq -c --arg platform "$platform" '
          def route: {key, command, when};
          (
            [
              {
                key: "ctrl+`",
                command: "workbench.action.focusActiveEditorGroup",
                when: "terminalFocus && terminalIsOpen && !termnav.nvimFocused"
              },
              {
                key: "ctrl+p",
                command: "workbench.action.quickOpen",
                when: "terminalFocus && !termnav.nvimFocused"
              },
              {
                key: "ctrl+v",
                command: "workbench.action.terminal.paste",
                when: "terminalFocus && !termnav.nvimFocused"
              }
            ]
            + if $platform == "macOS" then
                [
                  {
                    key: "cmd+p",
                    command: "workbench.action.quickOpen",
                    when: "terminalFocus && !termnav.nvimFocused"
                  },
                  {
                    key: "cmd+v",
                    command: "workbench.action.terminal.paste",
                    when: "terminalFocus && !termnav.nvimFocused"
                  },
                  {
                    key: "f20",
                    command: "workbench.action.terminal.paste",
                    when: "terminalFocus && !termnav.nvimFocused"
                  }
                ]
              else [] end
          ) as $allowed
          | ([
              .[]
              | select((.when // "") | contains("!termnav.nvimFocused"))
              | route
            ] | unique) as $actual
          | (($actual - $allowed) + ($allowed - $actual) | unique)
        ' "$keybindings_file")"
      _assert_eq "vscode focused nvim: application-aware chords stay positive-only" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
            [
              {key: "ctrl+.", text: "\u001b[46;5u"},
              {key: "ctrl+shift+e", text: "\u001b[101;6u"},
              {key: "ctrl+shift+f", text: "\u001b[102;6u"},
              {key: "ctrl+shift+m", text: "\u001b[109;6u"},
              {key: "ctrl+shift+p", text: "\u001b[112;6u"},
              {key: "shift+pageup", text: "\u001b[5;2~"},
              {key: "shift+pagedown", text: "\u001b[6;2~"}
            ][]
          )
          | . as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus && termnav.nvimFocused"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]
        ' "$keybindings_file")"
    }

    _assert_vscode_terminal_clipboard_keybindings() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: Ctrl+C copies only selected text" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+c" and .command == "workbench.action.terminal.copySelection" and .when == "terminalFocus && terminalTextSelected")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+C keeps interrupt behavior without a selection" \
        "2" \
        "$(jq '[.[] | select(.key == "ctrl+c")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+V pastes outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+v" and .command == "workbench.action.terminal.paste" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+V reaches nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+v" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0016")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+P opens VS Code quick open outside nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+p" and .command == "workbench.action.quickOpen" and .when == "terminalFocus && !termnav.nvimFocused")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+P reaches nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+p" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0010")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+F reaches nvim" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+f" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u0006")] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: synthesized Ctrl letters exclude native Ctrl+J" \
        "25" \
        "$(jq '[
          .[]
          | select(.key | test("^ctrl\\+[a-z]$"))
          | select(
              .command == "workbench.action.terminal.sendSequence"
              and (
                .when == "terminalFocus"
                or (.when | contains("termnav.nvimFocused"))
              )
            )
        ] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: Ctrl+Shift+G reaches nvim distinctly" \
        "1" \
        "$(jq '[.[] | select(.key == "ctrl+shift+g" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus && termnav.nvimFocused" and .args.text == "\u001b[103;6u")] | length' "$keybindings_file")"
    }

    _assert_vscode_terminal_native_settings() {
      local settings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: Ctrl+J bypasses the workbench panel shortcut once" \
        "1" \
        "$(jq '[.["terminal.integrated.commandsToSkipShell"][]? | select(
          . == "-workbench.action.togglePanel"
        )] | length' "$settings_file")"
      _assert_eq "vscode $platform terminal: positive panel skip cannot override Ctrl+J passthrough" \
        "0" \
        "$(jq '[.["terminal.integrated.commandsToSkipShell"][]? | select(
          . == "workbench.action.togglePanel"
        )] | length' "$settings_file")"
    }

    _assert_vscode_terminal_local_settings_preserved() {
      local settings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: local skip-shell policy survives Ctrl+J passthrough" \
        '["workbench.action.quickOpen","-local.terminalCommand","-workbench.action.togglePanel"]' \
        "$(jq -c '.["terminal.integrated.commandsToSkipShell"]' "$settings_file")"
    }

    _assert_vscode_focus_keybinding_migration() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform migration: stale Ctrl host actions are removed" \
        "0" \
        "$(jq '[.[] | select(.when == "terminalFocus") | select(
          (.key == "ctrl+p" and .command == "workbench.action.quickOpen")
          or (.key == "ctrl+v" and .command == "workbench.action.terminal.paste")
        )] | length' "$keybindings_file")"

      if [[ "$platform" == "macOS" ]]; then
        _assert_eq "vscode macOS migration: stale Cmd host actions are removed" \
          "0" \
          "$(jq '[.[] | select(.when == "terminalFocus") | select(
            (.key == "cmd+p" and .command == "workbench.action.quickOpen")
            or (.key == "cmd+v" and .command == "workbench.action.terminal.paste")
          )] | length' "$keybindings_file")"
        _assert_eq "vscode macOS migration: terminal-native Cmd routes are restored" \
          "8" \
          "$(jq '[.[] | select(.when == "terminalFocus")
            | select(.command == "workbench.action.terminal.sendSequence")
            | select(.key as $key | [
              "cmd+a", "cmd+b", "cmd+l", "cmd+n",
              "cmd+r", "cmd+u", "cmd+w", "cmd+z"
            ] | index($key))
          ] | length' "$keybindings_file")"
      else
        # Settings Sync can carry an exact macOS generation into another
        # platform's file. Central retirement intentionally removes those known
        # objects everywhere; a near-match remains local and is tested below.
        _assert_eq "vscode $platform migration: synced stale Cmd host actions are removed" \
          "0" \
          "$(jq '[.[] | select(.when == "terminalFocus") | select(
            (.key == "cmd+p" and .command == "workbench.action.quickOpen")
            or (.key == "cmd+v" and .command == "workbench.action.terminal.paste")
          )] | length' "$keybindings_file")"
        _assert_eq "vscode $platform migration: synced stale Cmd terminal routes are removed" \
          "0" \
          "$(jq '[.[] | select(.when == "terminalFocus")
            | select(.command == "workbench.action.terminal.sendSequence")
            | select(.key as $key | [
              "cmd+a", "cmd+b", "cmd+l", "cmd+n",
              "cmd+r", "cmd+u", "cmd+w", "cmd+z"
            ] | index($key))
          ] | length' "$keybindings_file")"
      fi

      _assert_eq "vscode $platform migration: near-match Cmd local binding is preserved" \
        "1" \
        "$(jq '[.[] | select(
          .key == "cmd+p"
          and .command == "workbench.action.quickOpen"
          and .when == "terminalFocus && localTerminalMode"
        )] | length' "$keybindings_file")"
    }

    _assert_vscode_keybinding_precedence() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform terminal: exact legacy Ctrl-Tab handler is retired" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+tab"
          and .command == "workbench.action.terminal.focusNext"
          and .when == "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: managed Ctrl-Tab wins over a local near-match" \
        '["workbench.action.terminal.focusNext","workbench.action.terminal.sendSequence"]' \
        "$(jq -c '[.[] | select(.key == "ctrl+tab" and (.command == "workbench.action.terminal.focusNext" or .command == "workbench.action.terminal.sendSequence")) | .command]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: exact legacy Ctrl-Shift-Tab handler is retired" \
        "0" \
        "$(jq '[.[] | select(
          .key == "ctrl+shift+tab"
          and .command == "workbench.action.terminal.focusPrevious"
          and .when == "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: managed Ctrl-Shift-Tab wins over a local near-match" \
        '["workbench.action.terminal.focusPrevious","workbench.action.terminal.sendSequence"]' \
        "$(jq -c '[.[] | select(.key == "ctrl+shift+tab" and (.command == "workbench.action.terminal.focusPrevious" or .command == "workbench.action.terminal.sendSequence")) | .command]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: tab routes are terminal-native" \
        '[]' \
        "$(jq -c '[
          . as $bindings
          | (
              [
                {key: "ctrl+tab", text: "\u001b[9;5u"},
                {key: "ctrl+shift+tab", text: "\u001b[9;6u"}
              ][]
            ) as $wanted
          | select(
              [
                $bindings[]
                | select(
                    .key == $wanted.key
                    and .command == "workbench.action.terminal.sendSequence"
                    and .args.text == $wanted.text
                    and .when == "terminalFocus"
                  )
              ]
              | length != 1
            )
          | $wanted.key
        ]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: every tab sequence is adapter-independent" \
        "0" \
        "$(jq '[.[] | select(
          (.key == "ctrl+tab" or .key == "ctrl+shift+tab")
          and .command == "workbench.action.terminal.sendSequence"
          and .when != "terminalFocus"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform editor: native tab defaults have no managed shadow" \
        "0" \
        "$(jq '[.[] | select(
          [.key, .command, (.when // "")] as $route
          | [
              ["ctrl+shift+tab", "workbench.action.quickOpenLeastRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty && !terminalFocus"],
              ["ctrl+shift+tab", "-workbench.action.quickOpenLeastRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty"],
              ["ctrl+tab", "workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty && !terminalFocus"],
              ["ctrl+tab", "-workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup", "!activeEditorGroupEmpty"],
              ["ctrl+tab", "workbench.action.quickOpenNavigateNextInEditorPicker", "inEditorsPicker && inQuickOpen && !terminalFocus"],
              ["ctrl+tab", "-workbench.action.quickOpenNavigateNextInEditorPicker", "inEditorsPicker && inQuickOpen"],
              ["ctrl+shift+tab", "workbench.action.quickOpenNavigatePreviousInEditorPicker", "inEditorsPicker && inQuickOpen && !terminalFocus"],
              ["ctrl+shift+tab", "-workbench.action.quickOpenNavigatePreviousInEditorPicker", "inEditorsPicker && inQuickOpen"]
            ]
            | any(.[]; . == $route)
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: unrelated local overlap retains precedence" \
        '["workbench.action.terminal.paste","local.terminalPasteOverride"]' \
        "$(jq -c '[.[] | select(.key == "ctrl+v" and (.command == "workbench.action.terminal.paste" or .command == "local.terminalPasteOverride")) | .command]' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: same command with different args stays local" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+p"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u001b[local-action"
          and .when == "terminalFocus && localTerminalMode"
        )] | length' "$keybindings_file")"
      _assert_eq "vscode $platform terminal: same managed action under a local condition survives" \
        "1" \
        "$(jq '[.[] | select(
          .key == "ctrl+p"
          and .command == "workbench.action.terminal.sendSequence"
          and .args.text == "\u0010"
          and .when == "terminalFocus && localTerminalMode"
        )] | length' "$keybindings_file")"
    }

    _assert_vscode_native_tab_handling() {
      local keybindings_file="$1"
      local platform="$2"

      _assert_eq "vscode $platform: no-termnav keeps terminal-native and local tab routes only" \
        '[]' \
        "$(jq -c '
          [
            .[]
            | select(.key == "ctrl+tab" or .key == "ctrl+shift+tab")
            | {key, command, when: (.when // "")}
          ] as $actual
          | [
              {
                key: "ctrl+tab",
                command: "workbench.action.terminal.focusNext",
                when: "terminalFocus && localTerminalMode"
              },
              {
                key: "ctrl+shift+tab",
                command: "workbench.action.terminal.focusPrevious",
                when: "terminalFocus && localTerminalMode"
              },
              {
                key: "ctrl+tab",
                command: "workbench.action.terminal.sendSequence",
                when: "terminalFocus"
              },
              {
                key: "ctrl+shift+tab",
                command: "workbench.action.terminal.sendSequence",
                when: "terminalFocus"
              }
            ] as $expected
          | (($actual - $expected) + ($expected - $actual) | unique)
        ' "$keybindings_file")"
    }

    _dev_vscode_merges_fixture

    _dev_vscode_fixture_merge
    _dev_vscode_fixture_expectations
    _assert_file_exists "vscode settings: records reversible ownership" \
      "$vscode_receipt_root/$vscode_settings_key.json"
    vscode_keybindings_path=$vscode_home/.config/Code/User/keybindings.json
    vscode_keybindings_key=$(printf '%s\n%s\n' vscode-keybindings \
      "$vscode_keybindings_path" | git hash-object --stdin)
    _assert_file_exists "vscode keybindings: records reversible ownership" \
      "$vscode_receipt_root/$vscode_keybindings_key.json"
    vscode_extensions_path=$vscode_home/.vscode/extensions/extensions.json
    vscode_extensions_key=$(printf '%s\n%s\n' vscode-extensions \
      "$vscode_extensions_path" | git hash-object --stdin)
    _assert_file_exists "vscode extensions: records reversible ownership" \
      "$vscode_receipt_root/$vscode_extensions_key.json"
    _assert_eq "vscode extensions: receipt records each managed link" '2' \
      "$(jq '.links | length' \
        "$vscode_receipt_root/$vscode_extensions_key.json")"
    _assert_vscode_focus_keybinding_migration \
      "$vscode_home/.config/Code/User/keybindings.json" \
      "linux"
    # Each layer is prepended for compatibility with VS Code's bottom-up user
    # binding resolution. Check both lexical ordering inside all.d and the
    # platform family's precedence over the completed common aggregate.
    _assert_eq "vscode keybindings: later fragments and platform family retain precedence" \
      "true" \
      "$(jq '
        map(.command) as $commands
        | ($commands | index("fixture.orderPlatform")) as $platform
        | ($commands | index("fixture.orderCommonLater")) as $common_later
        | ($commands | index("fixture.orderCommonEarlier")) as $common_earlier
        | $platform < $common_later and $common_later < $common_earlier
      ' "$vscode_home/.config/Code/User/keybindings.json")"

    vscode_settings=$(jq -c . "$vscode_home/.config/Code/User/settings.json")
    _assert_contains "vscode sley: python uses local formatter" \
      '"editor.defaultFormatter":"cgraf.sley-tools"' "$vscode_settings"
    _assert_contains "vscode sley: generated format-on-save enabled" \
      '"editor.formatOnSave":true' "$vscode_settings"
    _assert_contains "vscode sley: shellscript mapping generated" \
      '"[shellscript]"' "$vscode_settings"
    _assert_contains "vscode sley: starlark mapping generated" \
      '"[bzl]"' "$vscode_settings"
    _assert_contains "vscode sley: generated settings preserve static python options" \
      '"editor.tabSize":4' "$vscode_settings"
    _assert_not_contains "vscode sley: lint-only filetypes are not format providers" \
      '"[makefile]"' "$vscode_settings"
    _assert_not_contains "vscode settings: stale isort setting is absent" \
      '"isort.args"' "$vscode_settings"
    _assert_contains "vscode terminal: native bell sound stays enabled" \
      '"accessibility.signals.terminalBell":{"sound":"on"}' "$vscode_settings"
    _assert_contains "vscode sley: exact filename association generated" \
      '".editorconfig":"editorconfig"' "$vscode_settings"
    _assert_contains "vscode sley: gitconfig association generated" \
      '".gitconfig":"gitconfig"' "$vscode_settings"
    _assert_contains "vscode sley: hgrc association generated" \
      '"*.hgrc":"ini"' "$vscode_settings"
    _assert_contains "vscode sley: ini association generated" \
      '"*.ini":"ini"' "$vscode_settings"
    _assert_contains "vscode sley: pathlist association generated" \
      '"*.pathlist":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: ssh-config association generated" \
      '"*.ssh-config":"ssh_config"' "$vscode_settings"
    _assert_contains "vscode sley: ssh_config association generated" \
      '"*.ssh_config":"ssh_config"' "$vscode_settings"
    _assert_contains "vscode sley: txt association generated" \
      '"*.txt":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: tsv association generated" \
      '"*.tsv":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: tmux association generated" \
      '"tmux.conf":"tmux"' "$vscode_settings"
    _assert_contains "vscode sley: build association generated" \
      '"BUILD":"starlark"' "$vscode_settings"
    _assert_contains "vscode sley: systemd extension association generated" \
      '"*.service":"systemd"' "$vscode_settings"
    _assert_contains "vscode sley: makefile extension association generated" \
      '"*.mak":"makefile"' "$vscode_settings"
    _assert_contains "vscode sley: pattern association generated" \
      '"WORKSPACE.*":"starlark"' "$vscode_settings"
    _assert_contains "vscode sley: agent target association generated" \
      '"*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.conf":"plaintext"' "$vscode_settings"
    _assert_contains "vscode sley: agent replace target association generated" \
      '"*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.replace/*.conf":"plaintext"' "$vscode_settings"
    _assert_contains "vscode schemas: Checkrun JSON schemas generated" \
      '"json.schemas":[{"fileMatch":[".sley/verify.json","**/.sley/verify.json"],"name":"Sley verify registry","url":"file:///mock/sley/verify.schema.json"}]' "$vscode_settings"
    _assert_contains "vscode schemas: Checkrun YAML schemas generated" \
      '"yaml.schemas":{"https://example.invalid/docker-compose.schema.json":["docker-compose.yml","**/docker-compose.yml"]}' "$vscode_settings"
    _assert_contains "vscode schemas: Checkrun TOML schemas generated" \
      '"evenBetterToml.schema.associations":{".*/pyproject\\.toml$":"https://example.invalid/pyproject.schema.json"}' "$vscode_settings"
    _assert_not_contains "vscode schemas: stale synced JSON schemas are pruned" \
      'stale-json' "$vscode_settings"
    _assert_not_contains "vscode schemas: stale synced YAML schemas are pruned" \
      'stale.yml' "$vscode_settings"
    _assert_not_contains "vscode schemas: stale synced TOML schemas are pruned" \
      'stale.toml' "$vscode_settings"
    # The fixture seeds stale generated schema settings as if a user wrote
    # them; the receipt's user-owned baseline must not adopt them, or profile
    # deactivation would restore the stale paths.
    _assert_eq "vscode schemas: receipt baseline holds no schema settings" \
      '[]' \
      "$(jq -c '.before | [keys[] | select(. == "json.schemas" or . == "yaml.schemas" or . == "evenBetterToml.schema.associations")]' \
        "$vscode_receipt_root/$vscode_settings_key.json")"
    _assert_not_contains "vscode schemas: generated settings omit absolute home paths" \
      '/Users/chris' "$vscode_settings"
    _assert_contains "vscode settings: C/C++ comment continuation is durable" \
      '"C_Cpp.commentContinuationPatterns":["// ","/**"]' "$vscode_settings"
    _assert_contains "vscode settings: C/C++ snippets stay disabled" \
      '"C_Cpp.suggestSnippets":false' "$vscode_settings"
    _assert_contains "vscode settings: prefixed settings layer is discovered" \
      '"dotfiles.prefixProbe":true' "$vscode_settings"
    _assert_eq "vscode settings: generated window title uses local host label" \
      "$vscode_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.config/Code/User/settings.json")"
    vscode_mcp_token_path="$vscode_home/.local/state/dot/vscode-mcp-auth-token"
    vscode_mcp_token_state=$(cat "$vscode_mcp_token_path" 2>/dev/null || true)
    vscode_mcp_token_setting=$(jq -r '.["vscode-mcp-server.authToken"] // empty' "$vscode_home/.config/Code/User/settings.json")
    _assert_eq "vscode mcp auth: generated token matches per-machine state file" \
      "$vscode_mcp_token_state" "$vscode_mcp_token_setting"
    if [[ -n "$vscode_mcp_token_setting" && ${#vscode_mcp_token_setting} -ge 32 ]]; then
      _pass "vscode mcp auth: token is non-trivial length"
    else
      _fail "vscode mcp auth: token is non-trivial length"
    fi
    vscode_mcp_token_perms=$(stat -c '%a' "$vscode_mcp_token_path" 2>/dev/null || stat -f '%Lp' "$vscode_mcp_token_path" 2>/dev/null)
    _assert_eq "vscode mcp auth: token state file is not group/world readable" \
      "600" "$vscode_mcp_token_perms"

    # The repeat, failure-propagation, and shared-config merges that start
    # from this post-merge state run in dev-vscode-merges-rerun-test.

    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/30-history-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+8",
    "command": "fixture.managedOld",
    "args": {"version": 1},
    "when": "fixture.managedOld",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+9",
    "command": "fixture.managedDeleted",
    "when": "fixture.managedDeleted",
    "dotfiles.retire": true
  },
  {
    "key": "ctrl+alt+0",
    "command": "fixture.managedNew",
    "args": {"version": 2},
    "when": "fixture.managedNew"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u0010"},
    "when": "terminalFocus && fixtureParallelSource"
  }
]
JSON
    vscode_visible_edit=$(_tmpfile)
    jq '. + [{
        "key": "ctrl+p",
        "command": "workbench.action.quickOpen",
        "when": "terminalFocus"
      }]' "$vscode_home/.config/Code/User/keybindings.json" \
      >"$vscode_visible_edit"
    mv "$vscode_visible_edit" \
      "$vscode_home/.config/Code/User/keybindings.json"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="fixture-host" bash -c '
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
      merge
    '
    _assert_eq "vscode keybindings: prior managed action is retired after arbitrary change" \
      "0" \
      "$(jq '[.[] | select(.command == "fixture.managedOld")] | length' \
        "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: deleted managed action is retired" \
      "0" \
      "$(jq '[.[] | select(.command == "fixture.managedDeleted")] | length' \
        "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: replacement managed action is installed" \
      "1" \
      "$(jq '[.[] | select(
        .key == "ctrl+alt+0"
        and .command == "fixture.managedNew"
        and .args.version == 2
        and .when == "fixture.managedNew"
      )] | length' "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: current fragments retain parallel conditions for one action" \
      "2" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.terminal.sendSequence"
        and .args.text == "\u0010"
        and (
          .when == "terminalFocus && termnav.nvimFocused"
          or .when == "terminalFocus && fixtureParallelSource"
        )
      )] | length' "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_eq "vscode keybindings: retired pre-provenance binding cannot be reintroduced" \
      "0" \
      "$(jq '[.[] | select(
        .key == "ctrl+p"
        and .command == "workbench.action.quickOpen"
        and .when == "terminalFocus"
      )] | length' "$vscode_home/.config/Code/User/keybindings.json")"
    _assert_vscode_keybinding_precedence \
      "$vscode_home/.config/Code/User/keybindings.json" \
      "linux post-history"

    # Retirement is destructive authority, so a nearly-correct directive must
    # fail closed. Treating a string as truthy here would permit an accidental
    # source typo to delete a user's exact local binding.
    cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid-retirement.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+9",
    "command": "fixture.invalidRetirement",
    "when": "fixture.invalidRetirement",
    "dotfiles.retire": "yes"
  }
]
JSON
    vscode_before_invalid_retirement=$(cat \
      "$vscode_home/.config/Code/User/keybindings.json")
    vscode_invalid_retirement_rc=0
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
    ' >/dev/null 2>&1 || vscode_invalid_retirement_rc=$?
    _assert_eq "vscode keybindings: malformed retirement directive fails closed" \
      "1" "$vscode_invalid_retirement_rc"
    _assert_file_content "vscode keybindings: malformed retirement leaves artifact unchanged" \
      "$vscode_before_invalid_retirement" \
      "$vscode_home/.config/Code/User/keybindings.json"
    rm "$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/99-invalid-retirement.jsonc"

    _assert_contains "vscode settings: bash LSP indexes shell-like files" \
      '"bashIde.globPattern":"**/*@(.sh|.inc|.bash|.zsh|.command)"' "$vscode_settings"
    _assert_contains "vscode settings: bash LSP uses PATH shfmt" \
      '"bashIde.shfmt.path":""' "$vscode_settings"
    _assert_contains "vscode settings: unchanged diff regions stay collapsed" \
      '"diffEditor.hideUnchangedRegions.enabled":true' "$vscode_settings"
    _assert_contains "vscode settings: copied text stays plain" \
      '"editor.copyWithSyntaxHighlighting":false' "$vscode_settings"
    _assert_contains "vscode settings: editor font size is durable" \
      '"editor.fontSize":11' "$vscode_settings"
    _assert_contains "vscode settings: linked editing is durable" \
      '"editor.linkedEditing":true' "$vscode_settings"
    _assert_contains "vscode settings: minimap stays disabled" \
      '"editor.minimap.enabled":false' "$vscode_settings"
    _assert_contains "vscode settings: line length ruler is durable" \
      '"editor.rulers":[100]' "$vscode_settings"
    _assert_contains "vscode settings: editor does not scroll past EOF" \
      '"editor.scrollBeyondLastLine":false' "$vscode_settings"
    _assert_contains "vscode settings: git autofetch is durable" \
      '"git.autofetch":true' "$vscode_settings"
    _assert_contains "vscode settings: git sync prompt stays disabled" \
      '"git.confirmSync":false' "$vscode_settings"
    _assert_contains "vscode settings: smart commit is enabled" \
      '"git.enableSmartCommit":true' "$vscode_settings"
    _assert_not_contains "vscode settings: personal remote SSH platform is absent" \
      '"remote.SSH.remotePlatform":{"private-host.example":"linux"}' \
      "$vscode_settings"
    _assert_contains "vscode settings: search smart case is enabled" \
      '"search.smartCase":true' "$vscode_settings"
    _assert_contains "vscode settings: search respects global ignores" \
      '"search.useGlobalIgnoreFiles":true' "$vscode_settings"
    _assert_contains "vscode settings: Settings Sync ignores generated schema paths" \
      '"settingsSync.ignoredSettings":["evenBetterToml.schema.associations","json.schemas","vscode-mcp-server.authToken","window.title","yaml.schemas"]' "$vscode_settings"
    _assert_contains "vscode settings: Sley diagnostics skip noisy HOME dependencies" \
      '"sleyTools.diagnosticExclude":[".vscode/extensions/**",".vscode-server/**","Downloads/**","**/node_modules/**"]' "$vscode_settings"
    _assert_contains "vscode settings: shell integration history is durable" \
      '"terminal.integrated.shellIntegration.history":10000' "$vscode_settings"
    _assert_not_contains "vscode settings: personal cmder profile is absent" \
      '"cmder":{"args":["/K","%CMDER_ROOT%\\vendor\\bin\\vscode_init.cmd"],"path":"C:\\WINDOWS\\System32\\cmd.exe"}' "$vscode_settings"
    _assert_not_contains "vscode settings: stale notebook association is absent" \
      '"workbench.editorAssociations"' "$vscode_settings"
    _assert_contains "vscode settings: editor labels omit path context" \
      '"workbench.editor.labelFormat":"default"' "$vscode_settings"
    _assert_contains "vscode settings: modified tabs stay visible" \
      '"workbench.editor.highlightModifiedTabs":true' "$vscode_settings"
    vscode_mv_ops=$(cat "$vscode_mv_log")
    _assert_contains "vscode sley: settings replacement uses forced mv" \
      "$vscode_home/.config/Code/User/settings.json" "$vscode_mv_ops"
    _assert_contains "vscode sley: keybindings replacement uses forced mv" \
      "$vscode_home/.config/Code/User/keybindings.json" "$vscode_mv_ops"
    sorted_settings=$(_tmpfile)
    jq --indent 4 --sort-keys '.' "$vscode_home/.config/Code/User/settings.json" >"$sorted_settings"
    if cmp -s "$sorted_settings" "$vscode_home/.config/Code/User/settings.json"; then
      _pass "vscode sley: saved settings are sorted"
    else
      _fail "vscode sley: saved settings are sorted"
    fi
    sorted_keybindings=$(_tmpfile)
    jq --indent 4 --sort-keys '.' \
      "$vscode_home/.config/Code/User/keybindings.json" \
      >"$sorted_keybindings"
    if cmp -s "$sorted_keybindings" "$vscode_home/.config/Code/User/keybindings.json"; then
      _pass "vscode sley: saved keybindings are sorted"
    else
      _fail "vscode sley: saved keybindings are sorted"
    fi
    vscode_keybindings_file="$vscode_home/.config/Code/User/keybindings.json"
    _assert_vscode_keybinding_precedence "$vscode_keybindings_file" "linux"
    _assert_eq "vscode terminal: Alt-Shift-[ sends tmux/nvim tab-move escape" \
      "1" \
      "$(jq '[.[] | select(.key == "alt+shift+[" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus" and .args.text == "\u001b{")] | length' "$vscode_keybindings_file")"
    _assert_eq "vscode terminal: Alt-Shift-] sends tmux/nvim tab-move escape" \
      "1" \
      "$(jq '[.[] | select(.key == "alt+shift+]" and .command == "workbench.action.terminal.sendSequence" and .when == "terminalFocus" and .args.text == "\u001b}")] | length' "$vscode_keybindings_file")"
    _assert_vscode_terminal_clipboard_keybindings "$vscode_keybindings_file" "linux"
    _assert_vscode_focus_fallback_keybindings "$vscode_keybindings_file" "Linux"
    _assert_vscode_terminal_native_settings \
      "$vscode_home/.config/Code/User/settings.json" "Linux"
    _assert_vscode_terminal_local_settings_preserved \
      "$vscode_home/.config/Code/User/settings.json" "Linux"
    vscode_extensions=$(jq -c . "$vscode_home/.vscode/extensions/extensions.json")
    _assert_contains "vscode sley: extension registered" \
      '"id":"cgraf.sley-tools"' "$vscode_extensions"
    _assert_contains "vscode termnav: extension registered" \
      '"id":"cgraf.termnav"' "$vscode_extensions"
    _assert_eq "vscode local extensions: registration uses the manifest version" \
      "0.3.0" \
      "$(jq -r '.[] | select(.identifier.id == "cgraf.termnav") | .version' "$vscode_home/.vscode/extensions/extensions.json")"
    _assert_eq "vscode termnav: enabled upgrade keeps one current registration" \
      '["termnav-0.3.0"]' \
      "$(jq -c '[.[] | select(.identifier.id == "cgraf.termnav") | .relativeLocation]' "$vscode_home/.vscode/extensions/extensions.json")"
    _assert_eq "vscode local extensions: only declared extensions are registered" \
      '["cgraf.sley-tools","cgraf.termnav"]' \
      "$(jq -c '[.[] | select(.metadata.source == "local") | .identifier.id]' "$vscode_home/.vscode/extensions/extensions.json")"
    _assert_contains "vscode sley: preserves existing extension registrations" \
      '"id":"keep.existing"' "$vscode_extensions"
    _assert_contains "vscode sley: refreshes stale local extension registration" \
      '"relativeLocation":"sley-tools-0.0.1"' "$vscode_extensions"
    _assert_not_contains "vscode sley: removes stale local extension location" \
      'stale-sley-tools-0.0.1' "$vscode_extensions"
    _assert_not_contains "vscode local extensions: retired registration is pruned" \
      '"id":"cgraf.retired-local"' "$vscode_extensions"
    if [[ ! -L "$vscode_home/.vscode/extensions/retired-local-0.0.1" ]]; then
      _pass "vscode local extensions: retired broken symlink is pruned"
    else
      _fail "vscode local extensions: retired broken symlink is pruned"
    fi
    if [[ -L "$vscode_home/.vscode/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode sley: extension symlink deployed"
    else
      _fail "vscode sley: extension symlink deployed"
    fi
    _assert_eq "vscode sley: existing same-version link migrates to provider" \
      "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode/sley-tools-0.0.1" \
      "$(readlink "$vscode_home/.vscode/extensions/sley-tools-0.0.1")"
    if [[ -L "$vscode_home/.vscode/extensions/termnav-0.3.0" ]]; then
      _pass "vscode termnav: extension symlink deployed"
    else
      _fail "vscode termnav: extension symlink deployed"
    fi
    _assert_file_missing "vscode termnav: enabled upgrade prunes older generation" \
      "$vscode_home/.vscode/extensions/termnav-0.2.0"
    _assert_eq "vscode remote settings: generated window title uses remote host label" \
      "$vscode_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.vscode-server/data/Machine/settings.json")"
    _assert_eq "vscode remote settings: mcp auth token matches local variant's per-machine state" \
      "$vscode_mcp_token_state" \
      "$(jq -r '.["vscode-mcp-server.authToken"] // empty' "$vscode_home/.vscode-server/data/Machine/settings.json")"

    # The Ctrl+Arrow editor bindings are macOS-specific: Karabiner exempts
    # VS Code so integrated terminals receive raw Ctrl+Arrow sequences, and
    # this keybinding layer restores editor word movement only for that platform.
    vscode_mac_keybindings="$vscode_home/Library/Application Support/Code/User/keybindings.json"
    rm -rf "$vscode_home/Library/Application Support/Code/User"
    _write_vscode_keybinding_conflicts "$vscode_mac_keybindings"
    _add_vscode_pre_focus_keybindings "$vscode_mac_keybindings" "macOS"
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Darwin\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      _vscode_variants() {
        printf "%s\t%s\n" "$HOME/.vscode/extensions" "$HOME/Library/Application Support/Code/User"
      }
      merge
    '
    _assert_vscode_keybinding_precedence "$vscode_mac_keybindings" "macOS"
    _assert_vscode_focus_keybinding_migration "$vscode_mac_keybindings" "macOS"
    _assert_vscode_macos_ctrl_arrow_keybindings "$vscode_mac_keybindings"
    _assert_vscode_macos_karabiner_terminal_keybindings "$vscode_mac_keybindings"
    _assert_vscode_terminal_clipboard_keybindings "$vscode_mac_keybindings" "macOS"
    _assert_vscode_focus_fallback_keybindings "$vscode_mac_keybindings" "macOS"
    _assert_vscode_terminal_native_settings \
      "$vscode_home/Library/Application Support/Code/User/settings.json" "macOS"

    rm -rf "$vscode_home/.config/Code/User"

    # Remote VS Code server profiles have an extensions dir but no local
    # settings/keybindings dir. Work overlays describe those as extension-only
    # variants so local dot extensions are visible to remote extension hosts
    # without inventing unrelated config files.
    remote_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_MV_LOG="$vscode_mv_log" DOT_TEST_VSCODE_HOSTNAME="remote-only-host" bash -c '
      set -euo pipefail
      . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
      dot_hook_platform_match() { return 1; }
      uname() { printf "Linux\n"; }
      _log() { :; }
      _warn() { printf "%s\n" "$*" >&2; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
      merge
    ' || remote_rc=$?
    _assert_eq "vscode sley: extension-only merge exits cleanly" "0" "$remote_rc"
    vscode_remote_only_title_expected="remote-only-host\${separator}\${activeRepositoryBranchName}\${separator}\${rootNameShort}\${separator}\${activeEditorShort}"
    _assert_eq "vscode remote settings: server-only host gets generated window title" \
      "$vscode_remote_only_title_expected" \
      "$(jq -r '.["window.title"]' "$vscode_home/.vscode-server/data/Machine/settings.json")"
    vscode_remote_extensions=$(jq -c . "$vscode_home/.vscode-server/extensions/extensions.json")
    _assert_contains "vscode sley: extension-only variant registered" \
      '"id":"cgraf.sley-tools"' "$vscode_remote_extensions"
    _assert_contains "vscode termnav: extension-only variant registered" \
      '"id":"cgraf.termnav"' "$vscode_remote_extensions"
    if [[ -L "$vscode_home/.vscode-server/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode sley: extension-only symlink deployed"
    else
      _fail "vscode sley: extension-only symlink deployed"
    fi
    if [[ -L "$vscode_home/.vscode-server/extensions/termnav-0.3.0" ]]; then
      _pass "vscode termnav: extension-only symlink deployed"
    else
      _fail "vscode termnav: extension-only symlink deployed"
    fi

    vscode_nosley_extensions=$(jq -c . "$vscode_home/.vscode-nosley/extensions/extensions.json")
    _assert_not_contains "vscode sley: no-sley variant unregisters formatter extension" \
      '"id":"cgraf.sley-tools"' "$vscode_nosley_extensions"
    _assert_eq "vscode sley: no-sley variant keeps independent local extensions" \
      '["cgraf.termnav"]' \
      "$(jq -c '[.[] | select(.metadata.source == "local") | .identifier.id]' "$vscode_home/.vscode-nosley/extensions/extensions.json")"
    if [[ ! -e "$vscode_home/.vscode-nosley/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode sley: no-sley variant removes formatter symlink"
    else
      _fail "vscode sley: no-sley variant removes formatter symlink"
    fi
    if [[ -L "$vscode_home/.vscode-nosley/extensions/termnav-0.3.0" ]]; then
      _pass "vscode termnav: no-sley variant keeps tab router"
    else
      _fail "vscode termnav: no-sley variant keeps tab router"
    fi
    vscode_no_termnav_extensions=$(jq -c . \
      "$vscode_home/.vscode-no-termnav/extensions/extensions.json")
    _assert_not_contains "vscode termnav: no-termnav variant unregisters adapter" \
      '"id":"cgraf.termnav"' "$vscode_no_termnav_extensions"
    _assert_contains "vscode termnav: no-termnav keeps independent local extensions" \
      '"id":"cgraf.sley-tools"' "$vscode_no_termnav_extensions"
    _assert_file_missing "vscode termnav: no-termnav removes current adapter symlink" \
      "$vscode_home/.vscode-no-termnav/extensions/termnav-0.3.0"
    _assert_file_missing "vscode termnav: no-termnav removes older adapter symlinks" \
      "$vscode_home/.vscode-no-termnav/extensions/termnav-0.2.0"
    _assert_eq "vscode keybindings: every PR 90 review-build fallback is retired exactly" \
      "0" \
      "$(jq '[.[] | select(
        [.key, .command, (.when // "")] as $route
        | [
            ["ctrl+.", "editor.action.quickFix", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+/", "editor.action.commentLine", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+\\", "workbench.action.splitEditor", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+e", "workbench.view.explorer", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+f", "workbench.view.search", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+m", "workbench.actions.view.problems", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+p", "workbench.action.showCommands", "terminalFocus && !termnav.nvimFocused"],
            ["shift+cmd+f", "workbench.view.search", "terminalFocus && !termnav.nvimFocused"],
            ["shift+cmd+p", "workbench.action.showCommands", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+v", "workbench.action.terminal.paste", "terminalFocus && !termnav.nvimFocused"],
            ["ctrl+shift+v", "editor.action.clipboardPasteAction", "textInputFocus && !editorReadonly && !terminalFocus"],
            ["cmd+/", "editor.action.commentLine", "terminalFocus && !termnav.nvimFocused"]
          ]
          | any(.[]; . == $route)
      )] | length' "$vscode_home/.config/NoTermnav/User/keybindings.json")"
    _assert_vscode_focus_fallback_keybindings \
      "$vscode_home/.config/NoTermnav/User/keybindings.json" "Linux"
    _assert_vscode_terminal_native_settings \
      "$vscode_home/.config/NoTermnav/User/settings.json" "Linux no-Termnav"
    _assert_vscode_native_tab_handling \
      "$vscode_home/.config/NoTermnav/User/keybindings.json" "Linux"

    for vscode_no_termnav_platform in macos windows; do
      vscode_no_termnav_config="$vscode_home/.config/NoTermnav-$vscode_no_termnav_platform/User"
      _write_vscode_keybinding_conflicts \
        "$vscode_no_termnav_config/keybindings.json"
      # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
      env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
        DOT_TEST_MV_LOG="$vscode_mv_log" \
        DOT_TEST_VSCODE_CONFIG="$vscode_no_termnav_config" \
        DOT_TEST_VSCODE_PLATFORM="$vscode_no_termnav_platform" bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { return 1; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        _vscode_keybinding_platform() {
          printf "%s\n" "$DOT_TEST_VSCODE_PLATFORM"
        }
        _merge_vscode_config "$DOT_TEST_VSCODE_CONFIG" no-termnav
      '
      case "$vscode_no_termnav_platform" in
        macos) vscode_no_termnav_label="macOS" ;;
        windows) vscode_no_termnav_label="Windows" ;;
      esac
      _assert_vscode_focus_fallback_keybindings \
        "$vscode_no_termnav_config/keybindings.json" \
        "$vscode_no_termnav_label"
      _assert_vscode_terminal_native_settings \
        "$vscode_no_termnav_config/settings.json" \
        "$vscode_no_termnav_label no-Termnav"
      _assert_vscode_native_tab_handling \
        "$vscode_no_termnav_config/keybindings.json" \
        "$vscode_no_termnav_label"
    done

    vscode_nosley_settings=$(jq -c . "$vscode_home/.config/NoSley/User/settings.json")
    _assert_not_contains "vscode sley: no-sley variant removes formatter settings" \
      'cgraf.sley-tools' "$vscode_nosley_settings"
    _assert_not_contains "vscode sley: no-sley variant removes generated format-on-save" \
      '"[cpp]"' "$vscode_nosley_settings"
    _assert_contains "vscode sley: no-sley variant preserves unrelated language settings" \
      '"editor.tabSize":4' "$vscode_nosley_settings"
    _assert_contains "vscode schemas: no-sley keeps Checkrun schema policy" \
      '"json.schemas":[{"fileMatch":[".sley/verify.json","**/.sley/verify.json"],"name":"Sley verify registry","url":"file:///mock/sley/verify.schema.json"}]' "$vscode_nosley_settings"

    win_profile="$vscode_home/win/Users/Chris"
    win_appdata="$win_profile/AppData/Roaming"
    win_code_user="$win_appdata/Code/User"
    win_ext_dir="$win_profile/.vscode/extensions"
    mkdir -p "$win_code_user" "$win_ext_dir/keep-existing-extension-1.0.0"
    cat >"$win_code_user/settings.json" <<'JSON'
{
  "editor.tabSize": 4,
  "terminal.integrated.commandsToSkipShell": [
    "workbench.action.quickOpen",
    "workbench.action.togglePanel",
    "-local.terminalCommand"
  ]
}
JSON
    # Windows shares the Ctrl baseline but must never claim macOS Cmd-shaped
    # locals. Seed the complete macOS historical shape here so WSL exercises
    # the persisted "windows" platform key, not just Linux/macOS branches.
    _write_vscode_keybinding_conflicts "$win_code_user/keybindings.json"
    _add_vscode_pre_focus_keybindings \
      "$win_code_user/keybindings.json" \
      "windows"
    win_extensions_before='[{"identifier":{"id":"keep.existing"},"relativeLocation":"keep-existing-extension-1.0.0","metadata":{"ownedBy":"windows"}}]'
    printf '%s\n' "$win_extensions_before" >"$win_ext_dir/extensions.json"
    rm -f \
      "$vscode_home/.vscode-server/extensions/extensions.json" \
      "$vscode_home/.vscode-server/extensions/sley-tools-0.0.1"

    wsl_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_WINDOWS_APPDATA="$win_appdata" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_WSL_PAIRED_ACCOUNT=1 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        merge
      ' || wsl_rc=$?
    _assert_eq "vscode wsl: merge exits cleanly" "0" "$wsl_rc"

    win_extensions=$(jq -c . "$win_ext_dir/extensions.json")
    _assert_contains "vscode wsl: Windows native extension registration is preserved" \
      '"id":"keep.existing"' "$win_extensions"
    _assert_file_content "vscode wsl: Windows native extension registry is untouched" \
      "$win_extensions_before" "$win_ext_dir/extensions.json"
    _assert_not_contains "vscode wsl: Windows native does not register sley extension" \
      '"id":"cgraf.sley-tools"' "$win_extensions"
    _assert_not_contains "vscode wsl: Windows native does not register termnav extension" \
      '"id":"cgraf.termnav"' "$win_extensions"
    _assert_file_missing "vscode wsl: Windows native sley extension not copied" \
      "$win_ext_dir/sley-tools-0.0.1"

    wsl_extensions=$(jq -c . "$vscode_home/.vscode-server/extensions/extensions.json")
    _assert_contains "vscode wsl: server registers sley extension" \
      '"id":"cgraf.sley-tools"' "$wsl_extensions"
    _assert_contains "vscode wsl: server registers termnav extension" \
      '"id":"cgraf.termnav"' "$wsl_extensions"
    _assert_eq "vscode wsl: server only registers declared local extensions" \
      '["cgraf.sley-tools","cgraf.termnav"]' \
      "$(jq -c '[.[] | select(.metadata.source == "local") | .identifier.id]' "$vscode_home/.vscode-server/extensions/extensions.json")"
    if [[ -L "$vscode_home/.vscode-server/extensions/sley-tools-0.0.1" ]]; then
      _pass "vscode wsl: server sley symlink deployed"
    else
      _fail "vscode wsl: server sley symlink deployed"
    fi
    if [[ -L "$vscode_home/.vscode-server/extensions/termnav-0.3.0" ]]; then
      _pass "vscode wsl: server termnav symlink deployed"
    else
      _fail "vscode wsl: server termnav symlink deployed"
    fi

    win_settings=$(jq -c . "$win_code_user/settings.json")
    _assert_contains "vscode wsl: Windows settings use local formatter" \
      '"editor.defaultFormatter":"cgraf.sley-tools"' "$win_settings"
    vscode_mv_ops=$(cat "$vscode_mv_log")
    _assert_not_contains "vscode wsl: Windows settings replacement avoids forced mv" \
      "$win_code_user/settings.json" "$vscode_mv_ops"
    _assert_not_contains "vscode wsl: Windows keybindings replacement avoids forced mv" \
      "$win_code_user/keybindings.json" "$vscode_mv_ops"
    _assert_vscode_terminal_clipboard_keybindings \
      "$win_code_user/keybindings.json" "Windows"
    _assert_vscode_focus_fallback_keybindings \
      "$win_code_user/keybindings.json" "Windows"
    _assert_vscode_terminal_native_settings \
      "$win_code_user/settings.json" "Windows"
    _assert_vscode_terminal_local_settings_preserved \
      "$win_code_user/settings.json" "Windows"
    _assert_vscode_focus_keybinding_migration \
      "$win_code_user/keybindings.json" "Windows"
    _assert_vscode_keybinding_precedence \
      "$win_code_user/keybindings.json" "Windows"

    # Regression: on a machine where a second Linux account (e.g. root) also
    # runs `dot update`, both accounts previously resolved the same native
    # Windows profile and raced unlocked writes on the same settings.json,
    # which is how it got corrupted. An unpaired account must leave the
    # native Windows config untouched entirely.
    win_settings_before_unpaired=$(cat "$win_code_user/settings.json")
    win_keybindings_before_unpaired=$(cat "$win_code_user/keybindings.json")
    win_extensions_before_unpaired=$(cat "$win_ext_dir/extensions.json")

    wsl_unpaired_rc=0
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_home" REAL_HOME="$REAL_HOME" PATH="$vscode_bin:$PATH" \
      DOT_TEST_WINDOWS_APPDATA="$win_appdata" DOT_TEST_MV_LOG="$vscode_mv_log" \
      DOT_TEST_WSL_PAIRED_ACCOUNT=0 bash -c '
        set -euo pipefail
        . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh"
        dot_hook_platform_match() { [[ $1 == wsl ]]; }
        uname() { printf "Linux\n"; }
        _log() { :; }
        _warn() { printf "%s\n" "$*" >&2; }
        # shellcheck source=/dev/null
        . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
        merge
      ' || wsl_unpaired_rc=$?
    _assert_eq "vscode wsl unpaired: merge exits cleanly" "0" "$wsl_unpaired_rc"

    _assert_file_content "vscode wsl unpaired: native settings.json untouched" \
      "$win_settings_before_unpaired" "$win_code_user/settings.json"
    _assert_file_content "vscode wsl unpaired: native keybindings.json untouched" \
      "$win_keybindings_before_unpaired" "$win_code_user/keybindings.json"
    _assert_file_content "vscode wsl unpaired: native extensions.json untouched" \
      "$win_extensions_before_unpaired" "$win_ext_dir/extensions.json"
  else
    echo "  SKIP: VS Code Sley merge hook assertions (jq unavailable)"
  fi
  _test_summary
}
