local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local ui = require("triad.ui")
local Path = require("plenary.path")

-- Robust helper to wait for confirmation window and trigger 'y'
local function wait_and_confirm()
    -- Poll for the window to appear
    local found = vim.wait(1000, function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local b = vim.api.nvim_win_get_buf(win)
            local name = vim.api.nvim_buf_get_name(b)
            if name:match("triad://confirmation") then
                return true
            end
        end
        return false
    end, 10)

    if not found then return false end

    -- Find buffer and trigger callback
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("triad://confirmation") then
             local keymaps = vim.api.nvim_buf_get_keymap(b, "n")
             for _, map in ipairs(keymaps) do
                 if map.lhs == "y" then
                     map.callback()
                     return true
                 end
             end
        end
    end
    return false
end

local function wait_and_reject()
    local found = vim.wait(1000, function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local b = vim.api.nvim_win_get_buf(win)
            local name = vim.api.nvim_buf_get_name(b)
            if name:match("triad://confirmation") then
                return true
            end
        end
        return false
    end, 10)

    if not found then return false end

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("triad://confirmation") then
             local keymaps = vim.api.nvim_buf_get_keymap(b, "n")
             for _, map in ipairs(keymaps) do
                 if map.lhs == "n" then
                     map.callback()
                     return true
                 end
             end
        end
    end
    return false
end

describe("FS Modification & Confirmation", function()
  local temp_dir
  local files = { "alpha.txt", "beta.lua", "gamma/" }
  local original_notify

  before_each(function()
    -- Mock vim.notify to avoid Hit-Enter prompts
    original_notify = vim.notify
    vim.notify = function(...) end

    -- Cleanup windows
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       ui.close_layout()
    end

    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    for _, f in ipairs(files) do
      local p = temp_dir:joinpath(f)
      if f:sub(-1) == "/" then
        p:mkdir()
      else
        p:touch()
      end
    end
    
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50) -- Wait for render
  end)

  after_each(function()
    vim.notify = original_notify
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("detects additions, deletions, and renames", function()
    -- Enable Edit Mode
    ui.enable_edit_mode()
    local buf = state.current_buf_id
    
    -- 1. Rename 'alpha.txt' to 'delta.lua'
    vim.cmd("%s/alpha.txt/delta.lua/e")
    
    -- 2. Delete 'beta.lua'
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
        if line:match("beta%.lua") then
            vim.api.nvim_buf_set_lines(buf, i-1, i, false, {})
            break
        end
    end
    
    -- 3. Add 'newfile.js'
    vim.cmd("$put ='- newfile.js'")
    
    -- Trigger Save
    vim.cmd("write")
    
    -- Wait for window to appear (implicit in wait_and_confirm)
    
    -- Verify content first? Hard to do async. 
    -- We rely on wait_and_confirm to check for window existence.
    
    -- Check Buttons (Optional, assumed from logic)
    
    -- Confirm Changes
    local confirmed = wait_and_confirm()
    assert.is_true(confirmed, "Confirmation window did not appear or 'y' keymap failed")
    
    -- Wait for FS ops
    vim.wait(200)
    
    -- Verify FS
    assert.is_false(temp_dir:joinpath("beta.lua"):exists(), "beta.lua should be deleted")
    assert.is_false(temp_dir:joinpath("alpha.txt"):exists(), "alpha.txt should be gone")
    assert.is_true(temp_dir:joinpath("delta.lua"):exists(), "delta.lua should exist")
    assert.is_true(temp_dir:joinpath("newfile.js"):exists(), "newfile.js should exist")
    
    -- Verify Triad View updated
    local current_lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local view_content = table.concat(current_lines, "\n")
    assert.is_true(view_content:find("delta.lua", 1, true) ~= nil, "View should show delta.lua")
    assert.is_true(view_content:find("beta.lua", 1, true) == nil, "View should not show beta.lua")
  end)

  it("cancels changes when rejected", function()
     print("DEBUG TEST: Start 'cancels changes when rejected' test")
     ui.enable_edit_mode()
     local buf_id_at_start = state.current_buf_id
     print("DEBUG TEST: Buffer ID at start of test:", buf_id_at_start)
     
     -- Delete everything
     vim.api.nvim_buf_set_lines(buf_id_at_start, 0, -1, false, {})
     print("DEBUG TEST: Buffer content after clearing (should be empty):")
     local cleared_content = vim.api.nvim_buf_get_lines(buf_id_at_start, 0, -1, false)
     for _, l in ipairs(cleared_content) do print("DEBUG TEST:   " .. l) end
     print("DEBUG TEST: Content count:", #cleared_content)

     vim.cmd("write")
     
     local rejected = wait_and_reject()
     assert.is_true(rejected, "Confirmation window did not appear or 'n' keymap failed")
     
     local content_updated = vim.wait(500, function() -- Wait up to 500ms for content
        local lines = vim.api.nvim_buf_get_lines(buf_id_at_start, 0, -1, false)
        return #lines > 0 -- Content should be restored
     end, 10)
     assert.is_true(content_updated, "Buffer content did not update after rejection")
     
     print("DEBUG TEST: Final buf_id for assertion:", state.current_buf_id)
     local current_lines = vim.api.nvim_buf_get_lines(buf_id_at_start, 0, -1, false)
     local view_content = table.concat(current_lines, "\n")
     print("DEBUG TEST: Final buffer content (view_content):")
     for _, l in ipairs(current_lines) do print("DEBUG TEST:   " .. l) end
     print("DEBUG TEST: Final content count:", #current_lines)
     
     -- Verify buffer content is restored to original
     local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
     local view_content = table.concat(current_lines, "\n")
     assert.is_true(view_content:find("alpha.txt", 1, true) ~= nil, "View should show alpha.txt")
     assert.is_true(view_content:find("beta.lua", 1, true) ~= nil, "View should show beta.lua")
     assert.is_true(view_content:find("gamma/", 1, true) ~= nil, "View should show gamma/")
     assert.is_false(vim.api.nvim_buf_get_option(buf, "modified"), "Buffer should not be modified after rejection")
  end)
end)
