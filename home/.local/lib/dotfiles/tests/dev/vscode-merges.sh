# shellcheck shell=bash
# VS Code merge-hook behavior, split from merges.sh because it is the longest
# block: as a separate suite `dot test` runs it in parallel with the rest.
# The unchanged-update signature lifecycle lives in vscode-signature-merges.sh.

# The shared fixture in vscode-merges-setup.sh assigns vscode_home,
# vscode_bin, vscode_mv_log, and the receipt and title expectations; a
# standalone check cannot see those writes.
# shellcheck disable=SC2154

# shellcheck source=merges-setup.sh
. "${BASH_SOURCE[0]%/*}/merges-setup.sh"
# shellcheck source-path=SCRIPTDIR source=vscode-merges-setup.sh
. "${BASH_SOURCE[0]%/*}/vscode-merges-setup.sh"

dot_dev_vscode_merges_test() {
  _dev_merges_setup || return
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
      _dot_tool_present() { return 0; }
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/vscode.sh"
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
      # The hook compatibility layer installs the real host capability
      # predicate. This fixture deliberately has no editor marker because it
      # exercises variant failure aggregation, so select the hook explicitly
      # rather than depending on an ambient VS Code binary from the CI host.
      _dot_tool_present() { [[ $1 == vscode ]]; }
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

    vscode_server_only_home=$(_tmpdir)
    mkdir -p "$vscode_server_only_home/.vscode-server"
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

    vscode_missing_termnav_home=$(_tmpdir)
    mkdir -p \
      "$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/local-extensions.d" \
      "$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/variants.d" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions" \
      "$vscode_missing_termnav_home/dev/termnav-9.9.9" \
      "$vscode_missing_termnav_home/managed/termnav-0.2.0" \
      "$vscode_missing_termnav_home/managed/termnav-tools-0.1.0" \
      "$vscode_missing_termnav_home/managed/termnav-2-tools-0.1.0"
    cat >"$vscode_missing_termnav_home/managed/termnav-0.2.0/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.2.0"
}
JSON
    cat >"$vscode_missing_termnav_home/managed/termnav-2-tools-0.1.0/package.json" <<'JSON'
{
  "name": "termnav-2-tools",
  "publisher": "cgraf",
  "version": "0.1.0"
}
JSON
    cat >"$vscode_missing_termnav_home/managed/termnav-tools-0.1.0/package.json" <<'JSON'
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
    ln -s "$vscode_missing_termnav_home/managed/termnav-0.2.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.2.0"
    ln -s "$vscode_missing_termnav_home/managed/termnav-0.1.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.1.0"
    ln -s "$vscode_missing_termnav_home/dev/termnav-9.9.9" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-9.9.9"
    ln -s "$vscode_missing_termnav_home/managed/termnav-tools-0.1.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-tools-0.1.0"
    ln -s "$vscode_missing_termnav_home/managed/termnav-2-tools-0.1.0" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-2-tools-0.1.0"
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
# extension_id	source_dir	disabled_by_variant_options
cgraf.termnav	$HOME/managed/termnav-0.3.0	no-termnav
EOF
    cat >"$vscode_missing_termnav_home/.config/dot/merge-hooks.d/vscode/variants.d/10-variants.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Linux	$HOME/.vscode-no-termnav/extensions	$HOME/.vscode-no-termnav/extensions	-	no-termnav
EOF
    # shellcheck disable=SC2016 # The inner shell expands fixture env variables.
    env HOME="$vscode_missing_termnav_home" REAL_HOME="$REAL_HOME" \
      PATH="$vscode_bin:$PATH" DOT_TEST_MV_LOG="$vscode_mv_log" bash -c '
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
      _dot_tool_present() { [[ $1 == vscode ]]; }
      merge
    '
    _assert_eq \
      "vscode termnav: opt-out unregisters adapter when source is unavailable" \
      '[]' \
      "$(jq -c '[.[].identifier.id]' \
        "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/extensions.json")"
    _assert_file_missing \
      "vscode termnav: opt-out removes older adapter when source is unavailable" \
      "$vscode_missing_termnav_home/.vscode-no-termnav/extensions/termnav-0.2.0"
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
    echo "  SKIP: VS Code Sley merge hook assertions (jq unavailable)"
  fi
  _test_summary
}
