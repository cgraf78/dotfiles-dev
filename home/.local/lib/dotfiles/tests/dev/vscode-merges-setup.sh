# shellcheck shell=bash
# Shared VS Code merge-hook fixture for the dev-vscode suites: an isolated HOME
# with Sley and Termnav payloads, tracked merge inputs, checkrun/shdeps/mv
# shims, and the full single-variant Linux merge run against it.

# Seed keybinding files with the user-owned, legacy, and stale entries the
# merge must preserve, migrate, or retire. The fixture and several suite cases
# use these, so they live beside the fixture rather than inside one suite.
_add_vscode_stale_terminal_native_keybindings() {
  local keybindings_file="$1"
  local migrated

  migrated=$(_tmpfile)
  jq '. + [
        {
          "key": "ctrl+b",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u0002"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+h",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u0008"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+j",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000a"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+j",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000a"},
          "when": "terminalFocus"
        },
        {
          "key": "ctrl+k",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000b"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+l",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u000c"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+tab",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001b[9;5u"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+shift+tab",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001b[9;6u"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+/",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001f"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "cmd+/",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u001f"},
          "when": "terminalFocus && termnav.nvimFocused"
        },
        {
          "key": "ctrl+`",
          "command": "workbench.action.terminal.sendSequence",
          "args": {"text": "\u0000"},
          "when": "terminalFocus && termnav.nvimFocused"
        }
      ]' "$keybindings_file" >"$migrated"
  mv "$migrated" "$keybindings_file"
}

_write_vscode_keybinding_conflicts() {
  local keybindings_file="$1"

  mkdir -p "$(dirname "$keybindings_file")"
  cat >"$keybindings_file" <<'JSON'
[
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;5u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;6u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+v",
    "command": "local.terminalPasteOverride",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u001b[local-action"},
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u0010"},
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "cmd+p",
    "command": "workbench.action.quickOpen",
    "when": "terminalFocus && localTerminalMode"
  }
]
JSON
  # Exercise upgrades from the #80/#90 focus-gated terminal controls, the
  # #98 tab generation, and the normalized #100 Ctrl+J route, including
  # machines that skipped releases.
  _add_vscode_stale_terminal_native_keybindings "$keybindings_file"
}

_add_vscode_pre_focus_keybindings() {
  local keybindings_file="$1"
  local platform="$2"
  local migrated

  migrated=$(_tmpfile)
  jq --arg platform "$platform" '
        . + [
          {
            "key": "ctrl+p",
            "command": "workbench.action.quickOpen",
            "when": "terminalFocus"
          },
          {
            "key": "ctrl+v",
            "command": "workbench.action.terminal.paste",
            "when": "terminalFocus"
          }
        ] + (
          if $platform == "macOS" then
            [
              {
                "key": "cmd+a",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0001"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+b",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0002"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+l",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u000c"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+n",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u000e"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+p",
                "command": "workbench.action.quickOpen",
                "when": "terminalFocus"
              },
              {
                "key": "cmd+r",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0012"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+u",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0015"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+v",
                "command": "workbench.action.terminal.paste",
                "when": "terminalFocus"
              },
              {
                "key": "cmd+w",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u0017"},
                "when": "terminalFocus"
              },
              {
                "key": "cmd+z",
                "command": "workbench.action.terminal.sendSequence",
                "args": {"text": "\u001a"},
                "when": "terminalFocus"
              }
            ]
          else
            []
          end
        )
      ' "$keybindings_file" >"$migrated"
  mv "$migrated" "$keybindings_file"
}

