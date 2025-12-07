---@class TriadGit
local M = {}

local Job = require("plenary.job")
local state = require("triad.state")

--- Fetches and parses git status for the current directory.
function M.fetch_git_status()
  if not state.current_dir then return end

  -- 1. Get Git Root
  Job:new({
    command = "git",
    args = { "rev-parse", "--show-toplevel" },
    cwd = state.current_dir,
    on_exit = vim.schedule_wrap(function(j_root)
      if j_root.code ~= 0 then
         -- Not a git repo? Clear status
         state.git_status_data = {}
         state.is_git_repo = false
         state.git_root = nil
         require("triad.ui").render_current_pane()
         return 
      end
      
      local git_root = j_root:result()[1]
      if not git_root then return end

      state.is_git_repo = true
      state.git_root = git_root
      
      -- 2. Get Status
      Job:new({
        command = "git",
        args = { "status", "--porcelain", "--ignored" },
        cwd = state.current_dir,
        on_exit = vim.schedule_wrap(function(j_status)
          state.git_status_data = {}
          local output = j_status:result()
          for _, line in ipairs(output) do
            if #line > 3 then
              local status = line:sub(1, 2)
              local raw_path = line:sub(4)
              local filename = raw_path
              
              -- Handle Renames
              if status:sub(1, 1) == "R" then
                 local arrow_match = raw_path:match("%-> (.+)")
                 if arrow_match then
                     filename = arrow_match
                 end
              end
              
              -- Remove quotes if present
              filename = filename:match("^\"?(.-)\"?$")
              
              if filename then
                 local abs_path = git_root .. "/" .. filename
                 -- Normalize directory slash
                 if abs_path:sub(-1) == "/" then
                     abs_path = abs_path:sub(1, -2)
                 end
                 state.git_status_data[abs_path] = status
              end
            end
          end
          -- Trigger a re-render of the current pane to show git status
          require("triad.ui").render_current_pane()
        end),
      }):start()
    end),
  }):start()
end

return M