
---@class TriadUI
local M = {}

local state = require("triad.state")
local fs = require("triad.fs")
local preview = require("triad.preview")
local Path = require("plenary.path")

local devicons = nil

--- Initializes devicons if enabled in the config.
local function setup_devicons()
  if devicons then return end -- Already loaded
  if state.config and state.config.devicons_enabled then
    local ok, lib = pcall(require, "nvim-web-devicons")
    if ok then
      devicons = lib
    else
      vim.notify("Triad: nvim-web-devicons is enabled in config but not found. Disabling.", vim.log.levels.WARN)
    end
  end
end

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

--- Creates a new buffer for a Triad pane
--- @param name string Name of the buffer
--- @param buftype string buftype (e.g., 'nofile', 'acwrite')
--- @return number Buffer ID
local function create_triad_buffer(name, buftype)
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf_id, "triad://" .. name)
  vim.api.nvim_buf_set_option(buf_id, "buftype", buftype)
  vim.api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf_id, "swapfile", false)
  vim.api.nvim_buf_set_option(buf_id, "filetype", "triad")
  vim.api.nvim_buf_set_option(buf_id, "modifiable", false) -- Default to read-only
  vim.api.nvim_buf_set_option(buf_id, "undolevels", 1000)
  return buf_id
end

--- Renders a table of lines to a given buffer.
--- @param buf_id number The ID of the buffer to render to.
--- @param lines string[] The table of lines to write.
local function render_buffer(buf_id, lines)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then return end

  vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

