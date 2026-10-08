# VS Code Merge Hook Instance

This directory declares the `vscode` merge-hook instance. VS Code declarative
source families and private helpers live in this directory.

- `settings.d/` layers VS Code `settings.json` fragments.
- `keybindings/` layers shared and platform-specific `keybindings.jsonc`
  fragments.
- `extensions.d/` declares marketplace extension bundles and install profiles.
  Dot selects the ordered overlay stream, including `.replace` winners, and
  passes those files explicitly to the shdeps-provided `vscode-exts` command.
  The provider owns the manifest model, validation, platform discovery,
  locking, and additive installation. The default managed-extension manifest
  stays in a `.replace` group so an overlay can replace the whole personal
  extension policy with an empty manifest.
  The thin adapter translates Dot's established `DOT_WINDOWS_HOME` and timeout
  controls to provider-native names; explicitly set `VSCODE_EXTS_*` values take
  precedence.
- `variants.d/` declares VS Code, VS Code Insiders, Cursor, and remote variant
  targets.
- `local-extensions.d/` declares provider-owned local extensions that should
  be symlinked into active variants. Each TSV row names the extension ID, the
  shdeps dependency that publishes it, and comma-separated variant options that
  disable it. The hook asks `shdeps dep-path` for the dependency's
  `share/<repo>/vscode/` directory, so shdeps keeps owning install roots,
  development-clone precedence, and host filters, then selects the one folder
  whose `package.json` `publisher.name` matches the ID. Folder names are the
  provider's packaging choice (usually the manifest version, which moves
  independently of the provider's release version) and are never configured
  here. A dependency that is inactive, uninstalled, or unknown on the host
  silently skips the extension (shdeps reports those alike); a name shdeps
  rejects, or an installed provider with no matching folder or several,
  warns and skips it.
  Sley owns the extension implementation and its detailed behavioral suite;
  this merge hook owns only activation, the `no-sley` opt-out, and a
  compatibility smoke test. Keeping that boundary explicit prevents editor
  behavior from drifting into a second consumer-owned copy while preserving
  local deployment policy. The Termnav adapter uses `no-termnav`; opting out
  unregisters it and prunes identifiable older dot-managed symlinked
  generations even when the provider publishes no usable current payload.
  Otherwise local, remote, and WSL extension hosts load the same
  provider-owned adapter so they share one window-scoped tab bridge.
  After first registration, reload or restart each editor window, then relaunch
  its existing terminal or tmux clients so they receive the adapter socket.
  Relaunch those clients again after a later editor or extension-host restart.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/vscode.sh`.

After a fully successful merge the hook records a signature of its inputs and
converged destinations in `$XDG_CACHE_HOME/dot/merge-vscode-signature-v1`.
An update whose signature still matches skips the settings, keybinding, and
local-extension merge; extension installs always run. Any source, destination,
receipt, or hook change invalidates it, and `dot update -f` forces the full
merge. Deleting the file is always safe.
