local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Safety", function()
  local temp_dir

  before_each(function()
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       require("triad.ui").close_layout()
    end
    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    temp_dir:joinpath("delete_me.txt"):touch()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("prompts for confirmation before deleting", function()
    -- Mock vim.ui.select to intercept the prompt
    local original_select = vim.ui.select
    local prompt_args = nil
    local selected_choice = nil
    
    vim.ui.select = function(items, opts, on_choice)
      prompt_args = opts.prompt
      -- Simulate choosing "No" (cancel)
      on_choice("No")
    end

    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    require("triad.ui").enable_edit_mode()
    
    -- Delete the line
    vim.api.nvim_win_set_cursor(state.current_win_id, {1, 0})
    vim.cmd("normal! dd")
    
    -- Trigger Save
    vim.cmd("write")
    vim.wait(50) -- Wait for async logic

    -- Assertions
    assert.is_not_nil(prompt_args, "Confirmation prompt should appear")
    assert.is_true(prompt_args:match("Delete: 1"), "Prompt should mention deleting 1 file")
    
    -- Since we chose "No", file should still exist on disk
    local file_path = temp_dir:joinpath("delete_me.txt")
    assert.is_true(file_path:exists(), "File should not be deleted if cancelled")
    
    -- Buffer should still be modified?
    -- Actually handle_buf_write doesn't set nomodified if cancelled.
    assert.is_true(vim.api.nvim_buf_get_option(state.current_buf_id, "modified"), "Buffer should remain modified")

    -- Restore mock
    vim.ui.select = original_select
  end)
  
  it("applies changes if confirmed", function()
    -- Mock vim.ui.select to accept
    local original_select = vim.ui.select
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice("Yes")
    end

    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    require("triad.ui").enable_edit_mode()
    
    -- Delete the line
    vim.api.nvim_win_set_cursor(state.current_win_id, {1, 0})
    vim.cmd("normal! dd")
    
    -- Trigger Save
    vim.cmd("write")
    vim.wait(100) 

    -- Assertions
    local file_path = temp_dir:joinpath("delete_me.txt")
    assert.is_false(file_path:exists(), "File should be deleted if confirmed")
    
    vim.ui.select = original_select
  end)
end)