--- Renders the contents of the parent directory to the parent pane.
function M.render_parent_pane()
  if state.is_edit_mode then return end
  if not state.current_dir then return end
  if not state.parent_buf_id or not vim.api.nvim_buf_is_valid(state.parent_buf_id) then return end

  local parent_path_str = Path:new(state.current_dir):parent():__tostring()
  local files, err = fs.read_dir(parent_path_str)
  if err then
    render_buffer(state.parent_buf_id, { "Error: " .. err })
    return
  end

  local lines_to_render = {}
  local highlights = {} -- Stores highlight info

  for _, file_name in ipairs(files) do
    local full_path = Path:new(parent_path_str, file_name):__tostring()
    local stat = vim.uv.fs_stat(full_path)
    local is_dir = stat and stat.type == "directory"

    local icon, icon_hl = get_devicon(file_name, is_dir)
    local display_name = icon .. " " .. file_name
    if is_dir then display_name = display_name .. "/" end
    table.insert(lines_to_render, display_name)

    -- Store highlight info
    local icon_end = #icon
    local name_start = icon_end + 1
    local name_end = #display_name

    table.insert(highlights, {
        line = #lines_to_render - 1,
        icon_hl = icon_hl,
        icon_end = icon_end,
        is_dir = is_dir,
        name_start = name_start,
        name_end = name_end
    })
  end
  render_buffer(state.parent_buf_id, lines_to_render)

  -- Apply Highlights
  vim.api.nvim_buf_clear_namespace(state.parent_buf_id, M.icon_ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
      if hl.icon_hl and hl.icon_hl ~= "" then
          vim.api.nvim_buf_set_extmark(state.parent_buf_id, M.icon_ns_id, hl.line, 0, {
              end_col = hl.icon_end,
              hl_group = hl.icon_hl,
          })
      end
      if hl.is_dir then
          vim.api.nvim_buf_set_extmark(state.parent_buf_id, M.icon_ns_id, hl.line, hl.name_start, {
              end_col = hl.name_end,
              hl_group = "TriadDirectory",
          })
      end
  end
end

--- Renders the contents of the current directory to the current pane.
function M.render_current_pane()
  if state.is_edit_mode then return end
  if not state.current_dir then return end
  if not state.current_buf_id or not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end

  local files, err = fs.read_dir(state.current_dir)
  if err then
    render_buffer(state.current_buf_id, { "Error: " .. err })
    return
  end

  state.reset_original_file_data()
  local lines_to_render = {}
  local git_extmarks = {} -- Stores {line_idx, icon, hl_group}
  local highlights = {} -- Stores highlight info

  -- Resolve current_dir to real path once for consistent git lookup (handles symlinks)
  local real_current_dir = vim.fn.resolve(state.current_dir)

  for i, file_name in ipairs(files) do
    state.original_file_data[i] = Path:new(state.current_dir, file_name):__tostring()
    local display_name = file_name

    local full_path = Path:new(state.current_dir, file_name):__tostring()
    local stat = vim.uv.fs_stat(full_path)
    local is_dir = stat and stat.type == "directory"

    -- Prepend devicon
    local dev_icon, dev_hl = get_devicon(file_name, is_dir)
    if dev_icon == "" then dev_icon = "-" end
    display_name = dev_icon .. " " .. display_name

    if is_dir then
        display_name = display_name .. "/"
    end

    table.insert(lines_to_render, display_name)

    -- Highlight Info
    local icon_end = #dev_icon
    local name_start = icon_end + 1
    local name_end = #display_name

    table.insert(highlights, {
        line = #lines_to_render - 1,
        icon_hl = dev_hl,
        icon_end = icon_end,
        is_dir = is_dir,
        name_start = name_start,
        name_end = name_end
    })

    -- Git status icon (Extmarks)
    -- Use real_current_dir for lookup key construction to match git's absolute paths
    local lookup_path = Path:new(real_current_dir, file_name):__tostring()
    if lookup_path:sub(-1) == "/" then lookup_path = lookup_path:sub(1, -2) end
    
    local git_status = state.git_status_data[lookup_path]
    if git_status then
      local git_icon = ""
      local git_hl = "Normal"
      local s1 = git_status:sub(1, 1)
      local s2 = git_status:sub(2, 2)
      
      if s1 == "U" or s2 == "U" or (s1 == "A" and s2 == "A") or (s1 == "D" and s2 == "D") then
         git_icon = state.config.git_icons.conflict
         git_hl = "TriadGitConflict"
      elseif s1 == "?" then
         git_icon = state.config.git_icons.untracked
         git_hl = "TriadGitUntracked"
      elseif s1 == "!" then
         git_icon = state.config.git_icons.ignored
         git_hl = "Comment"
      elseif s1 == "M" or s2 == "M" then
         git_icon = state.config.git_icons.modified
         git_hl = "TriadGitModified"
      elseif s1 == "A" then
         git_icon = state.config.git_icons.added
         git_hl = "TriadGitAdded"
      elseif s1 == "R" then
         git_icon = state.config.git_icons.renamed
         git_hl = "TriadGitModified"
      elseif s1 == "D" then
         git_icon = state.config.git_icons.deleted
         git_hl = "TriadGitDeleted"
      end
      
      if git_icon ~= "" then
        table.insert(git_extmarks, { i - 1, git_icon, git_hl })
      end
    end
  end

  render_buffer(state.current_buf_id, lines_to_render)
  
  -- Apply Icon/Dir Highlights
  vim.api.nvim_buf_clear_namespace(state.current_buf_id, M.icon_ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
      if hl.icon_hl and hl.icon_hl ~= "" then
          vim.api.nvim_buf_set_extmark(state.current_buf_id, M.icon_ns_id, hl.line, 0, {
              end_col = hl.icon_end,
              hl_group = hl.icon_hl,
          })
      end
      if hl.is_dir then
          vim.api.nvim_buf_set_extmark(state.current_buf_id, M.icon_ns_id, hl.line, hl.name_start, {
              end_col = hl.name_end,
              hl_group = "TriadDirectory",
          })
      end
  end
  
  -- Apply Git Extmarks
  vim.api.nvim_buf_clear_namespace(state.current_buf_id, M.git_ns_id, 0, -1)
  for _, mark in ipairs(git_extmarks) do
      vim.api.nvim_buf_set_extmark(state.current_buf_id, M.git_ns_id, mark[1], 0, {
          virt_text = { { mark[2], mark[3] } },
          virt_text_pos = "right_align",
      })
  end
end

local oil_augroup_id = vim.api.nvim_create_augroup("TriadOilEngine", { clear = true })
local preview_augroup_id = vim.api.nvim_create_augroup("TriadPreview", { clear = true })
local autoclose_augroup_id = vim.api.nvim_create_augroup("TriadAutoClose", { clear = true })
local autohighlight_augroup_id = vim.api.nvim_create_augroup("TriadAutoHighlight", { clear = true }) -- New augroup for highlight

M.highlight_ns_id = vim.api.nvim_create_namespace("TriadHighlights") -- New namespace for highlight
M.git_ns_id = vim.api.nvim_create_namespace("TriadGitIcons") -- Namespace for git extmarks
M.icon_ns_id = vim.api.nvim_create_namespace("TriadIcons") -- Namespace for file icons

local is_closing = false

-- Define the highlight group for the selected line
vim.api.nvim_set_hl(0, "TriadSelectedLine", { link = "CursorLine" }) -- Link to 'CursorLine' to span full width
vim.api.nvim_set_hl(0, "TriadGitModified", { link = "GitSignsChange", default = true })
vim.api.nvim_set_hl(0, "TriadGitAdded", { link = "GitSignsAdd", default = true })
vim.api.nvim_set_hl(0, "TriadGitDeleted", { link = "GitSignsDelete", default = true })
vim.api.nvim_set_hl(0, "TriadGitConflict", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "TriadGitUntracked", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "TriadDirectory", { fg = "Cyan", default = true })

--- Gets the filename from a display line (stripping icons).
--- @param line string The display line.
--- @return string filename The filename.
local function get_filename_from_line(line)
  if not line then return "" end
  local name = line:match("[^%s]*%s?(.*)") or line
  -- Strip trailing slash if present
  if name:sub(-1) == "/" then
    name = name:sub(1, -2)
  end
  return name
end

--- Saves the current cursor position for the current directory.
local function save_cursor_position()
  if not state.current_dir or not state.current_buf_id or not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end
  local cursor = vim.api.nvim_win_get_cursor(state.current_win_id)
  local row = cursor[1]
  local line = vim.api.nvim_buf_get_lines(state.current_buf_id, row - 1, row, false)[1]
  local filename = get_filename_from_line(line)
  if filename and filename ~= "" then
    state.dir_cursor_history[state.current_dir] = filename
  end
end

--- Restores the cursor position for the current directory.
local function restore_cursor_position()
  if not state.current_dir or not state.current_buf_id or not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end
  local target_filename = state.dir_cursor_history[state.current_dir]
  if not target_filename then return end

  local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
  for i, line in ipairs(lines) do
    local fname = get_filename_from_line(line)
    if fname == target_filename then
       pcall(vim.api.nvim_win_set_cursor, state.current_win_id, {i, 0})
       -- Force redraw/scroll
       vim.cmd("normal! zz")
       return
    end
  end
end

--- Helper to set/clear line highlight
--- @param buf_id number
--- @param line_num number|nil 1-based line number to highlight, or nil to clear all.
local function set_line_highlight(buf_id, line_num)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then return end
  vim.api.nvim_buf_clear_namespace(buf_id, M.highlight_ns_id, 0, -1) -- Clear all custom highlights

  if line_num then
    vim.api.nvim_buf_set_extmark(buf_id, M.highlight_ns_id, line_num - 1, 0, {
        line_hl_group = "TriadSelectedLine",
        priority = 200,
    })
  end
end

--- Handles BufWriteCmd for the current pane to manage file system changes.
--- @param on_complete function|nil Callback(success: boolean)
function M.save_changes(on_complete)
  -- Read current lines from buffer
  local current_lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)

  -- 1. Identify Original Files (State)
  local original_names_set = {}
  local original_files_list = {} -- indexed by line number
  local max_orig_line = 0
  for line_num, full_path in pairs(state.original_file_data) do
    local name = vim.fn.fnamemodify(full_path, ":t")
    original_names_set[name] = true
    original_files_list[line_num] = { name = name, full_path = full_path }
    if line_num > max_orig_line then max_orig_line = line_num end
  end

  -- 2. Parse current lines
  local current_files = {}
  local current_idx = 1
  for i, line in ipairs(current_lines) do
    -- Skip empty or whitespace-only lines
    if line:match("%S") then
        local icon_part, name_part = line:match("^([^%s]*)%s?(.*)")
        local effective_name = line
        local raw_name = line
    
        if name_part and name_part ~= "" then
           local clean_name_part = name_part:gsub("/$", "")
           if original_names_set[clean_name_part] then
              effective_name = clean_name_part
              raw_name = name_part
           elseif icon_part == "-" or icon_part:match("[^%z\1-\127]") then 
              effective_name = clean_name_part
              raw_name = name_part
           else
              effective_name = line:gsub("/$", "")
              raw_name = line
           end
        else
           effective_name = line:gsub("/$", "")
           raw_name = line
        end
        current_files[current_idx] = { raw = raw_name, name = effective_name }
        current_idx = current_idx + 1
    end
  end

  -- 3. Calculate Diff
  local creates = {}
  local deletes = {}
  local renames = {}
  local processed_current = {}
  local processed_original = {}

  -- Identify Keeps (Same name exists)
  for i, file_info in ipairs(current_files) do
    if original_names_set[file_info.name] then
        processed_current[i] = true
        -- Mark original instance
        for orig_i, orig_data in pairs(original_files_list) do
            if orig_data.name == file_info.name then
                processed_original[orig_i] = true
                break
            end
        end
    end
  end

  local max_line = math.max(#current_files, max_orig_line)
  for i = 1, max_line do
    local curr = current_files[i]
    local orig = original_files_list[i]
    local is_curr_processed = processed_current[i]
    local is_orig_processed = processed_original[i]

    if curr and not is_curr_processed and orig and not is_orig_processed then
        table.insert(renames, { from = orig, to = curr })
        processed_current[i] = true
        processed_original[i] = true
    elseif curr and not is_curr_processed then
        table.insert(creates, curr)
        processed_current[i] = true
    elseif orig and not is_orig_processed then
        table.insert(deletes, orig)
        processed_original[i] = true
    end
  end
  
  -- Stragglers
  for line_num, orig_data in pairs(original_files_list) do
      if not processed_original[line_num] then
         table.insert(deletes, orig_data)
         processed_original[line_num] = true
      end
  end
  for i, curr in ipairs(current_files) do
      if not processed_current[i] then
        table.insert(creates, curr)
        processed_current[i] = true
      end
  end

  -- 4. Confirmation Logic
  local changes_count = #creates + #deletes + #renames
  if changes_count == 0 then
      vim.api.nvim_buf_set_option(state.current_buf_id, "modified", false)
      if on_complete then on_complete(true) end
      return
  end

  local summary = {}
  if #creates > 0 then table.insert(summary, "Create: " .. #creates) end
  if #renames > 0 then table.insert(summary, "Rename: " .. #renames) end
  if #deletes > 0 then table.insert(summary, "Delete: " .. #deletes) end
  
  local prompt_str = "Apply changes? (" .. table.concat(summary, ", ") .. ")"
  
  vim.ui.select({ "Yes", "No" }, {
    prompt = prompt_str,
    format_item = function(item) return item end
  }, function(choice)
    if choice == "Yes" then
        -- Apply Changes
        for _, item in ipairs(renames) do
            local new_full_path = Path:new(state.current_dir, item.to.name):__tostring()
            local ok, err = fs.rename(item.from.full_path, new_full_path)
            if not ok then vim.notify("Triad: Rename failed: " .. err, vim.log.levels.ERROR) end
        end
        for _, item in ipairs(creates) do
            local new_full_path = Path:new(state.current_dir, item.name):__tostring()
            local is_dir = item.raw:sub(-1) == "/"
            if is_dir then
               local ok, err = fs.mkdir(new_full_path)
               if not ok then vim.notify("Triad: Mkdir failed: " .. err, vim.log.levels.ERROR) end
            else
               local ok, err = fs.touch(new_full_path)
               if not ok then vim.notify("Triad: Touch failed: " .. err, vim.log.levels.ERROR) end
            end
        end
        for _, item in ipairs(deletes) do
            local ok, err = fs.unlink(item.full_path)
            if not ok then vim.notify("Triad: Delete failed: " .. err, vim.log.levels.ERROR) end
        end
        
        -- Finalize
        vim.schedule(function()
            vim.api.nvim_buf_set_option(state.current_buf_id, "modified", false)
            M.render_current_pane()
            M.render_parent_pane()
            if on_complete then on_complete(true) end
        end)
    else
        vim.notify("Triad: Changes cancelled. Press 'u' to undo edits.")
        if on_complete then on_complete(false) end
    end
  end)
end

--- Sets up the autocommands for the current buffer for file system changes.
function M.setup_file_system_watcher()
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = oil_augroup_id,
    buffer = state.current_buf_id,
    callback = function() M.save_changes(nil) end,
  })
