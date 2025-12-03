local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Edit Mode", function()
  local temp_dir

  before_each(function()
    -- Cleanup windows
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

  it("enables modifiable when entering edit mode", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    -- Initial state: Nav mode -> modifiable = false
    assert.is_false(vim.api.nvim_buf_get_option(state.current_buf_id, "modifiable"), "Buffer should be read-only in nav mode")
    
    -- Trigger edit mode via keymap simulation or direct call
    require("triad.ui").enable_edit_mode()
    
    -- Check state: Edit mode -> modifiable = true
    assert.is_true(vim.api.nvim_buf_get_option(state.current_buf_id, "modifiable"), "Buffer should be modifiable in edit mode")
  end)
end)
