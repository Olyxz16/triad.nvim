
---@class TriadPreview
local M = {}

local state = require("triad.state")
local config = require("triad.config")
local fs = require("triad.fs")
local Path = require("plenary.path")

local DEBOUNCE_TIME_MS = 100
local timer = nil
local devicons = nil

--- Initializes devicons if enabled in the config.
local function setup_devicons()
  if devicons then return end -- Already loaded
  if state.config and state.config.devicons_enabled then
    local ok, lib = pcall(require, "nvim-web-devicons")
    if ok then
      devicons = lib
    end
  end
end

--- Gets the devicon for a given filename.
--- @param filename string The name of the file.
--- @param is_dir boolean Whether the file is a directory.
--- @return string icon The devicon.
local function get_devicon(filename, is_dir)
  setup_devicons()
  if devicons then
    if is_dir then
      return ""
    end
    local extension = filename:match("^.+%.(.+)$")
    local icon = devicons.get_icon(filename, extension, { default = true })
    return icon or ""
  end
  return ""
end

--- Determines the type of a file/path.
--- @param path string The path to check.
--- @return "directory" | "text" | "binary" | "unknown" | "error" type The type of the path.
--- @return string|nil err An error message if an error occurred.
function M.get_file_type(path)
  local stat, err = vim.uv.fs_stat(path)
  if err then
    return "error", err
  end

  if stat.type == "directory" then
    return "directory"
  elseif stat.type == "file" then
    -- Heuristic to guess if it's a text file
    -- Read a small chunk and check for null bytes
    local file_handle, open_err = vim.uv.fs_open(path, "r", 438) -- 0o666
    if open_err then
      return "error", open_err
    end
    local chunk, read_err = vim.uv.fs_read(file_handle, 2048, 0) -- Read first 2KB
    vim.uv.fs_close(file_handle)

    if read_err then
      return "error", read_err
    end

    if chunk and chunk:find("\0") then
      return "binary"
    else
      return "text"
    end
  end
  return "unknown"
end

--- Loads content of a text file.
--- @param path string The path to the file.
--- @param limit number Maximum number of lines to read.
--- @return string[]|nil lines The lines of the file, or nil if an error occurred.
--- @return string|nil err An error message if an error occurred.
function M.load_file_content(path, limit)
  local ok, lines = pcall(vim.fn.readfile, path, "", limit)
  if ok then
    return lines
  else
    -- vim.fn.readfile errors are raised, pcall catches them
    return nil, "Failed to read file: " .. tostring(lines)
  end
end

--- Renders content to the preview buffer.
--- @param lines string[] The lines to render.
local function render_preview_buffer(lines)
  if not vim.api.nvim_buf_is_valid(state.preview_buf_id) then return end

  vim.api.nvim_buf_set_option(state.preview_buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.preview_buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.preview_buf_id, "modifiable", false)
end

--- Debounced function to update the preview pane.
--- @param file_path string The path to the file/directory to preview.
function M.update_preview(file_path)
  if timer then
    timer:stop()
  end
  timer = vim.uv.new_timer()
  timer:start(DEBOUNCE_TIME_MS, 0, vim.schedule_wrap(function()
    if not file_path then
      render_preview_buffer({ "" })
      return
    end

    local file_type, err = M.get_file_type(file_path)
    if err then
      render_preview_buffer({ "Error: " .. err })
      return
    end

    if file_type == "directory" then
      local files, read_err = fs.read_dir(file_path)
      if read_err then
        render_preview_buffer({ "Error reading directory: " .. read_err })
      else
        local lines = {}
        for _, name in ipairs(files) do
           local full_path = Path:new(file_path, name):__tostring()
           local stat = vim.uv.fs_stat(full_path)
           local is_dir = stat and stat.type == "directory"
           
           local icon = get_devicon(name, is_dir)
           if icon == "" then icon = "-" end -- Default placeholder if no icon
           
           local display = icon .. " " .. name
           if is_dir then display = display .. "/" end
           table.insert(lines, display)
        end
        render_preview_buffer(lines)
      end
    elseif file_type == "text" then
      local lines, read_err = M.load_file_content(file_path, 100) -- Read first 100 lines
      if read_err then
        render_preview_buffer({ "Error reading file: " .. read_err })
      else
        render_preview_buffer(lines)
      end
    elseif file_type == "binary" then
      render_preview_buffer({ "[Binary File]" })
    else
      render_preview_buffer({ "[Unknown File Type]" })
    end
  end))
end

return M