end

--- Sets up the autocommands for the current buffer to update the preview pane.
function M.setup_preview_watcher()
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = preview_augroup_id,
    buffer = state.current_buf_id,
    callback = vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end
      -- ... rest of logic
      local cursor = vim.api.nvim_win_get_cursor(0)
      local cursor_row = cursor[1]
      local line_content_with_icons = vim.api.nvim_buf_get_lines(state.current_buf_id, cursor_row - 1, cursor_row, false)[1]
      if not line_content_with_icons then return end
      local line_content = line_content_with_icons:match("[^%s]*%s?(.*)") -- Remove leading icon and space

      if line_content and line_content ~= "" then
        local file_path = Path:new(state.current_dir, line_content):__tostring()
        preview.update_preview(file_path)
      else
        preview.update_preview(nil)
      end
    end),
  })
end

--- Closes all Triad windows and buffers
function M.close_layout()
  if is_closing then return end
  is_closing = true

  -- Close windows first
  if state.parent_win_id and state.parent_win_id ~= -1 and vim.api.nvim_win_is_valid(state.parent_win_id) then
      pcall(vim.api.nvim_win_close, state.parent_win_id, true)
  end
  if state.current_win_id and state.current_win_id ~= -1 and vim.api.nvim_win_is_valid(state.current_win_id) then
      pcall(vim.api.nvim_win_close, state.current_win_id, true)
  end
  if state.preview_win_id and state.preview_win_id ~= -1 and vim.api.nvim_win_is_valid(state.preview_win_id) then
      pcall(vim.api.nvim_win_close, state.preview_win_id, true)
  end

  if vim.api.nvim_buf_is_valid(state.parent_buf_id) then
    pcall(vim.api.nvim_buf_delete, state.parent_buf_id, { force = true })
  end
  if vim.api.nvim_buf_is_valid(state.current_buf_id) then
    pcall(vim.api.nvim_buf_delete, state.current_buf_id, { force = true })
  end
  if vim.api.nvim_buf_is_valid(state.preview_buf_id) then
    pcall(vim.api.nvim_buf_delete, state.preview_buf_id, { force = true })
  end
  
  -- Clear autocmds instead of deleting groups to preserve IDs
  pcall(vim.api.nvim_clear_autocmds, { group = oil_augroup_id })
  pcall(vim.api.nvim_clear_autocmds, { group = preview_augroup_id })
  pcall(vim.api.nvim_clear_autocmds, { group = autoclose_augroup_id })
  pcall(vim.api.nvim_clear_autocmds, { group = autohighlight_augroup_id })

  state.parent_win_id = -1
  state.current_win_id = -1
  state.preview_win_id = -1
