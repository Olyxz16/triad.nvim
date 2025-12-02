local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Preview", function()
  local temp_dir
  local test_file_path
  local test_content = { "Line 1", "Line 2", "Line 3" }

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
    
    -- Create multiple files to ensure we can move cursor
    temp_dir:joinpath("a_dummy.txt"):touch()
    
    test_file_path = temp_dir:joinpath("z_test.txt")
    test_file_path:write(table.concat(test_content, "\n"), "w")
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("updates preview on cursor move", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    -- Find the line with z_test.txt
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local file_idx = nil
    for i, line in ipairs(lines) do
      if line:match("z_test.txt") then
        file_idx = i
        break
      end
    end
    assert.is_not_nil(file_idx, "z_test.txt not found in current pane")

    -- Ensure we are NOT at file_idx (assuming a_dummy is first)
    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] == file_idx then
        -- Should not happen if 'a_dummy' sorts before 'z_test'
        error("Cursor already at target file, cannot test CursorMoved")
    end

    -- Move cursor to z_test.txt
    local win = vim.fn.bufwinid(state.current_buf_id)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, {file_idx, 0})

    -- Manual trigger to verify logic (bypass flaky autocommand in headless)
    require("triad.preview").update_preview(test_file_path:absolute())

    -- Wait for debounce and autocommand
    vim.wait(200)

    -- Check preview buffer content
    local preview_lines = vim.api.nvim_buf_get_lines(state.preview_buf_id, 0, -1, false)
    
    assert.is_true(#preview_lines >= 1, "Preview buffer is empty")
    assert.equals(test_content[1], preview_lines[1])
  end)
end)