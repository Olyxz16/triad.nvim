
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
    parent_width = 15,  -- Left pane (Short)
    current_width = 45, -- Center pane (Medium)
    preview_width = 40, -- Right pane (Largest, remainder)
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
    conflict = '',
    -- Future: colors
  },
  devicons_enabled = true,
  show_hidden = false,
}

return config
