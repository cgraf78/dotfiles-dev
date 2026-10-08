-- Debug keys that mirror VS Code's (F5 continue, Shift-F5 stop, F9
-- breakpoint, F10/F11/Shift-F11 step over/into/out), added to the DAP extra's
-- `<leader>d` keys. Lazy spec keys load nvim-dap on first press.
--
-- tmux and xterm-style terminfo report Shift-F5 and Shift-F11 as F17 and F23,
-- so each shifted key also maps its legacy encoding. Inside the VS Code
-- integrated terminal, VS Code keeps F11 (full screen) and takes F5 and F10
-- while one of its own debug sessions is active; F9 always reaches Neovim.

local function dap(method)
  return function()
    require("dap")[method]()
  end
end

return {
  {
    "mfussenegger/nvim-dap",
    optional = true,
    -- stylua: ignore
    keys = {
      { "<F5>", dap("continue"), desc = "Run/Continue" },
      { "<S-F5>", dap("terminate"), desc = "Terminate" },
      { "<F17>", dap("terminate"), desc = "Terminate" },
      { "<F9>", dap("toggle_breakpoint"), desc = "Toggle Breakpoint" },
      { "<F10>", dap("step_over"), desc = "Step Over" },
      { "<F11>", dap("step_into"), desc = "Step Into" },
      { "<S-F11>", dap("step_out"), desc = "Step Out" },
      { "<F23>", dap("step_out"), desc = "Step Out" },
      -- `<leader>dr` belongs to Diffview (git-dev.lua), so the REPL moves to
      -- the uppercase key, beside the DAP extra's `dB`/`dC`/`dO`/`dP`.
      { "<leader>dR", function() require("dap").repl.toggle() end, desc = "Toggle REPL" },
    },
  },
}
