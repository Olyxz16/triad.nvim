
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
    local extension = filename:match("^.+%.(.+)$")
    local icon, hl = devicons.get_icon(filename, extension, { default = true })
    if is_dir then
        -- nvim-web-devicons usually handles dirs poorly via get_icon, check if there is a specific dir api or just use default
        -- But let's stick to get_icon for now, maybe override for dirs if needed.
        -- Actually, let's check if we can just pass nil extension.
        icon, hl = devicons.get_icon(filename, nil, { default = true })
    end
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
  if not state.current_dir then return end
  if not state.parent_buf_id or not vim.api.nvim_buf_is_valid(state.parent_buf_id) then return end

  local parent_path_str = Path:new(state.current_dir):parent():__tostring()
  local files, err = fs.read_dir(parent_path_str)
  if err then
    render_buffer(state.parent_buf_id, { "Error: " .. err })
    return
  end

  local lines_to_render = {}
  for _, file_name in ipairs(files) do
    local full_path = Path:new(parent_path_str, file_name):__tostring()
    local stat = vim.uv.fs_stat(full_path)
    local is_dir = stat and stat.type == "directory"

    local icon = get_devicon(file_name, is_dir)
    table.insert(lines_to_render, icon .. " " .. file_name)
  end
  render_buffer(state.parent_buf_id, lines_to_render)
end

--- Renders the contents of the current directory to the current pane.
function M.render_current_pane()
  if not state.current_dir then return end
  if not state.current_buf_id or not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end

  local files, err = fs.read_dir(state.current_dir)
  if err then
    render_buffer(state.current_buf_id, { "Error: " .. err })
    return
  end

  state.reset_original_file_data()
  local lines_to_render = {}
  for i, file_name in ipairs(files) do
    state.original_file_data[i] = Path:new(state.current_dir, file_name):__tostring()
    local display_name = file_name

    local full_path = Path:new(state.current_dir, file_name):__tostring()
    local stat = vim.uv.fs_stat(full_path)
    local is_dir = stat and stat.type == "directory"

    -- Prepend devicon
    local dev_icon = get_devicon(file_name, is_dir)
    if dev_icon == "" then dev_icon = "-" end
    display_name = dev_icon .. " " .. display_name

    -- Prepend git status icon
    local git_status = state.git_status_data[file_name]
    if git_status then
      local git_icon = ""
      if git_status == "M " then git_icon = state.config.git_icons.modified
      elseif git_status == "A " then git_icon = state.config.git_icons.added
      elseif git_status == "D " then git_icon = state.config.git_icons.deleted
      elseif git_status == "?? " then git_icon = state.config.git_icons.untracked
      elseif git_status == "!! " then git_icon = state.config.git_icons.ignored
      elseif git_status:sub(1,1) == "R" then git_icon = state.config.git_icons.renamed -- Renamed files start with 'R'
      end
      if git_icon ~= "" then
        display_name = git_icon .. " " .. display_name
      end
    end
    table.insert(lines_to_render, display_name)
  end

  render_buffer(state.current_buf_id, lines_to_render)
end

local oil_augroup_id = vim.api.nvim_create_augroup("TriadOilEngine", { clear = true })
local preview_augroup_id = vim.api.nvim_create_augroup("TriadPreview", { clear = true })
local autoclose_augroup_id = vim.api.nvim_create_augroup("TriadAutoClose", { clear = true })
local autohighlight_augroup_id = vim.api.nvim_create_augroup("TriadAutoHighlight", { clear = true }) -- New augroup for highlight

M.highlight_ns_id = vim.api.nvim_create_namespace("TriadHighlights") -- New namespace for highlight
local is_closing = false

-- Define the highlight group for the selected line
vim.api.nvim_set_hl(0, "TriadSelectedLine", { link = "Visual" }) -- Link to 'Visual' by default

--- Helper to set/clear line highlight
--- @param buf_id number
--- @param line_num number|nil 1-based line number to highlight, or nil to clear all.
local function set_line_highlight(buf_id, line_num)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then return end
  vim.api.nvim_buf_clear_namespace(buf_id, M.highlight_ns_id, 0, -1) -- Clear all custom highlights

  if line_num then
    vim.api.nvim_buf_add_highlight(buf_id, M.highlight_ns_id, "TriadSelectedLine", line_num - 1, 0, -1)
  end
end

--- Handles BufWriteCmd for the current pane to manage file system changes.
local function handle_buf_write()
  -- ... (no change needed here usually, assuming schedule handles valid checks if render called)
  -- Actually, handle_buf_write calls render_current_pane in schedule, which now has checks.
  local current_lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)

  local new_files = {}
  for _, line in ipairs(current_lines) do
    new_files[line] = true
  end

  -- Detect deletions and renames
  for line_num, original_full_path in pairs(state.original_file_data) do
    local original_file_name = Path:new(original_full_path).name
    local new_file_name_with_icons = current_lines[line_num]
    local new_file_name = new_file_name_with_icons:match("[^%s]*%s?(.*)") -- Remove leading icon and space

    if not new_file_name_with_icons then
      -- Line was deleted
      vim.schedule(function()
        local ok, err = fs.unlink(original_full_path)
        if not ok then
          vim.notify("Triad: Failed to delete " .. original_file_name .. ": " .. err, vim.log.levels.ERROR)
        end
      end)
    elseif new_file_name ~= original_file_name then
      -- Line was renamed
      vim.schedule(function()
        local new_full_path = Path:new(state.current_dir, new_file_name):__tostring()
        local ok, err = fs.rename(original_full_path, new_full_path)
        if not ok then
          vim.notify("Triad: Failed to rename " .. original_file_name .. " to " .. new_file_name .. ": " .. err, vim.log.levels.ERROR)
        end
      end)
    end
  end

  -- For now, just re-render to reflect changes made by deletes/renames
  vim.schedule(function()
    M.render_current_pane()
    M.render_parent_pane()
  end)
