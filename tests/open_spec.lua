local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Opening", function()
  local temp_dir
  local test_file_path

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
    
    test_file_path = temp_dir:joinpath("open_me.txt")
    test_file_path:touch()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("opens file on <CR>", function()
    -- Ensure we have a normal window open first
    local original_win = vim.api.nvim_get_current_win()
    
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    -- Find the line with open_me.txt
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local file_idx = nil
    for i, line in ipairs(lines) do
      if line:match("open_me.txt") then
        file_idx = i
        break
      end
    end
    assert.is_not_nil(file_idx, "open_me.txt not found in current pane")

    -- Move cursor
    local win = state.current_win_id
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, {file_idx, 0})

    -- Press Enter
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
    vim.wait(100)

    -- Assert Triad closed (state IDs should be -1 or windows invalid)
    assert.equals(-1, state.current_win_id)
    
    -- Assert file is open in the current window
    local current_buf_name = vim.api.nvim_buf_get_name(0)
    assert.is_true(current_buf_name:match("open_me.txt") ~= nil, "Current buffer should be open_me.txt")
    
    -- Check we are in the original window or at least a non-float
    local current_win = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(current_win)
    assert.equals("", config.relative, "Should not be in a floating window")
  end)
end)
