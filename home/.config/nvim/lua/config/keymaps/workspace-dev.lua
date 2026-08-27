local M = {}

function M.setup()
  if not rawget(_G, "Snacks") then
    pcall(require, "snacks")
  end
  vim.keymap.set("n", "<leader>gg", function()
    local opts = require("nvim_workspace.lazygit").opts()
    require("snacks.lazygit").open(opts)
  end, { desc = "Lazygit (Root Dir)" })
end

return M
