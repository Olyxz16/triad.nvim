
---@class TriadGit
local M = {}

local Job = require("plenary.job")
local state = require("triad.state")

--- Fetches and parses git status for the current directory.
function M.fetch_git_status()
  if not state.current_dir then return end

  Job:new({
    command = "git",
    args = { "status", "--porcelain", "-u" },
    cwd = state.current_dir,
    on_exit = vim.schedule_wrap(function(j)
      state.git_status_data = {}
      local output = j:result()
      for _, line in ipairs(output) do
        local status = line:sub(1, 2)
        local filename = line:sub(4):match("^\"?(.-)\"?$") -- Remove quotes if present
        if filename then
          state.git_status_data[filename] = status
        end
      end
      -- Trigger a re-render of the current pane to show git status
      require("triad.ui").render_current_pane()
    end),
  }):start()
end

return M
