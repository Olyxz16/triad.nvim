local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

local function trigger_confirm()
    local conf_buf = -1
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("triad://confirmation") then
            conf_buf = b
            break
        end
    end
    
    if conf_buf ~= -1 then
        local keymaps = vim.api.nvim_buf_get_keymap(conf_buf, "n")
        for _, map in ipairs(keymaps) do
            if map.lhs == "y" then
                map.callback()
                return true
            end
        end
    end
    return false
end

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

    -- Check for confirmation window
    local found = false
    local content = ""
    local conf_buf = -1
    for _, win in ipairs(vim.api.nvim_list_wins()) do
       local b = vim.api.nvim_win_get_buf(win)
       if vim.api.nvim_buf_get_name(b):match("triad://confirmation") then
           found = true
           content = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
           conf_buf = b
           break
       end
    end

    assert.is_true(found, "Confirmation prompt should appear")
    assert.truthy(content:match("%[%-%].*delete_me%.txt"), "Prompt should mention deleting file")
    
    -- Simulate choosing "No" (cancel) via keymap
    if conf_buf ~= -1 then
        local keymaps = vim.api.nvim_buf_get_keymap(conf_buf, "n")
        for _, map in ipairs(keymaps) do
            if map.lhs == "n" then
                map.callback()
                break
            end
        end
    end
    vim.wait(50)
    
    -- File should still exist on disk
    local file_path = temp_dir:joinpath("delete_me.txt")
    assert.is_true(file_path:exists(), "File should not be deleted if cancelled")
    
    -- Buffer should still be modified
    assert.is_true(vim.api.nvim_buf_get_option(state.current_buf_id, "modified"), "Buffer should remain modified")
  end)
  
  it("applies changes if confirmed", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    require("triad.ui").enable_edit_mode()
    
    -- Delete the line
    vim.api.nvim_win_set_cursor(state.current_win_id, {1, 0})
    vim.cmd("normal! dd")
    
    -- Trigger Save
    vim.cmd("write")
    vim.wait(50)
    
    -- Confirm
    trigger_confirm()
    vim.wait(100) 

    -- Assertions
    local file_path = temp_dir:joinpath("delete_me.txt")
    assert.is_false(file_path:exists(), "File should be deleted if confirmed")
  end)
end)
