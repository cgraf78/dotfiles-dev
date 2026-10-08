# Development Neovim modules

Modules under `home/.config/nvim/lua/config/` define development policy such as
Mason fallbacks, language servers, schemas, Checkrun, and Sley integration.
Editor keymap domains, including the VSCode-style `config.keymaps.vscode`, are
owned by `dotfiles-nvim`; this overlay adds only `config.keymaps.workspace-dev`
for its Lazygit mapping.
