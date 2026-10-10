# shellcheck shell=bash
# Location of Neovim's generated Checkrun editor metadata.
#
# The checkrun-nvim merge hook publishes the file and dev profile deactivation
# removes it, so both resolve it here. Neovim's reader is Lua and mirrors the
# same rule in metadata_path() in .config/nvim/lua/config/checkrun-nvim.lua;
# workflow-consistency-test publishes through the hook and reads through Neovim
# to keep them aligned.

# Resolve the metadata path into REPLY with Dot's XDG state rule.
checkrun_nvim_metadata_path() {
  dot_xdg_path state dot/overlays/dev/checkrun-editor-metadata.json
}

# Remove staging files that Dot's sibling-temporary primitive created for the
# metadata DESTINATION (`<destination>.tmp.XXXXXX`) and an interrupted run left
# behind. Callers hold Dot's update lock, so no live run owns one.
checkrun_nvim_remove_staging() {
  local staged
  for staged in "$1".tmp.??????; do
    [[ -f $staged && ! -L $staged ]] && rm -f -- "$staged"
  done
  return 0
}
