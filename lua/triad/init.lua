
---@class TriadConfig
---@field some_option string

local M = {}
local ui = require("triad.ui")
local state = require("triad.state")
local git = require("triad.git") -- Add this line
local default_config = require("triad.config")

--- Setup function for Triad.nvim
--- @param opts TriadConfig | nil
function M.setup(opts)
  state.config = vim.tbl_deep_extend("force", default_config, opts or {})
end

--- Opens the Triad file explorer
function M.open()
  -- Ensure config is initialized if setup wasn't called
  if not state.config then
    state.config = default_config
  end
  
  state.set_current_dir(vim.fn.getcwd())
  ui.create_layout()
  git.fetch_git_status() -- Add this line
end

return M