# Build the fixture in the caller's scope. Assignments are intentionally
# global: vscode_home, vscode_bin, vscode_mv_log, and the paths below are read
# by the suite bodies after this returns.
_dev_vscode_merges_fixture() {
  vscode_home=$(_tmpdir)
  vscode_bin=$(_tmpdir)/bin
  # Use the actual Sley-owned payload in this consumer integration fixture.
  # A repository-local copy would make local-extension reconciliation pass
  # even if dotfiles and the provider published incompatible contracts.
  vscode_sley_root="${DOT_TEST_SLEY_ROOT:-${DOT_TEST_HOST_HOME:-$REAL_HOME}/.local/share/cgraf78/sley}"
  vscode_sley_source="$vscode_sley_root/share/sley/vscode/sley-tools-0.0.1"
  export DOT_VSCODE_EXTENSIONS_SKIP=1
  mkdir -p \
    "$vscode_bin" \
    "$vscode_home/.config/Code/User" \
    "$vscode_home/.config/dot/merge-hooks.d" \
    "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode" \
    "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.3.0" \
    "$vscode_home/.local/share/dot-vscode-extensions" \
    "$vscode_home/.vscode/extensions"
  cat >"$vscode_home/.config/Code/User/settings.json" <<'JSON'
{
  "[python]": {
    "editor.defaultFormatter": "cgraf.sley-tools",
    "editor.formatOnSave": true,
    "editor.tabSize": 4
  },
  "evenBetterToml.schema.associations": {
    "^/Users/chris/stale\\.toml$": "file:///Users/chris/stale.schema.json",
    "^/root/stale\\.toml$": "file:///root/stale.schema.json"
  },
  "json.schemas": [
    {
      "fileMatch": ["/Users/chris/stale.json"],
      "name": "stale-json",
      "url": "file:///Users/chris/stale.schema.json"
    }
  ],
  "terminal.integrated.commandsToSkipShell": [
    "workbench.action.quickOpen",
    "workbench.action.togglePanel",
    "-local.terminalCommand"
  ],
  "yaml.schemas": {
    "file:///Users/chris/stale.schema.json": ["/Users/chris/stale.yml"]
  }
}
JSON
  _write_vscode_keybinding_conflicts "$vscode_home/.config/Code/User/keybindings.json"
  _add_vscode_pre_focus_keybindings \
    "$vscode_home/.config/Code/User/keybindings.json" \
    "linux"
  cp -R "$REAL_HOME/.config/dot/merge-hooks.d/vscode" \
    "$vscode_home/.config/dot/merge-hooks.d/vscode"
  cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/25-order-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+5",
    "command": "fixture.orderCommonEarlier",
    "when": "fixture.orderCommonEarlier"
  }
]
JSON
  cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/all.d/30-history-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+8",
    "command": "fixture.managedOld",
    "args": {"version": 1},
    "when": "fixture.managedOld"
  },
  {
    "key": "ctrl+alt+9",
    "command": "fixture.managedDeleted",
    "when": "fixture.managedDeleted"
  },
  {
    "key": "ctrl+p",
    "command": "workbench.action.terminal.sendSequence",
    "args": {"text": "\u0010"},
    "when": "terminalFocus && fixtureParallelSource"
  },
  {
    "key": "ctrl+alt+6",
    "command": "fixture.orderCommonLater",
    "when": "fixture.orderCommonLater"
  }
]
JSON
  cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/keybindings/linux.d/20-order-probe.jsonc" <<'JSON'
[
  {
    "key": "ctrl+alt+7",
    "command": "fixture.orderPlatform",
    "when": "fixture.orderPlatform"
  }
]
JSON
  cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/settings.d/50-prefix-probe.json" <<'JSON'
{
  "dotfiles.prefixProbe": true
}
JSON
  cp -R "$vscode_sley_source" \
    "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode/sley-tools-0.0.1"
  # Model an in-place fleet upgrade from the old dotfiles-owned payload.
  # The provider keeps the same extension basename, so basename-only pruning
  # cannot distinguish this stale live link from the desired Sley-owned one.
  cp -R "$vscode_sley_source" \
    "$vscode_home/.local/share/dot-vscode-extensions/sley-tools-0.0.1"
  ln -s "$vscode_home/.local/share/dot-vscode-extensions/sley-tools-0.0.1" \
    "$vscode_home/.vscode/extensions/sley-tools-0.0.1"
  cat >"$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.3.0/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.3.0"
}
JSON
  vscode_mv_log="$vscode_home/mv.log"
  cat >"$vscode_home/.vscode/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {
      "id": "keep.existing"
    },
    "relativeLocation": "keep-existing-extension-1.0.0"
  },
  {
    "identifier": {
      "id": "cgraf.sley-tools"
    },
    "relativeLocation": "stale-sley-tools-0.0.1"
  },
  {
    "identifier": {
      "id": "cgraf.termnav"
    },
    "relativeLocation": "termnav-0.2.0",
    "metadata": {
      "source": "local"
    }
  },
  {
    "identifier": {
      "id": "cgraf.retired-local"
    },
    "relativeLocation": "retired-local-0.0.1",
    "metadata": {
      "source": "local"
    }
  }
]
JSON
  ln -s "$vscode_home/.local/share/dot-vscode-extensions/retired-local-0.0.1" \
    "$vscode_home/.vscode/extensions/retired-local-0.0.1"
  mkdir -p "$vscode_home/.vscode-server/extensions"
  mkdir -p \
    "$vscode_home/.vscode-nosley/extensions" \
    "$vscode_home/.vscode-no-termnav/extensions" \
    "$vscode_home/.config/NoSley/User" \
    "$vscode_home/.config/NoTermnav/User" \
    "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0"
  ln -s "$vscode_home/.local/share/cgraf78/sley/share/sley/vscode/sley-tools-0.0.1" \
    "$vscode_home/.vscode-nosley/extensions/sley-tools-0.0.1"
  cat >"$vscode_home/.vscode-nosley/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {
      "id": "cgraf.sley-tools"
    },
    "relativeLocation": "sley-tools-0.0.1"
  }
]
JSON
  cat >"$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0/package.json" <<'JSON'
{
  "name": "termnav",
  "publisher": "cgraf",
  "version": "0.2.0"
}
JSON
  ln -s \
    "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0" \
    "$vscode_home/.vscode/extensions/termnav-0.2.0"
  ln -s \
    "$vscode_home/.local/share/cgraf78/termnav/share/termnav/vscode/termnav-0.2.0" \
    "$vscode_home/.vscode-no-termnav/extensions/termnav-0.2.0"
  cat >"$vscode_home/.vscode-no-termnav/extensions/extensions.json" <<'JSON'
