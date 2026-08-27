-- Sort after dotfiles-nvim's editor policy so these explicit re-enables win.
return {
  -- dotfiles-nvim keeps its editor-only profile free of development services.
  -- Re-enable the LazyVim core specs that this capability owns before the
  -- language and debugger extras extend them.
  { "neovim/nvim-lspconfig", enabled = true },
  { "mason-org/mason.nvim", enabled = true },
  { "mason-org/mason-lspconfig.nvim", enabled = true },
  { "stevearc/conform.nvim", enabled = true },
  { "mfussenegger/nvim-lint", enabled = true },
  { "folke/lazydev.nvim", enabled = true },

  { import = "lazyvim.plugins.extras.dap.core" },
  { import = "lazyvim.plugins.extras.lang.clangd" },
  { import = "lazyvim.plugins.extras.lang.cmake" },
  { import = "lazyvim.plugins.extras.lang.docker" },
  { import = "lazyvim.plugins.extras.lang.git" },
  { import = "lazyvim.plugins.extras.lang.go" },
  { import = "lazyvim.plugins.extras.lang.json" },
  { import = "lazyvim.plugins.extras.lang.python" },
  { import = "lazyvim.plugins.extras.lang.rust" },
  { import = "lazyvim.plugins.extras.lang.thrift" },
  { import = "lazyvim.plugins.extras.lang.toml" },
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.lang.yaml" },
  { import = "lazyvim.plugins.extras.lsp.none-ls" },
  { import = "lazyvim.plugins.extras.util.dot" },
}
