# Development Neovim plugins

Plugin specs under `home/.config/nvim/lua/plugins/` add language support, DAP,
formatting, linting, development Git workflows, and repository tools. Basic
editing and Gitsigns remain owned by `dotfiles-nvim`.

LazyVim extras live under `lua/dotfiles/lazyvim_extras/`, which the editor
imports before ordinary plugin specs. Final development overrides live under
`lua/dotfiles/plugin_overrides/`, which the editor imports afterward. Policy
constraints such as host-aware Mason disabling live under
`lua/dotfiles/final_policy/` and apply after those overrides. These explicit
extension points avoid relying on filename sorting for semantic ordering.