[
  {
    "identifier": {
      "id": "cgraf.termnav"
    },
    "relativeLocation": "termnav-0.2.0",
    "metadata": {
      "source": "local"
    }
  }
]
JSON
  cat >"$vscode_home/.config/NoTermnav/User/keybindings.json" <<'JSON'
[
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && terminalHasBeenCreated && !terminalEditorFocus || terminalFocus && terminalProcessSupported && !terminalEditorFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.focusNext",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.focusPrevious",
    "when": "terminalFocus && localTerminalMode"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenLeastRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup",
    "when": "!activeEditorGroupEmpty"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+tab",
    "command": "-workbench.action.quickOpenNavigateNextInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen && !terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "-workbench.action.quickOpenNavigatePreviousInEditorPicker",
    "when": "inEditorsPicker && inQuickOpen"
  },
  {
    "key": "ctrl+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;5u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+shift+tab",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[9;6u" },
    "when": "terminalFocus"
  },
  {
    "key": "ctrl+/",
    "command": "editor.action.commentLine",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+.",
    "command": "editor.action.quickFix",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+\\",
    "command": "workbench.action.splitEditor",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+e",
    "command": "workbench.view.explorer",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+f",
    "command": "workbench.view.search",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+m",
    "command": "workbench.actions.view.problems",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+p",
    "command": "workbench.action.showCommands",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "shift+cmd+f",
    "command": "workbench.view.search",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "shift+cmd+p",
    "command": "workbench.action.showCommands",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+v",
    "command": "workbench.action.terminal.paste",
    "when": "terminalFocus && !termnav.nvimFocused"
  },
  {
    "key": "ctrl+shift+v",
    "command": "editor.action.clipboardPasteAction",
    "when": "textInputFocus && !editorReadonly && !terminalFocus"
  },
  {
    "key": "cmd+/",
    "command": "editor.action.commentLine",
    "when": "terminalFocus && !termnav.nvimFocused"
  }
]
JSON
  _add_vscode_stale_terminal_native_keybindings \
    "$vscode_home/.config/NoTermnav/User/keybindings.json"
  cat >"$vscode_home/.config/NoSley/User/settings.json" <<'JSON'
{
  "[cpp]": {
    "editor.defaultFormatter": "cgraf.sley-tools",
    "editor.formatOnSave": true
  },
  "[python]": {
    "editor.defaultFormatter": "cgraf.sley-tools",
    "editor.formatOnSave": true,
    "editor.tabSize": 4
  }
}
JSON
  mkdir -p "$vscode_home/.config/dot/merge-hooks.d/vscode/variants.d"
  cat >"$vscode_home/.config/dot/merge-hooks.d/vscode/variants.d/80-extra.tsv" <<'EOF'
