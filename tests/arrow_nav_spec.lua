local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Arrow Navigation", function()
  local temp_dir
  local subdir
  local file1

  before_each(function()
    -- Cleanup windows
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if #vim.api.nvim_list_wins() > 1 then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end

    -- Setup FS
    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    
    subdir = temp_dir:joinpath("subdir")
    subdir:mkdir()
    
    file1 = temp_dir:joinpath("file1.txt")
    file1:touch()
    
    subdir:joinpath("subfile.txt"):touch()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("Right arrow navigates into directory", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(100)

    -- Find subdir line
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local subdir_line_idx = nil
    for i, line in ipairs(lines) do
      if line:match("subdir") then
        subdir_line_idx = i
        break
      end
    end
    assert.is_not_nil(subdir_line_idx, "subdir not found")

    local win = vim.fn.bufwinid(state.current_buf_id)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, {subdir_line_idx, 0})

    -- Press Right Arrow
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Right>", true, false, true), "mx", false)
    vim.wait(100)

    assert.equals(subdir:absolute(), state.current_dir)
  end)

  it("Right arrow does nothing on file", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(100)

    -- Find file1 line
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local file_line_idx = nil
    for i, line in ipairs(lines) do
      if line:match("file1.txt") then
        file_line_idx = i
        break
      end
    end
    assert.is_not_nil(file_line_idx, "file1.txt not found")

    local win = vim.fn.bufwinid(state.current_buf_id)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, {file_line_idx, 0})

    -- Press Right Arrow
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Right>", true, false, true), "mx", false)
    vim.wait(100)

    -- Should still be in temp_dir
    assert.equals(temp_dir:absolute(), state.current_dir)
    -- And Triad should still be open (buf valid)
    assert.is_true(vim.api.nvim_buf_is_valid(state.current_buf_id))
  end)

  it("Left arrow navigates up", function()
     vim.api.nvim_set_current_dir(subdir:absolute())
     triad.open()
     vim.wait(50)
     
     local win = vim.fn.bufwinid(state.current_buf_id)
     vim.api.nvim_set_current_win(win)

     -- Press Left Arrow
     vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Left>", true, false, true), "mx", false)
     vim.wait(50)

     assert.equals(temp_dir:absolute(), state.current_dir)
  end)
end)
