local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad UI Navigation", function()
  local temp_dir
  local subdir

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
    
    temp_dir:joinpath("file1.txt"):touch()
    subdir:joinpath("subfile.txt"):touch()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("navigates into directories", function()
    -- Change to temp dir so Triad opens there
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    
    triad.open()

    -- Wait for UI to render (it's synchronous mostly, but good to be safe)
    vim.wait(100)

    -- Check initial state
    assert.equals(temp_dir:absolute(), state.current_dir)
    
    -- Find the line with "subdir"
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local subdir_line_idx = nil
    for i, line in ipairs(lines) do
      if line:match("subdir") then
        subdir_line_idx = i
        break
      end
    end
    assert.is_not_nil(subdir_line_idx, "subdir not found in current pane")

    -- Move cursor to subdir line
    local win = vim.fn.bufwinid(state.current_buf_id)
    vim.api.nvim_set_current_win(win) -- Ensure focus
    vim.api.nvim_win_set_cursor(win, {subdir_line_idx, 0})

    -- Trigger Enter (<CR>)
    -- We can simulate the keypress or call the mapping function. 
    -- Simulating keypress is better integration test.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
    
    -- Wait for async things (if any)
    vim.wait(100)

    -- Assert state updated
    assert.equals(subdir:absolute(), state.current_dir)

    -- Assert current buffer content updated
    local new_lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local found_subfile = false
    for _, line in ipairs(new_lines) do
      if line:match("subfile.txt") then
        found_subfile = true
        break
      end
    end
    assert.is_true(found_subfile, "Did not find subfile.txt after navigation")
  end)

  it("navigates up", function()
     -- Start in subdir
     vim.api.nvim_set_current_dir(subdir:absolute())
     triad.open()
     vim.wait(50)

     assert.equals(subdir:absolute(), state.current_dir)
     
     -- Ensure focus on current pane
     local win = vim.fn.bufwinid(state.current_buf_id)
     vim.api.nvim_set_current_win(win)

     -- Trigger "-"
     vim.api.nvim_feedkeys("-", "mx", false)
     vim.wait(50)

     -- Assert back to parent
     assert.equals(temp_dir:absolute(), state.current_dir)
     
     -- Assert current buffer lists subdir
     local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
     local found_subdir = false
     for _, line in ipairs(lines) do
       if line:match("subdir") then
         found_subdir = true
         break
       end
     end
     assert.is_true(found_subdir, "Did not find subdir after navigating up")
  end)
end)
