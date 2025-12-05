---
--@class TriadFS
local M = {}

local Path = require("plenary.path")
local state = require("triad.state") -- Require triad.state instead of triad.init

---
-- Reads the contents of a directory.
-- @param path string The path to the directory.
-- @return table|nil files A list of file/directory names, or nil if an error occurred.
-- @return string|nil err An error message if an error occurred.
function M.read_dir(path)
  local entries_list = {}
  local handle, err = vim.uv.fs_opendir(path)
  if err then
    return nil, "Failed to open directory: " .. err
  end

  -- Check if the path is actually inside the git repo we are tracking
  local is_inside_repo = false
  if state.is_git_repo and state.git_root then
      local resolved_path = vim.fn.resolve(path)
      -- Ensure strict prefix match (either root itself or subdir)
      -- Standardize trailing slash for matching if needed, but resolve usually strips it
      if resolved_path == state.git_root or resolved_path:sub(1, #state.git_root + 1) == state.git_root .. "/" then
          is_inside_repo = true
      end
  end

  while true do
    local entries = vim.uv.fs_readdir(handle)
    if not entries then -- End of directory or error
      break
    end

    for _, entry in ipairs(entries) do
      local name = entry.name
      if name ~= "." and name ~= ".." then
        local is_hidden = false
        local config_show_hidden = state.config and state.config.show_hidden

        if config_show_hidden then
            is_hidden = false
        else
            if is_inside_repo then
                -- Explicitly hide .git directory
                if name == ".git" then
                    is_hidden = true
                else
                    -- Git Mode: Hide ignored files
                    -- Resolve path to ensure matches git's resolved root
                    local resolved_path = vim.fn.resolve(path)
                    local full_path = Path:new(resolved_path, name):__tostring()
                    
                    -- Normalize path key to match git.lua's storage
                    if full_path:sub(-1) == "/" then full_path = full_path:sub(1, -2) end

                    local status = state.git_status_data[full_path]
                    if status and (status:sub(1, 1) == "!" or status:match("!!")) then
                        is_hidden = true
                    end
                end
                -- Dotfiles are NOT hidden by default in git mode (unless explicitly hidden above)
            else
                -- Non-Git Mode (or outside repo): Hide dotfiles
                if name:sub(1, 1) == "." then
                    is_hidden = true
                end
            end
        end

        if not is_hidden then
          table.insert(entries_list, entry)
        end
      end
    end
  end

  vim.uv.fs_closedir(handle)

  table.sort(entries_list, function(a, b)
    if a.type == 'directory' and b.type ~= 'directory' then return true end
    if a.type ~= 'directory' and b.type == 'directory' then return false end
    return a.name < b.name
  end)

  local files = {}
  for _, entry in ipairs(entries_list) do
    table.insert(files, entry.name)
  end

  return files
end

---
-- Renames a file or directory.
-- @param old_path string The old path.
-- @param new_path string The new path.
-- @return boolean success True if successful, false otherwise.
-- @return string|nil err An error message if an error occurred.
function M.rename(old_path, new_path)
  local ok, err = vim.uv.fs_rename(old_path, new_path)
  if err then
    return false, "Failed to rename: " .. err
  else
    return true
  end
end

---
-- Unlinks (deletes) a file.
-- @param path string The path to the file.
-- @return boolean success True if successful, false otherwise.
-- @return string|nil err An error message if an error occurred.
function M.unlink(path)
  local ok, err = vim.uv.fs_unlink(path)
  if err then
    return false, "Failed to delete: " .. err
  else
    return true
  end
end

---
-- Creates a directory.
-- @param path string The path to the directory.
-- @return boolean success True if successful, false otherwise.
-- @return string|nil err An error message if an error occurred.
function M.mkdir(path)
  -- 493 is 0755 in octal
  local ok, err = vim.uv.fs_mkdir(path, 493)
  if err then
    return false, "Failed to create directory: " .. err
  else
    return true
  end
end

---
-- Creates an empty file.
-- @param path string The path to the file.
-- @return boolean success True if successful, false otherwise.
-- @return string|nil err An error message if an error occurred.
function M.touch(path)
  -- 420 is 0644 in octal, "w" creates/truncates
  local fd, err = vim.uv.fs_open(path, "w", 420)
  if err then
    return false, "Failed to create file: " .. err
  end
  vim.uv.fs_close(fd)
  return true
end

return M