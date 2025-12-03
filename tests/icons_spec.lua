local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")

describe("Triad Icons", function()
  local temp_dir

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
    
    -- Create files with known icons
    temp_dir:joinpath("file.lua"):touch()
    temp_dir:joinpath("README.md"):touch()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("renders devicons correctly", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    
    -- Check for Lua icon (usually  or similar, depends on font but at least check it's not empty or fallback)
    local lua_line = nil
    for _, line in ipairs(lines) do
      if line:match("file.lua") then
        lua_line = line
        break
      end
    end
    
    assert.is_not_nil(lua_line)
    -- Ensure it's not just " file.lua" or "- file.lua" (fallback)
    -- The default icon for lua is usually not "-"
    local icon = lua_line:match("^([^%s]+)")
    assert.is_not_nil(icon)
    assert.are_not.equal("-", icon)
  end)

  it("renders directory icons correctly (distinct from file icons)", function()
    -- Create a directory named 'lua' which might conflict with lua file icon
    temp_dir:joinpath("lua"):mkdir()
    
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    
    local lua_dir_line = nil
    local lua_file_line = nil
    
    for _, line in ipairs(lines) do
      if line:match("lua/$") then -- matches "lua/" directory
        lua_dir_line = line
      elseif line:match("file.lua") then
        lua_file_line = line
      end
    end
    
    assert.is_not_nil(lua_dir_line, "lua directory line not found")
    assert.is_not_nil(lua_file_line, "file.lua line not found")
    
    local dir_icon = lua_dir_line:match("^([^%s]+)")
    local file_icon = lua_file_line:match("^([^%s]+)")
    
    assert.are_not.equal(dir_icon, file_icon, "Directory 'lua/' should have a different icon than 'file.lua'")
    
    -- Optional: Check for specific folder icon if we decide on one.
    -- For now, just equality check proves they are treated differently.
  end)
end)
