---@class TriadPreview
local M = {}

local state = require("triad.state")
local config = require("triad.config")
local fs = require("triad.fs")
local cache = require("triad.cache")
local Path = require("plenary.path")

local DEBOUNCE_TIME_MS = 100
local PREFETCH_DEBOUNCE_MS = 150
local timer = nil
local prefetch_timer = nil
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

local icon_ns_id = vim.api.nvim_create_namespace("TriadPreviewIcons")

--- Gets the devicon for a given filename.
--- @param filename string The name of the file.
--- @param is_dir boolean Whether the file is a directory.
--- @return string icon The devicon.
--- @return string highlight The highlight group for the icon.
local function get_devicon(filename, is_dir)
  setup_devicons()
  if devicons then
    if is_dir then
      return "", "Directory"
    end
    local extension = filename:match("^.+%.(.+)$")
    local icon, hl = devicons.get_icon(filename, extension, { default = true })
    return icon or "", hl or ""
  end
  return "", ""
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
local function render_preview_buffer(lines, highlights)
  if not vim.api.nvim_buf_is_valid(state.preview_buf_id) then return end

  vim.api.nvim_buf_set_option(state.preview_buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.preview_buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.preview_buf_id, "modifiable", false)
  
  -- Apply highlights if provided
  if highlights then
      vim.api.nvim_buf_clear_namespace(state.preview_buf_id, icon_ns_id, 0, -1)
      for _, hl in ipairs(highlights) do
           if hl.icon_hl and hl.icon_hl ~= "" then
               vim.api.nvim_buf_set_extmark(state.preview_buf_id, icon_ns_id, hl.line, 0, {
                   end_col = hl.icon_end,
                   hl_group = hl.icon_hl,
               })
           end
           if hl.is_dir then
               vim.api.nvim_buf_set_extmark(state.preview_buf_id, icon_ns_id, hl.line, hl.name_start, {
                   end_col = hl.name_end,
                   hl_group = "TriadDirectory",
               })
           end
      end
  end
end

--- Async file read
local function read_file_async(path, limit, callback)
    vim.uv.fs_open(path, "r", 438, function(err, fd) 
        if err then callback(nil, err) return end
        
        -- Read a chunk
        vim.uv.fs_read(fd, 8192, 0, function(err, data) 
             vim.uv.fs_close(fd)
             if err then callback(nil, err) return end
             
             -- Binary check
             if data and data:find("\0") then
                 callback(nil, "binary")
                 return
             end
             
             -- Split lines
             local lines = {}
             if data then
                 for s in data:gmatch("[^\r\n]+") do
                     table.insert(lines, s)
                     if #lines >= limit then break end
                 end
                 if #lines == 0 and #data > 0 then table.insert(lines, data) end -- Handle single line case better
             end
             callback(lines)
        end)
    end)
end

--- Helper to format directory listing for preview
local function format_dir_listing(file_path, files)
    local lines = {}
    local highlights = {}
    
    for _, name in ipairs(files) do
       local full_path = Path:new(file_path, name):__tostring()
       -- We need sync stat here for icons? Or guess?
       -- Async stat for every file in dir listing is expensive.
       -- fs.read_dir already gives us sorted list but not types in the list (it returns names).
       -- Let's assume sync stat is okay-ish or just default to unknown icon?
       -- Actually fs.read_dir implementation in fs.lua does stat calls anyway, but doesn't return them.
       -- For now, let's use sync stat as in original code, but we are inside async callback chain, 
       -- so strictly speaking we should avoid blocking. But stat is fast.
       local stat = vim.uv.fs_stat(full_path)
       local is_dir = stat and stat.type == "directory"
       
       local icon, icon_hl = get_devicon(name, is_dir)
       if icon == "" then icon = "-" end
       
       local display = icon .. " " .. name
       if is_dir then display = display .. "/" end
       table.insert(lines, display)
       
       local icon_end = #icon
       local name_start = icon_end + 1
       local name_end = #display
       
       table.insert(highlights, {
          line = #lines - 1,
          icon_hl = icon_hl,
          icon_end = icon_end,
          is_dir = is_dir,
          name_start = name_start,
          name_end = name_end
       })
    end
    return lines, highlights
end


