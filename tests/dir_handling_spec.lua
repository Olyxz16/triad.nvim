local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")
local fs = require("triad.fs")

-- Helper to extract filename
local function get_filename_from_display_line(line)
  if not line then return nil end
  local name = line:match("[^%s]*%s?(.*)") or line
  if name:sub(-1) == "/" then
      name = name:sub(1, -2)
  end
  return name
end

describe("Triad Directory Handling", function()
  local temp_dir
  local subdir_name = "subdir"

  before_each(function()
    -- Clean up
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       require("triad.ui").close_layout()
    end

    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    temp_dir:joinpath("file.txt"):touch()
    temp_dir:joinpath(subdir_name):mkdir()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("renders directories with trailing slash", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local found_subdir = false
    for _, line in ipairs(lines) do
      -- Check if subdir line ends in "/"
      -- The line contains icon + space + subdir/
      if line:match(subdir_name .. "/$") then
        found_subdir = true
      end
    end
    assert.is_true(found_subdir, "Subdirectory should be rendered with trailing slash")
  end)

  it("creates a new directory when name ends with /", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    require("triad.ui").enable_edit_mode()
    
    -- Add a new line "newdir/"
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    table.insert(lines, "newdir/")
    vim.api.nvim_buf_set_lines(state.current_buf_id, 0, -1, false, lines)
    
    -- Save
    vim.cmd("write")
    vim.wait(100) -- Wait for schedule

    local new_dir_path = temp_dir:joinpath("newdir")
    assert.is_true(new_dir_path:exists(), "New directory should exist")
    assert.is_true(new_dir_path:is_dir(), "New item should be a directory")
  end)
  
  it("creates a new file when name does not end with /", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    require("triad.ui").enable_edit_mode()
    
    -- Add a new line "newfile.lua"
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    table.insert(lines, "newfile.lua")
    vim.api.nvim_buf_set_lines(state.current_buf_id, 0, -1, false, lines)
    
    -- Save
    vim.cmd("write")
    vim.wait(100)

    local new_file_path = temp_dir:joinpath("newfile.lua")
    assert.is_true(new_file_path:exists(), "New file should exist")
    assert.is_true(new_file_path:is_file(), "New item should be a file")
  end)
end)
