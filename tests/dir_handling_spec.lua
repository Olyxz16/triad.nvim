local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")
local fs = require("triad.fs")

local function trigger_confirm()
    local conf_buf = -1
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("triad://confirmation") then
            conf_buf = b
            break
        end
    end
    
    if conf_buf ~= -1 then
        local keymaps = vim.api.nvim_buf_get_keymap(conf_buf, "n")
        for _, map in ipairs(keymaps) do
            if map.lhs == "y" then
                map.callback()
                return true
            end
        end
    end
    return false
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
    
    -- Append a new line "newdir/" safely
    vim.api.nvim_buf_set_lines(state.current_buf_id, -1, -1, false, {"newdir/"})
    
    -- Save
    vim.cmd("write")
    vim.wait(50)
    
    -- Confirm
    trigger_confirm()
    vim.wait(100)

    local new_dir_path = temp_dir:joinpath("newdir")
    assert.is_true(new_dir_path:exists(), "New directory should exist")
    assert.is_true(new_dir_path:is_dir(), "New item should be a directory")
  end)
  
  it("creates a new file when name does not end with /", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    require("triad.ui").enable_edit_mode()
    
    -- Append a new line "newfile.lua" safely
    vim.api.nvim_buf_set_lines(state.current_buf_id, -1, -1, false, {"newfile.lua"})
    
    -- Save
    vim.cmd("write")
    vim.wait(50)
    
    -- Confirm
    trigger_confirm()
    vim.wait(100)

    local new_file_path = temp_dir:joinpath("newfile.lua")
    assert.is_true(new_file_path:exists(), "New file should exist")
    assert.is_true(new_file_path:is_file(), "New item should be a file")
  end)
end)