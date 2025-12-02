
---@class TriadState
---@field current_dir string | nil
---@field parent_buf_id number
---@field current_buf_id number
---@field preview_buf_id number
---@field selected_file string
---@field file_data table
---@field original_file_data table<number, string> -- Maps line number to original full path
---@field git_status_data table<string, string> -- Maps filename to git status (e.g., " M", "??")
---@field config TriadConfig | nil -- Runtime configuration

local M = {}

M.current_dir = nil
M.parent_buf_id = -1
M.current_buf_id = -1
M.preview_buf_id = -1
M.parent_win_id = -1
M.current_win_id = -1
M.preview_win_id = -1
M.prev_win_id = -1 -- Window ID before Triad opened
M.selected_file = ""
M.file_data = {} -- Stores data about files in the current pane for diffing/renaming
M.original_file_data = {}
M.git_status_data = {}
M.config = nil

function M.set_current_dir(path)
  M.current_dir = path
end

function M.reset_original_file_data()
  M.original_file_data = {}
end

return M
