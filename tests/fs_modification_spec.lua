local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local ui = require("triad.ui")
local Path = require("plenary.path")

local function trigger_confirm()
    local found_conf_win = false
    local conf_buf = -1
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("triad://confirmation") then
            found_conf_win = true
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

describe("FS Modification & Confirmation", function()
  local temp_dir
  local files = { "alpha.txt", "beta.lua", "gamma/" }

  before_each(function()
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
    vim.wait(50)
    
    -- Expect Confirmation Window
    local found_conf_win = false
    local conf_buf = -1
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("triad://confirmation") then
            found_conf_win = true
            conf_buf = b
            break
        end
    end
    assert.is_true(found_conf_win, "Confirmation window should appear")
    
    -- Check content of confirmation window
    local conf_lines = vim.api.nvim_buf_get_lines(conf_buf, 0, -1, false)
    local content = table.concat(conf_lines, "\n")

    -- Use plain string search for robustness
    assert.is_true(content:find("[+] newfile.js", 1, true) ~= nil, "Should show creation: " .. content)
    assert.is_true(content:find("[-] beta.lua", 1, true) ~= nil, "Should show deletion: " .. content)
    assert.is_true(content:find("[~] alpha.txt -> delta.lua", 1, true) ~= nil, "Should show rename: " .. content)
    
    -- Confirm Changes
    local confirmed = trigger_confirm()
    assert.is_true(confirmed, "Could not trigger confirmation callback")
    vim.wait(100)
    
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
     ui.enable_edit_mode()
     local buf = state.current_buf_id
     
     -- Delete everything
     vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
     
     vim.cmd("write")
     vim.wait(50)
     
     -- Reject (Simulate 'n' via keymap)
     local conf_buf = -1
     for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_get_name(b):match("triad://confirmation") then
            conf_buf = b
            break
        end
     end
     
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
     
     -- Verify FS untouched
     assert.is_true(temp_dir:joinpath("alpha.txt"):exists(), "alpha.txt should still exist")
  end)
end)