local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")

describe("Triad Closing", function()
  
  before_each(function()
    -- Reset
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if #vim.api.nvim_list_wins() > 1 then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  it("closes all windows when 'q' is pressed", function()
    triad.open()
    vim.wait(50)
    
    assert.is_true(#vim.api.nvim_list_wins() >= 3, "Triad should open 3 windows")
    
    -- Press q in current buffer
    vim.api.nvim_feedkeys("q", "mx", false)
    vim.wait(100)
    
    -- Should be back to 1 window (or 0 if it was the only one, but usually test runner keeps one)
    assert.is_true(#vim.api.nvim_list_wins() < 3, "Triad windows should be closed")
  end)

  it("closes all windows when one is closed", function()
    triad.open()
    vim.wait(50)
    
    local wins = vim.api.nvim_list_wins()
    assert.is_true(#wins >= 3)
    
    -- Close the first triad window (should be parent or current)
    -- Let's specifically target the parent window
    local parent_win = vim.fn.bufwinid(state.parent_buf_id)
    if parent_win and vim.api.nvim_win_is_valid(parent_win) then
        vim.api.nvim_win_close(parent_win, true)
    end
    
    vim.wait(100)
    
    -- Check remaining windows. All triad buffers should be invalid or windows closed.
    assert.is_false(vim.api.nvim_buf_is_valid(state.current_buf_id), "Current buffer should be wiped")
    assert.is_false(vim.api.nvim_buf_is_valid(state.preview_buf_id), "Preview buffer should be wiped")
  end)
end)
