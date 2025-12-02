
---@class TriadConfig
---@field layout table
---@field keymaps table
---@field git_icons table
---@field devicons_enabled boolean
---@field show_hidden boolean

local config = {}

-- Default configuration
config = {
  layout = {
    parent_width = 30,
    current_width = 50,
    preview_width = 80,
    -- Future: ratios, min/max widths
  },
  keymaps = {
    -- Future: h, l, CR, etc.
  },
  git_icons = {
    added = '',
    modified = '',
    deleted = '',
    untracked = '',
    ignored = '',
    renamed = '➜',
    -- Future: colors
  },
  devicons_enabled = true,
  show_hidden = false,
}

return config
