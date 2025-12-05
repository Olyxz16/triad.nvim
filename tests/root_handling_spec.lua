local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local ui = require("triad.ui")
local Path = require("plenary.path")

describe("Triad Root Handling", function()
  before_each(function()
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       ui.close_layout()
    end
    -- We need layout to be created to have buffers
    triad.open() 
  end)

  it("displays only / in parent pane when at root", function()
    -- Set current dir to root
    state.set_current_dir("/")
    
    -- Force render
    ui.render_parent_pane()
    
    local buf = state.parent_buf_id
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    -- Should contain exactly one line
    assert.equals(1, #lines)
    
    -- content should be icon + / 
    -- We check for "/" at the end
    assert.is_true(lines[1]:match("/$") ~= nil, "Should display root directory")
    
    -- Should NOT be a list of files (bin, boot, etc)
    assert.is_nil(lines[1]:match("bin"), "Should not list root contents")
  end)
end)
