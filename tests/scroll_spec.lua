local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Navigation Scroll", function()
  local temp_dir
  local many_files_dir

  before_each(function()
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       require("triad.ui").close_layout()
    end
    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    
    -- Create a dir with many files to force scrolling
    many_files_dir = temp_dir:joinpath("many")
    many_files_dir:mkdir()
    for i = 1, 50 do
        many_files_dir:joinpath(string.format("file_%02d.txt", i)):touch()
    end
    -- Make a subdir in the middle
    many_files_dir:joinpath("middle_dir"):mkdir()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("centers cursor when returning from subdirectory", function()
    vim.api.nvim_set_current_dir(many_files_dir:absolute())
    triad.open()
    vim.wait(50)
    
    -- Find "middle_dir" and enter it
    local buf = state.current_buf_id
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local target_idx
    for i, line in ipairs(lines) do
        if line:match("middle_dir") then
            target_idx = i
            break
        end
    end
    
    assert.is_not_nil(target_idx, "middle_dir not found")
    
    -- Move cursor to it
    vim.api.nvim_win_set_cursor(state.current_win_id, {target_idx, 0})
    
    -- Enter (Simulate 'l')
    local keymaps = vim.api.nvim_buf_get_keymap(state.current_buf_id, "n")
    for _, map in ipairs(keymaps) do
        if map.lhs == "l" then
            map.callback()
            break
        end
    end
    vim.wait(50)
    
    assert.equals(many_files_dir:joinpath("middle_dir"):absolute(), state.current_dir)
    
    -- Go back (Simulate 'h')
    keymaps = vim.api.nvim_buf_get_keymap(state.current_buf_id, "n")
    for _, map in ipairs(keymaps) do
        if map.lhs == "h" then
            map.callback()
            break
        end
    end
    vim.wait(50)
    
    -- Check cursor position
    local cursor = vim.api.nvim_win_get_cursor(state.current_win_id)
    assert.equals(target_idx, cursor[1], "Cursor should be back on middle_dir")
    
    -- Check Scroll (Topline)
    -- If centered, topline should be roughly target_idx - (height/2)
    local win_height = vim.api.nvim_win_get_height(state.current_win_id)
    local view = vim.api.nvim_win_call(state.current_win_id, vim.fn.winsaveview)
    local topline = view.topline
    
    -- It shouldn't be exactly target_idx (which would be 'zt' behavior/top of screen)
    -- unless window height is 1.
    -- If target_idx is e.g. 25, and height is 20.
    -- Centered means row 10 onscreen is line 25. Topline ~ 15.
    -- 'zt' would make Topline 25.
    
    -- We want to ensure it's NOT zt (topline == cursor line) if there's room above.
    if target_idx > win_height then
        assert.is_true(topline < target_idx, "View should be centered or contain context above, not just start at cursor. Topline: "..topline..", Cursor: "..target_idx)
    end
  end)
end)