end

--- Sets up auto-close when any Triad buffer is closed.
function M.setup_autoclose()
  local bufs = { state.parent_buf_id, state.current_buf_id, state.preview_buf_id }
  vim.api.nvim_clear_autocmds({ group = autoclose_augroup_id })
  
  for _, buf_id in ipairs(bufs) do
    vim.api.nvim_create_autocmd("BufWinLeave", {
      group = autoclose_augroup_id,
      buffer = buf_id,
      callback = function()
        local triggered_buf = buf_id
        vim.schedule(function()
             -- Check if the triggered buffer is still part of the active state.
             -- If state has changed (e.g. new session started), triggered_buf will not match.
             if triggered_buf == state.parent_buf_id or 
                triggered_buf == state.current_buf_id or 
                triggered_buf == state.preview_buf_id then
                  M.close_layout()
             end
        end)
      end,
    })
  end
end

--- Enables Navigation Mode (Read-Only, specialized keymaps)
function M.enable_nav_mode()
  if not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end
  
  state.is_edit_mode = false

  -- Clear all existing buffer-local normal mode mappings that might conflict
  local keys_to_clear = { "q", "h", "-", "l", "<CR>", "j", "k", "e", "<Esc>" } -- Add <Esc> if mapped elsewhere
  for _, key in ipairs(keys_to_clear) do
    pcall(vim.keymap.del, "n", key, { buffer = state.current_buf_id })
  end

  -- Set Read-Only
  vim.api.nvim_buf_set_option(state.current_buf_id, "modifiable", false)
  
  local opts = { noremap = true, silent = true, buffer = state.current_buf_id }

  -- Re-enable preview watcher since we disabled it in edit mode
  M.setup_preview_watcher()

  -- Close panel
  vim.keymap.set("n", "q", function() M.close_layout() end, opts)
  
  -- ... (rest of mappings)

  -- Parent Directory
  local go_parent = function()
    save_cursor_position()
    
    local old_dir = state.current_dir
    local parent_path = Path:new(state.current_dir):parent():__tostring()
    
    -- When going UP, we want to land on the directory we just left.
    if old_dir and parent_path then
       local target = Path:new(old_dir):make_relative(parent_path)
       if target == old_dir then -- failed to make relative
          target = vim.fn.fnamemodify(old_dir, ":t")
       end
       state.dir_cursor_history[parent_path] = target
    end

    state.set_current_dir(parent_path)
    M.render_parent_pane()
    M.render_current_pane()
    restore_cursor_position()

    require("triad.git").fetch_git_status()
    M.enable_nav_mode() -- Ensure we stay in nav mode (re-applies settings/maps if lost)
  end
  vim.keymap.set("n", "h", go_parent, opts)
  vim.keymap.set("n", "-", go_parent, opts)
  vim.keymap.set("n", "<Left>", go_parent, opts)

  -- Enter Directory (l key)
  local enter_dir_only = function()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.current_buf_id, cursor_row - 1, cursor_row, false)[1]
    if not line_content then return end

    local filename = line_content:match("[^%s]*%s?(.*)")
    local full_path = Path:new(state.current_dir, filename):__tostring()
    
    local stat = vim.uv.fs_stat(full_path)
    if stat and stat.type == "directory" then
      save_cursor_position()
      state.set_current_dir(full_path)
      M.render_parent_pane()
      M.render_current_pane()
      restore_cursor_position()
      require("triad.git").fetch_git_status()
      M.enable_nav_mode()
    end
  end
  vim.keymap.set("n", "l", enter_dir_only, opts)
  vim.keymap.set("n", "<Right>", enter_dir_only, opts)

  -- Open / Enter (CR key)
  local open_entry = function()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.current_buf_id, cursor_row - 1, cursor_row, false)[1]
    if not line_content then return end

    local filename = line_content:match("[^%s]*%s?(.*)")
    local full_path = Path:new(state.current_dir, filename):__tostring()
    
    local stat = vim.uv.fs_stat(full_path)
    if stat and stat.type == "directory" then
      save_cursor_position()
      state.set_current_dir(full_path)
      M.render_parent_pane()
      M.render_current_pane()
      restore_cursor_position()
      require("triad.git").fetch_git_status()
      M.enable_nav_mode()
    elseif stat and stat.type == "file" then
      -- Open file
      M.close_layout()
      if state.prev_win_id and state.prev_win_id ~= -1 and vim.api.nvim_win_is_valid(state.prev_win_id) then
        vim.api.nvim_set_current_win(state.prev_win_id)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(full_path))
    end
  end
  vim.keymap.set("n", "<CR>", open_entry, opts)

  -- Default movement: j, k
  vim.keymap.set("n", "j", "j", opts)
  vim.keymap.set("n", "k", "k", opts)
  vim.keymap.set("n", "<Down>", "j", opts)
  vim.keymap.set("n", "<Up>", "k", opts)

  -- Switch to Edit Mode
  vim.keymap.set("n", "e", function() M.enable_edit_mode() end, opts)
  
  -- Implicit Edit Mode triggers
  vim.keymap.set("n", "i", function() 
      M.enable_edit_mode(function() vim.cmd("startinsert") end) 
  end, opts)
  
  vim.keymap.set("n", "a", function() 
      M.enable_edit_mode(function() vim.cmd("startinsert") vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Right>", true, false, true), "n", false) end) 
      -- Alternatively, just feed "a"? But we are in normal mode. `startinsert` is `i`. `startinsert!` is `A`.
      -- `a` is `l` + `i`.
      -- Simpler: feedkeys.
  end, opts)
  
  -- Re-mapping correctly using feedkeys for robust behavior
  local function trigger_edit(key)
      return function()
          M.enable_edit_mode(function()
              vim.api.nvim_feedkeys(key, "n", false)
          end)
      end
  end

  vim.keymap.set("n", "i", trigger_edit("i"), opts)
  vim.keymap.set("n", "I", trigger_edit("I"), opts)
  vim.keymap.set("n", "a", trigger_edit("a"), opts)
  vim.keymap.set("n", "A", trigger_edit("A"), opts)

  -- Set up CursorMoved autocommand for line highlighting
  vim.api.nvim_clear_autocmds({ group = autohighlight_augroup_id })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = autohighlight_augroup_id,
    buffer = state.current_buf_id,
    callback = vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end
      local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
      set_line_highlight(state.current_buf_id, cursor_row)
    end),
  })
  -- Initial highlight
  local initial_cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  set_line_highlight(state.current_buf_id, initial_cursor_row)
