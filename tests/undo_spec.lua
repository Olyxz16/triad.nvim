local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Undo", function()
  local temp_dir

  before_each(function()
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       require("triad.ui").close_layout()
    end
    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    temp_dir:joinpath("file.txt"):touch()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("restores deleted line via undo in edit mode", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(200)

    require("triad.ui").enable_edit_mode()
    
    local buf = state.current_buf_id
    local initial_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.is_true(#initial_lines > 0)

    -- Delete line (dd)
    vim.api.nvim_win_set_cursor(state.current_win_id, {1, 0})
    vim.cmd("normal! dd")
    
    local lines_after_delete = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are_not.same(initial_lines, lines_after_delete)

    -- Undo (u)
    vim.cmd("normal! u")
    
    local lines_after_undo = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Check that the file name is present in the first line
    if #lines_after_undo > 0 then
        assert.is_not_nil(lines_after_undo[1]:match("file.txt"), "Undo should restore the filename. Got: " .. (lines_after_undo[1] or "nil"))
    else
        assert.fail("Buffer is empty after undo")
    end
  end)
end)