-- Dotfiles adapter for Checkrun's provider-owned Neovim integration.
--
-- Checkrun owns the portable editor-metadata contract and all host
-- materialization rules. Dotfiles owns only two deployment choices: where its
-- checked metadata projection lives and how dependency assets resolve through
-- shdeps. Keeping those callbacks here prevents consumer policy from leaking
-- into Checkrun while avoiding a second implementation of its schema protocol.

local M = {}

local adapter_cache = nil
local metadata_cache = nil

local function dep_file(dependency, asset)
  return require("config.dot-runtime").dep_file(dependency, asset)
end

-- The checkrun-nvim merge hook generates this projection on every
-- `dot update`. Resolve its state directory the way Dot's dot_xdg_path does:
-- only an absolute XDG_STATE_HOME counts, otherwise $HOME/.local/state. Until
-- the first update writes it, the adapter finds no file and Neovim runs
-- without Checkrun schemas rather than failing.
local metadata_suffix = "dot/overlays/dev/checkrun-editor-metadata.json"

local function metadata_path()
  local state = vim.env.XDG_STATE_HOME
  if state == nil or state:sub(1, 1) ~= "/" then
    local home = vim.env.HOME
    if home == nil or home:sub(1, 1) ~= "/" then
      return nil
    end
    state = (home == "/" and "" or home) .. "/.local/state"
  end
  return state .. "/" .. metadata_suffix
end

function M.module()
  if adapter_cache ~= nil then
    return adapter_cache or nil
  end

  local path = dep_file("cgraf78/checkrun", "lib/checkrun/nvim.lua")
  if not path then
    adapter_cache = false
    return nil
  end

  adapter_cache = dofile(path)
  return adapter_cache
end

local function editor_metadata()
  if metadata_cache then
    return metadata_cache
  end

  local adapter = M.module()
  if not adapter then
    metadata_cache = { capabilities = {}, schemas = { json = {}, yaml = {}, toml = {} } }
    return metadata_cache
  end
  if type(adapter.editor_metadata) ~= "function" then
    error("checkrun Neovim adapter lacks editor_metadata; run dot update")
  end

  metadata_cache = adapter.editor_metadata({
    path = metadata_path(),
    resolve_dependency = dep_file,
  })
  return metadata_cache
end

function M.capability_opts()
  return { capabilities = vim.deepcopy(editor_metadata().capabilities) }
end

function M.schema_opts()
  return { config = vim.deepcopy(editor_metadata().schemas) }
end

return M