--- Loads data (dir or file) asynchronously and caches it.
--- @param file_path string
--- @param callback function(entry: table|nil)
local function load_and_cache(file_path, callback)
    vim.uv.fs_stat(file_path, function(err, stat) 
        if err then 
            callback({ lines = { "Error: " .. err } })
            return 
        end

        if stat.type == "directory" then
            fs.read_dir_async(file_path, function(files, err) 
                if err then
                    callback({ lines = { "Error reading dir: " .. err } })
                else
                    -- We need to schedule the formatting because it calls require() and UI stuff maybe?
                    -- Actually get_devicon calls require. Safe in schedule.
                    vim.schedule(function()
                        local lines, highlights = format_dir_listing(file_path, files)
                        local entry = { lines = lines, highlights = highlights, type = "directory" }
                        cache.set_preview(file_path, entry)
                        callback(entry)
                    end)
                end
            end)
        elseif stat.type == "file" then
            read_file_async(file_path, 100, function(lines, err) 
                 vim.schedule(function()
                     if err == "binary" then
                         local entry = { lines = { "[Binary File]" }, type = "binary" }
                         cache.set_preview(file_path, entry)
                         callback(entry)
                     elseif err then
                         local entry = { lines = { "Error reading file: " .. tostring(err) }, type = "error" }
                         cache.set_preview(file_path, entry)
                         callback(entry)
                     else
                         local entry = { lines = lines, type = "text" }
                         cache.set_preview(file_path, entry)
                         callback(entry)
                     end
                 end)
            end)
        else
            vim.schedule(function()
                local entry = { lines = { "[Unknown Type]" }, type = "unknown" }
                cache.set_preview(file_path, entry)
                callback(entry)
            end)
        end
    end)
end

--- Debounced function to update the preview pane.
--- @param file_path string The path to the file/directory to preview.
function M.update_preview(file_path)
  if timer then timer:stop() end
  
  if not file_path then
      render_preview_buffer({ "" })
      return
  end
  
  -- Check Cache First (Sync check)
  local cached = cache.get_preview(file_path)
  if cached then
      render_preview_buffer(cached.lines, cached.highlights)
      return
  end

  -- Cache Miss: Debounce and Async Load
  timer = vim.uv.new_timer()
  timer:start(DEBOUNCE_TIME_MS, 0, vim.schedule_wrap(function()
    load_and_cache(file_path, function(entry) 
        render_preview_buffer(entry.lines, entry.highlights)
    end)
  end))
end

--- Prefetches a specific path (Async, no render)
function M.prefetch(file_path)
    if not file_path then return end
    if cache.get_preview(file_path) then return end
    
    load_and_cache(file_path, function(_) end)
end

--- Prefetches surroundings of the cursor
--- @param current_dir string
--- @param cursor_row number 1-based index
--- @param buffer_lines string[]
function M.prefetch_surroundings(current_dir, cursor_row, buffer_lines)
    if prefetch_timer then prefetch_timer:stop() end
    
    prefetch_timer = vim.uv.new_timer()
    prefetch_timer:start(PREFETCH_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
        local range = 5 -- Prefetch 5 items up and down
        local targets = {}
        
        -- Helper to resolve path from line
        local function get_path(line)
             if not line then return nil end
             local name = line:match("[^%s]*%s?(.*)")
             if not name or name == "" then return nil end
             if name:sub(-1) == "/" then name = name:sub(1, -2) end
             return Path:new(current_dir, name):__tostring()
        end
        
        -- 1. Surroundings
        for i = math.max(1, cursor_row - range), math.min(#buffer_lines, cursor_row + range) do
            if i ~= cursor_row then -- Skip current, it's already handled by update_preview
                local path = get_path(buffer_lines[i])
                if path then table.insert(targets, path) end
            end
        end
        
        -- 2. Child Directory (if current is dir)
        local current_path = get_path(buffer_lines[cursor_row])
        if current_path then
            -- We can't know if it's a dir easily without checking cache or stat
            -- But prefetch checks stat anyway.
            -- However, for the "first child" requirement:
            -- If current_path is a directory, we want to read_dir it, and then prefetch the first item in it.
            -- This is a "deep prefetch".
            
            -- Check if current is dir in cache?
            local entry = cache.get_preview(current_path)
            if entry and entry.type == "directory" then
                -- It's a directory, and we have the listing!
                -- Find first item
                if entry.lines and #entry.lines > 0 then
                    local first_line = entry.lines[1]
                    local first_name = first_line:match("[^%s]*%s?(.*)")
                    if first_name and first_name ~= "" then
                         if first_name:sub(-1) == "/" then first_name = first_name:sub(1, -2) end
                         local child_path = Path:new(current_path, first_name):__tostring()
                         table.insert(targets, child_path)
                    end
                end
            elseif not entry then
                 -- If not cached, standard prefetch will load it. 
                 -- We might want to chain the deep prefetch? 
                 -- For now, let's just add current_path to targets (it might be already added or handled).
                 -- Actually, if we are on it, update_preview triggered load.
                 -- We can hook into that? Too complex.
                 -- Let's just hope the user hovers for >100ms.
            end
        end
        
        -- Execute Prefetches
        for _, path in ipairs(targets) do
            M.prefetch(path)
        end
    end))
end

return M