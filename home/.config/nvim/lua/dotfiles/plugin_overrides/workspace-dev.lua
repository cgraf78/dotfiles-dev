local vcs_markers = { ".git", ".hg", ".jj", ".svn" }
local vcs_root_env = {
  DOT_GIT_REAL = "1",
  SLEY_SKIP_BARE_REPO_FALLBACK = "1",
}

local function normalize_dir(path)
  return (vim.fn.fnamemodify(path, ":p"):gsub("/+$", ""))
end

local function home()
  return normalize_dir(vim.env.HOME or "~")
end

local function contains(root, path)
  root = normalize_dir(root)
  path = normalize_dir(path)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function marker_root(cwd)
  local marker = vim.fs.find(vcs_markers, { path = cwd, upward = true, limit = 1 })[1]
  if marker then
    local root = normalize_dir(vim.fs.dirname(marker))
    if root ~= home() then
      return root
    end
  end
end

local function option_marker_root(opts)
  if type(opts) == "table" and type(opts.marker_root) == "string" and opts.marker_root ~= "" then
    local root = normalize_dir(opts.marker_root)
    if root ~= home() then
      return root
    end
  end
end

local function sley_root(cwd, opts)
  local fast_root = option_marker_root(opts) or marker_root(cwd)
  if fast_root then
    return fast_root
  end
  if contains(home(), cwd) or vim.fn.executable("sley") ~= 1 then
    return nil
  end

  local ok, result = pcall(function()
    return vim
      .system({ "sley", "status", "--json" }, {
        cwd = cwd,
        text = true,
        env = vcs_root_env,
      })
      :wait()
  end)
  if not ok or result.code ~= 0 or result.stdout == "" then
    return nil
  end

  local decoded_ok, decoded = pcall(vim.json.decode, result.stdout)
  if decoded_ok and type(decoded) == "table" and type(decoded.root) == "string" then
    return decoded.root
  end
end

local function dotfiles_lazygit_opts(path, ctx)
  local rel = ctx.relative_to_default_root(path)
  if not rel then
    return nil
  end

  local root = ctx.default_root
  local git_dir = home() .. "/.dotfiles"
  local stat = vim.uv.fs_stat(git_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  vim.fn.system({
    "git",
    "--git-dir",
    git_dir,
    "--work-tree",
    root,
    "ls-files",
    "--error-unmatch",
    "--",
    rel,
  })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  return {
    cwd = root,
    args = { "--work-tree", root, "--git-dir", git_dir },
  }
end

return {
  {
    "cgraf78/nvim-workspace",
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          vim.schedule(function()
            require("config.keymaps.workspace-dev").setup()
          end)
        end,
      })
    end,
    opts = function(_, opts)
      opts.workspace = opts.workspace or {}
      opts.workspace.repo_root_detector = function(cwd, detector_opts)
        return sley_root(cwd, detector_opts)
      end
      opts.lazygit = opts.lazygit or {}
      opts.lazygit.opts_for_path = dotfiles_lazygit_opts
    end,
  },
}