end

--- Sets up the autocommands for the current buffer for file system changes.
function M.setup_file_system_watcher()
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = oil_augroup_id,
    buffer = state.current_buf_id,
    callback = handle_buf_write,
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
  
  -- Clear all existing buffer-local normal mode mappings that might conflict
  local keys_to_clear = { "q", "h", "-", "l", "<CR>", "j", "k", "e", "<Esc>" } -- Add <Esc> if mapped elsewhere
  for _, key in ipairs(keys_to_clear) do
    pcall(vim.keymap.del, "n", key, { buffer = state.current_buf_id })
  end

  -- Set Read-Only
  vim.api.nvim_buf_set_option(state.current_buf_id, "modifiable", false)
  
  local opts = { noremap = true, silent = true, buffer = state.current_buf_id }

  -- Close panel
  vim.keymap.set("n", "q", function() M.close_layout() end, opts)

  -- Parent Directory
  local go_parent = function()
    local parent_path = Path:new(state.current_dir):parent():__tostring()
    state.set_current_dir(parent_path)
    M.render_parent_pane()
    M.render_current_pane()
    require("triad.git").fetch_git_status()
    M.enable_nav_mode() -- Ensure we stay in nav mode (re-applies settings/maps if lost)
  end
  vim.keymap.set("n", "h", go_parent, opts)
  vim.keymap.set("n", "-", go_parent, opts)

  -- Enter Directory (l key)
  local enter_dir_only = function()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.current_buf_id, cursor_row - 1, cursor_row, false)[1]
    if not line_content then return end

    local filename = line_content:match("[^%s]*%s?(.*)")
    local full_path = Path:new(state.current_dir, filename):__tostring()
    
    local stat = vim.uv.fs_stat(full_path)
    if stat and stat.type == "directory" then
      state.set_current_dir(full_path)
      M.render_parent_pane()
      M.render_current_pane()
      require("triad.git").fetch_git_status()
      M.enable_nav_mode()
    end
  end
  vim.keymap.set("n", "l", enter_dir_only, opts)

  -- Open / Enter (CR key)
  local open_entry = function()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.current_buf_id, cursor_row - 1, cursor_row, false)[1]
    if not line_content then return end

    local filename = line_content:match("[^%s]*%s?(.*)")
    local full_path = Path:new(state.current_dir, filename):__tostring()
    
    local stat = vim.uv.fs_stat(full_path)
    if stat and stat.type == "directory" then
      state.set_current_dir(full_path)
      M.render_parent_pane()
      M.render_current_pane()
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

  -- Switch to Edit Mode
  vim.keymap.set("n", "e", function() M.enable_edit_mode() end, opts)

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
function M.enable_edit_mode()
  if not vim.api.nvim_buf_is_valid(state.current_buf_id) then return end

  -- Clear all existing buffer-local normal mode mappings
  pcall(vim.keymap.del, "n", "q", { buffer = state.current_buf_id })
  pcall(vim.keymap.del, "n", "h", { buffer = state.current_buf_id })
  pcall(vim.keymap.del, "n", "-", { buffer = state.current_buf_id })
  pcall(vim.keymap.del, "n", "l", { buffer = state.current_buf_id })
  pcall(vim.keymap.del, "n", "<CR>", { buffer = state.current_buf_id })
  pcall(vim.keymap.del, "n", "j", { buffer = state.current_buf_id })
  pcall(vim.keymap.del, "n", "k", { buffer = state.current_buf_id })
  pcall(vim.keymap.del, "n", "e", { buffer = state.current_buf_id })

  -- Set Read-Write
  vim.api.nvim_buf_set_option(state.current_buf_id, "modifiable", true)

  local opts = { noremap = true, silent = true, buffer = state.current_buf_id }

  -- Map Esc to exit Edit Mode and Save
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_buf_is_valid(state.current_buf_id) then
        vim.cmd("write") -- Sync changes
    end
    M.enable_nav_mode()
  end, opts)

  -- Ensure we are in Normal mode when entering Edit Mode and cursor is visible
  vim.cmd("normal! Gzz") 
  -- No startinsert. User can use any Vim edit command (i, a, o, dd, cw, etc.)
  -- from Normal mode in this editable buffer.
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
  vim.api.nvim_win_set_option(state.parent_win_id, "winfixwidth", true)

  -- Current Window
  win_opts.col = col + parent_width + 2 -- +2 for border accounting
  state.current_win_id = vim.api.nvim_open_win(state.current_buf_id, true, win_opts)
  vim.api.nvim_win_set_width(state.current_win_id, current_width)
  vim.api.nvim_win_set_option(state.current_win_id, "winfixwidth", true)

  -- Preview Window
  win_opts.col = col + parent_width + current_width + 4 -- +4 for two previous windows borders
  state.preview_win_id = vim.api.nvim_open_win(state.preview_buf_id, true, win_opts)
  vim.api.nvim_win_set_width(state.preview_win_id, preview_width)
  vim.api.nvim_win_set_option(state.preview_win_id, "winfixwidth", true)

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
