-- dotfiles-nvim keeps its editor-only profile free of development services.
-- This explicit post-plugin extension point makes the dev re-enables win
-- without depending on plugin-module filename ordering.
return {
  { "neovim/nvim-lspconfig", enabled = true },
  { "mason-org/mason.nvim", enabled = true },
  { "mason-org/mason-lspconfig.nvim", enabled = true },
  { "stevearc/conform.nvim", enabled = true },
  { "mfussenegger/nvim-lint", enabled = true },
  { "folke/lazydev.nvim", enabled = true },
}
