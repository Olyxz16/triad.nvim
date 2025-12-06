local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

-- Helper to extract filename, matching ui.lua's logic
local function get_filename_from_display_line(line)
  if not line then return nil end
  -- Match pattern used in ui.lua: icon + space + filename
  local name = line:match("[^%s]*%s?(.*)")
  if name and name:sub(-1) == "/" then
    name = name:sub(1, -2)
  end
  return name
end

describe("Triad Cursor Memory", function()
  local temp_dir
  local sub_dir_name = "subdir"
  local sub_dir_path
  local sub_sub_dir_name = "subsubdirA"
  local sub_sub_dir_path

  before_each(function()
    -- Cleanup windows
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       require("triad.ui").close_layout()
    end

    -- Setup FS
    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    
    -- Create 'subdir' and some files to ensure it's not the only item or first by chance (sort order)
    -- Make Root have multiple files so 'subdir' is not at line 1.
    temp_dir:joinpath("a_1.txt"):touch()
    temp_dir:joinpath("a_2.txt"):touch()
    temp_dir:joinpath("a_3.txt"):touch()
    -- Create a directory that comes BEFORE 'subdir' alphabetically to ensure 'subdir' is not first.
    temp_dir:joinpath("aa_dir"):mkdir() 
    sub_dir_path = temp_dir:joinpath(sub_dir_name)
    sub_dir_path:mkdir()
    -- 'subdir' should be 2nd (aa_dir, subdir, ...files...)
    
    -- Populate subdir with just ONE file so cursor is forced to line 1
    sub_dir_path:joinpath("inner.txt"):touch()
    -- subdir: inner.txt (1 line)
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("remembers cursor position when navigating up", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    -- Assert we are at root.
    -- We want to navigate TO subdir.
    -- Find line with "subdir"
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local subdir_idx = nil
    for i, line in ipairs(lines) do
      if get_filename_from_display_line(line) == sub_dir_name then
        subdir_idx = i
        break
      end
    end
    assert.is_not_nil(subdir_idx, "subdir not found in list")
    assert.is_true(subdir_idx > 1, "subdir should not be at line 1 for this test")
    
    -- Move cursor to subdir
    local win = state.current_win_id
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, {subdir_idx, 0})
    
    -- Enter (Simulate '<Right>' or '<CR>')
    local keymaps = vim.api.nvim_buf_get_keymap(state.current_buf_id, "n")
    for _, map in ipairs(keymaps) do
        if map.lhs == "<Right>" then
            map.callback()
            break
        end
    end
    vim.wait(50)
    
    assert.equals(sub_dir_path:absolute(), state.current_dir)
    
    -- Check cursor in subdir
    -- Go back (Simulate '<Left>')
    keymaps = vim.api.nvim_buf_get_keymap(state.current_buf_id, "n")
    for _, map in ipairs(keymaps) do
        if map.lhs == "<Left>" then
            map.callback()
            break
        end
    end
    vim.wait(50)
    
    -- Verify we are back at root
    assert.equals(temp_dir:absolute(), state.current_dir)
    
    -- KEY CHECK: Cursor should be on "subdir" line (subdir_idx)
    local new_cursor = vim.api.nvim_win_get_cursor(win)
    local new_row = new_cursor[1]
    
    local new_line = vim.api.nvim_buf_get_lines(state.current_buf_id, new_row - 1, new_row, false)[1]
    
    -- If bug exists, new_row will be 1 (carried over from subdir), so new_line will be 'a_1.txt'
    assert.is_true(get_filename_from_display_line(new_line) == sub_dir_name, "Cursor did not return to subdir. Got: " .. tostring(new_line))
  end)
end)
