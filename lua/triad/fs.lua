
---@class TriadFS
local M = {}

local Path = require("plenary.path")
local state = require("triad.state") -- Require triad.state instead of triad.init

--- Reads the contents of a directory.
--- @param path string The path to the directory.
--- @return table|nil files A list of file/directory names, or nil if an error occurred.
--- @return string|nil err An error message if an error occurred.
function M.read_dir(path)
  local files = {}
  local handle, err = vim.uv.fs_opendir(path)
  if err then
    return nil, "Failed to open directory: " .. err
  end

  while true do
    local entries = vim.uv.fs_readdir(handle)
    if not entries then -- End of directory or error
      break
    end

    for _, entry in ipairs(entries) do
      local name = entry.name
      if name ~= "." and name ~= ".." then
        if state.config and not state.config.show_hidden and name:sub(1,1) == "." then
          -- Skip hidden files if show_hidden is false
        else
          table.insert(files, name)
        end
      end
    end
  end

  vim.uv.fs_closedir(handle)
  table.sort(files)
  return files
end

--- Renames a file or directory.
--- @param old_path string The old path.
--- @param new_path string The new path.
--- @return boolean success True if successful, false otherwise.
--- @return string|nil err An error message if an error occurred.
function M.rename(old_path, new_path)
  local ok, err = vim.uv.fs_rename(old_path, new_path)
  if err then
    return false, "Failed to rename: " .. err
  else
    return true
  end
end

--- Unlinks (deletes) a file.
--- @param path string The path to the file.
--- @return boolean success True if successful, false otherwise.
--- @return string|nil err An error message if an error occurred.
function M.unlink(path)
  local ok, err = vim.uv.fs_unlink(path)
  if err then
    return false, "Failed to delete: " .. err
  else
    return true
  end
end

--- Creates a directory.
--- @param path string The path to the directory.
--- @return boolean success True if successful, false otherwise.
--- @return string|nil err An error message if an error occurred.
function M.mkdir(path)
  -- 493 is 0755 in octal
  local ok, err = vim.uv.fs_mkdir(path, 493)
  if err then
    return false, "Failed to create directory: " .. err
  else
    return true
  end
end

--- Creates an empty file.
--- @param path string The path to the file.
--- @return boolean success True if successful, false otherwise.
--- @return string|nil err An error message if an error occurred.
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