end

--- Enables Edit Mode (Read-Write, standard Vim keymaps)
--- @param post_action function|nil Optional callback to run after enabling edit mode
function M.enable_edit_mode(post_action)
  if not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end
  
  -- Ensure we are in the correct window for normal commands
  if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
      vim.api.nvim_set_current_win(state.current_win_id)
  end

  state.is_edit_mode = true

  -- Disable preview watcher while editing to prevent focus stealing or overhead
  if state.current_buf_id then
      pcall(vim.api.nvim_clear_autocmds, { group = preview_augroup_id, buffer = state.current_buf_id })
  end

  -- Clear all existing buffer-local normal mode mappings
  local keys_to_clear = { "q", "h", "-", "l", "<CR>", "j", "k", "e", "i", "a", "I", "A" }
  for _, key in ipairs(keys_to_clear) do
      pcall(vim.keymap.del, "n", key, { buffer = state.current_buf_id })
  end

  local opts = { noremap = true, silent = true, buffer = state.current_buf_id }

  -- Map Esc to exit Edit Mode and Save
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_buf_is_valid(state.current_buf_id) then
        M.save_changes(function(success)
            if success then
                M.enable_nav_mode()
            end
        end)
    end
  end, opts)

  -- Ensure we are in Normal mode and cursor is visible
  vim.cmd("normal! Gzz") 
  
  -- Set Read-Write LAST to ensure it sticks
  vim.api.nvim_buf_set_option(state.current_buf_id, "modifiable", true)
  
  -- Reset undo history to establish the current state as the baseline.
  -- This ensures that the first edit (e.g., dd) is undoable back to the initial list.
  local old_undolevels = vim.api.nvim_buf_get_option(state.current_buf_id, "undolevels")
  if old_undolevels < 1000 then old_undolevels = 1000 end -- Ensure we have levels
  
  vim.api.nvim_buf_set_option(state.current_buf_id, "undolevels", -1)
  vim.api.nvim_buf_set_option(state.current_buf_id, "undolevels", old_undolevels)
  
  -- Verify
  if not vim.api.nvim_buf_get_option(state.current_buf_id, "modifiable") then
      vim.notify("Triad: Failed to set modifiable=true!", vim.log.levels.ERROR)
  else
      vim.notify("Triad: Edit Mode Enabled")
      if post_action then
          post_action()
      end
  end
