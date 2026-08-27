return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewRefresh" },
    keys = {
      { "<leader>dv", "<cmd>DiffviewOpen<cr>", desc = "Diff changes" },
      { "<leader>dr", "<cmd>DiffviewRefresh<cr>", desc = "Refresh diff view" },
      { "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>dc", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
    },
  },
}