# platform	marker	extensions_dir	config_dir	options
Linux	$HOME/.vscode-server/extensions	$HOME/.vscode-server/extensions	-
Linux	$HOME/.vscode-nosley/extensions	$HOME/.vscode-nosley/extensions	$HOME/.config/NoSley/User	no-sley
Linux	$HOME/.vscode-no-termnav/extensions	$HOME/.vscode-no-termnav/extensions	$HOME/.config/NoTermnav/User	no-termnav
EOF
  cat >"$vscode_bin/checkrun" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "capabilities --json" ]]; then
  cat <<'JSON'
{
  "editorLanguageIds": {
    "vscode": {
      "bzl": ["starlark", "bzl"],
      "ini": ["ini"],
      "make": ["makefile"],
      "sh": ["shellscript"],
      "sshconfig": ["ssh_config"],
      "starlark": ["starlark", "bzl"],
      "text": ["plaintext"],
      "zsh": ["shellscript"]
    }
  },
  "filetypes": {
    "custom": {
      "extension": {
        "hgrc": "ini",
        "ini": "ini",
        "mak": "make",
        "pathlist": "text",
        "service": "systemd",
        "ssh-config": "sshconfig",
        "ssh_config": "sshconfig",
        "tsv": "text",
        "txt": "text"
      },
      "filename": {
        ".editorconfig": "editorconfig",
        ".gitconfig": "gitconfig",
        "BUILD": "bzl",
        "tmux.conf": "tmux"
      },
      "patterns": [
        {
          "filetype": "bzl",
          "pattern": "WORKSPACE.*"
        },
        {
          "filetype": "text",
          "pattern": "*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.conf"
        },
        {
          "filetype": "text",
          "pattern": "*/.config/dot/merge-hooks.d/agent-rules/targets.d/*.replace/*.conf"
        }
      ]
    },
    "format": ["python", "sh", "starlark", "zsh"],
    "lint": ["python", "sh", "starlark", "zsh", "make", "editorconfig", "gitconfig", "systemd", "tmux"]
  },
  "version": 2
}
JSON
  exit 0
fi
  exit 2
EOF
  cat >"$vscode_home/checkrun-schema-policy.py" <<'EOF'
#!/usr/bin/env python3
import json
import sys

if sys.argv[1:] != ["--lsp-schemas", "--editor-sources"]:
    raise SystemExit(2)

json.dump(
    {
        "json": [
            {
                "name": "Sley verify registry",
                "url": "file:///mock/sley/verify.schema.json",
                "fileMatch": [
                    ".sley/verify.json",
                    "/Users/chris/.sley/verify.json",
                    "/Users/cgraf/.sley/verify.json",
                    "/home/cgraf/.sley/verify.json",
                    "**/.sley/verify.json"
                ],
            }
        ],
        "yaml": {
            "https://example.invalid/docker-compose.schema.json": [
                "docker-compose.yml",
                "/Users/chris/docker-compose.yml",
                "/Users/cgraf/docker-compose.yml",
                "/home/cgraf/docker-compose.yml",
                "**/docker-compose.yml",
            ]
        },
        "toml": {
            ".*/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
            "^/Users/chris/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
            "^/Users/cgraf/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
            "^/home/cgraf/pyproject\\.toml$": "https://example.invalid/pyproject.schema.json",
        },
    },
    sys.stdout,
    separators=(",", ":"),
)
EOF
  cat >"$vscode_bin/shdeps" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "dep-file cgraf78/checkrun lib/checkrun/schemas/schema_policy.py" ]]; then
  printf '%s\n' "$HOME/checkrun-schema-policy.py"
  exit 0
fi
exit 2
EOF
  real_mv=$(command -v mv)
  cat >"$vscode_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "-f" ]]; then
  printf 'mv would prompt without -f: %s\n' "\$*" >&2
  exit 64
fi
shift
if [[ "\${1:-}" == "--" ]]; then
  shift
fi
printf '%s\n' "\$*" >>"\${DOT_TEST_MV_LOG:?}"
if [[ -n "\${DOT_TEST_MV_FAIL_SUFFIX:-}" && "\${!#}" == *"\$DOT_TEST_MV_FAIL_SUFFIX" ]]; then
  exit 75
fi
if [[ -n "\${DOT_TEST_MV_FAIL_ONCE_MARKER:-}" && ! -e "\$DOT_TEST_MV_FAIL_ONCE_MARKER" ]]; then
  : >"\$DOT_TEST_MV_FAIL_ONCE_MARKER"
  exit 75
fi
exec "$real_mv" -f -- "\$@"
EOF
  chmod +x "$vscode_bin/checkrun" "$vscode_bin/shdeps" "$vscode_bin/mv" "$vscode_home/checkrun-schema-policy.py"
}

# Run the full Linux merge of the fixture's single Code variant.
_dev_vscode_fixture_merge() {
  # shellcheck disable=SC2016 # The inner shell expands REAL_HOME from env.
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
    '
}

# Name the fixture merge's settings ownership receipt and the window title it
# generates for the fixture host label.
# shellcheck disable=SC2034 # Read by the suites after this returns.
_dev_vscode_fixture_expectations() {
  vscode_receipt_root=$vscode_home/.local/state/dot/overlays/dev/merge-receipts-v1
  vscode_settings_path=$vscode_home/.config/Code/User/settings.json
  vscode_settings_key=$(printf '%s\n%s\n' vscode-settings \
    "$vscode_settings_path" | git hash-object --stdin)
  vscode_title_expected="fixture-host\${separator}\${activeRepositoryBranchName}\${separator}\${rootNameShort}\${separator}\${activeEditorShort}"
}
