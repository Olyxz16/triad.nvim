local git = require("triad.git")
local state = require("triad.state")
local Job = require("plenary.job")
local ui = require("triad.ui")

-- Mock UI functions
vim.api.nvim_buf_set_extmark = function(...) 
  local args = {...}
  print("EXTMARK: " .. vim.inspect(args[5].virt_text))
end
vim.api.nvim_create_buf = function() return 1 end
vim.api.nvim_buf_is_valid = function() return true end
vim.api.nvim_buf_set_lines = function(...) end
vim.api.nvim_buf_clear_namespace = function(...) end

local cwd = vim.fn.tempname()
vim.fn.mkdir(cwd, "p")
state.current_dir = cwd
state.git_status_data = {}
state.current_buf_id = 1
state.config = require("triad.config")

-- Setup Repo
Job:new({ command = "git", args = { "init" }, cwd = cwd }):sync()
local file = cwd .. "/untracked.txt"
vim.fn.writefile({"hello"}, file)

print("CWD: " .. cwd)
print("File: " .. file)

-- Fetch Status
git.fetch_git_status()

-- Wait
vim.wait(2000, function() 
  local status = state.git_status_data[file]
  if status then print("STATUS FOUND: " .. status) end
  return status ~= nil 
end)

if not state.git_status_data[file] then
  print("STATUS NOT FOUND IN STATE")
  print("DUMP STATE: " .. vim.inspect(state.git_status_data))
end
