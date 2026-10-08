return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewRefresh" },
    keys = {
      { "<leader>dv", "<cmd>DiffviewOpen<cr>", desc = "Diff changes" },
      {
        "<leader>df",
        function()
          local file = vim.fn.expand("%")
          if file == "" then
            vim.cmd("DiffviewOpen")
          else
            vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(file))
          end
        end,
        desc = "Diff current file",
      },
      { "<leader>dr", "<cmd>DiffviewRefresh<cr>", desc = "Refresh diff view" },
      { "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>dc", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
    },
    opts = function()
      local actions = require("diffview.actions")
      local function cycle_layout_maps()
        return {
          { "n", "<C-x>", actions.cycle_layout, { desc = "Cycle diff layout" } },
          { "n", "<leader>dx", actions.cycle_layout, { desc = "Cycle diff layout" } },
        }
      end

      local function view_maps()
        local maps = cycle_layout_maps()
        -- Keep these view-local so the global Ctrl-Up/Down function-jump
        -- mappings still apply everywhere outside Diffview's diff buffers.
        vim.list_extend(maps, {
          { "n", "<C-Up>", "[c", { desc = "Previous diff hunk" } },
          { "n", "<C-Down>", "]c", { desc = "Next diff hunk" } },
        })
        return maps
      end

      return {
        view = {
          default = {
            -- Diffview names this layout "vertical", but it creates `:sp`
            -- windows: the old and new buffers are stacked top/bottom.
            layout = "diff2_vertical",
          },
        },
        keymaps = {
          view = view_maps(),
          file_panel = cycle_layout_maps(),
          file_history_panel = cycle_layout_maps(),
        },
      }
    end,
  },

  -- The diffview keys above win over the DAP extra's `<leader>dc` (continue)
  -- and `<leader>dr` (REPL). Two specs claiming one key leave it to whichever
  -- plugin loads last, so the binding flipped when DAP or Diffview loaded;
  -- dropping DAP's claim keeps the diffview binding from startup on.
  -- Continue moves to `<F5>` and the REPL moves to `<leader>dR` (debug.lua).
  -- `optional` keeps this fragment from adding nvim-dap when the extra is
  -- disabled.
  {
    "mfussenegger/nvim-dap",
    optional = true,
    keys = {
      { "<leader>dc", false },
      { "<leader>dr", false },
    },
  },

  -- The Rust extra's rust-analyzer on_attach also maps a buffer-local
  -- `<leader>dr` (Rust Debuggables), which shadowed the diffview key in Rust
  -- buffers once the server attached. Drop it after the extra's on_attach;
  -- `:RustLsp debuggables` remains.
  {
    "mrcjkb/rustaceanvim",
    optional = true,
    opts = function(_, opts)
      local on_attach = vim.tbl_get(opts, "server", "on_attach")
      if not on_attach then
        return
      end
      opts.server.on_attach = function(client, bufnr)
        on_attach(client, bufnr)
        pcall(vim.keymap.del, "n", "<leader>dr", { buffer = bufnr })
      end
    end,
  },
}