end

--- Creates and sets up the three Triad windows (parent, current, preview)
function M.create_layout()
  is_closing = false -- Reset guard
  
  -- Capture previous window
  state.prev_win_id = vim.api.nvim_get_current_win()

  local editor_width = vim.api.nvim_get_option("columns")
  local editor_height = vim.api.nvim_get_option("lines")

  local total_width = math.floor(editor_width * 0.8)
  local total_height = math.floor(editor_height * 0.8)

  local row = math.floor((editor_height - total_height) / 2)
  local col = math.floor((editor_width - total_width) / 2)

  local parent_width = math.floor(total_width * state.config.layout.parent_width / 100)
  local current_width = math.floor(total_width * state.config.layout.current_width / 100)
  -- Preview takes the rest
  local preview_width = total_width - parent_width - current_width

  -- Ensure minimum widths
  parent_width = math.max(parent_width, 15)
  current_width = math.max(current_width, 30)
  preview_width = math.max(preview_width, 30)
  
  -- Recalculate total width in case minimums pushed it
  total_width = parent_width + current_width + preview_width
  -- Re-center
  col = math.floor((editor_width - total_width) / 2)

  -- Create buffers
  state.parent_buf_id = create_triad_buffer("parent", "nofile")
  state.current_buf_id = create_triad_buffer("current", "acwrite")
  state.preview_buf_id = create_triad_buffer("preview", "nofile")

  -- Create Floating Windows
  local win_opts = {
    relative = 'editor',
    row = row,
    col = col,
    width = parent_width,
    height = total_height,
    style = 'minimal',
    border = 'single'
  }

  -- Parent Window
  state.parent_win_id = vim.api.nvim_open_win(state.parent_buf_id, true, win_opts)
  vim.api.nvim_win_set_config(state.parent_win_id, { focusable = false })
  vim.api.nvim_win_set_option(state.parent_win_id, "winfixwidth", true)
  vim.api.nvim_win_set_option(state.parent_win_id, "winhighlight", "Normal:Normal,FloatBorder:Normal")

  -- Current Window
  win_opts.col = col + parent_width + 2 -- +2 for border accounting
  state.current_win_id = vim.api.nvim_open_win(state.current_buf_id, true, win_opts)
  vim.api.nvim_win_set_width(state.current_win_id, current_width)
  vim.api.nvim_win_set_option(state.current_win_id, "winfixwidth", true)
  vim.api.nvim_win_set_option(state.current_win_id, "winhighlight", "Normal:Normal,FloatBorder:Normal")

  -- Preview Window
  win_opts.col = col + parent_width + current_width + 4 -- +4 for two previous windows borders
  state.preview_win_id = vim.api.nvim_open_win(state.preview_buf_id, true, win_opts)
  vim.api.nvim_win_set_config(state.preview_win_id, { focusable = false })
  vim.api.nvim_win_set_width(state.preview_win_id, preview_width)
  vim.api.nvim_win_set_option(state.preview_win_id, "winfixwidth", true)
  vim.api.nvim_win_set_option(state.preview_win_id, "winhighlight", "Normal:Normal,FloatBorder:Normal")

  -- Set initial cursor to the current pane
  vim.api.nvim_set_current_win(state.current_win_id)

  M.render_parent_pane()
  M.render_current_pane()
  M.setup_file_system_watcher()
  M.setup_preview_watcher() -- Setup the preview watcher
  M.setup_autoclose() -- Setup simultaneous close
  M.enable_nav_mode() -- Initial mode
end

return M
