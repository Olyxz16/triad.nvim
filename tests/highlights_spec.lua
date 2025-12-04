local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local ui = require("triad.ui")
local Path = require("plenary.path")

describe("Triad Highlights", function()
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
    
    -- Create items
    temp_dir:joinpath("file.lua"):touch()
    temp_dir:joinpath("mydir"):mkdir()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("applies highlight groups to directory names", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    local buf = state.current_buf_id
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    local dir_line_idx = nil
    for i, line in ipairs(lines) do
      if line:match("mydir/$") then
        dir_line_idx = i - 1
        break
      end
    end
    
    assert.is_not_nil(dir_line_idx, "Directory line not found")

    -- Check extmarks in icon_ns_id
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ui.icon_ns_id, {dir_line_idx, 0}, {dir_line_idx, -1}, {details = true})
    
    local found_dir_hl = false
    for _, mark in ipairs(extmarks) do
      -- mark structure: { id, row, col, details }
      local details = mark[4]
      if details.hl_group == "TriadDirectory" then
        found_dir_hl = true
        break
      end
    end
    
    assert.is_true(found_dir_hl, "TriadDirectory highlight not found on directory line")
  end)

  it("applies highlight groups to file icons", function()
    vim.api.nvim_set_current_dir(temp_dir:absolute())
    triad.open()
    vim.wait(50)

    local buf = state.current_buf_id
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    local file_line_idx = nil
    for i, line in ipairs(lines) do
      if line:match("file.lua") then
        file_line_idx = i - 1
        break
      end
    end
    
    assert.is_not_nil(file_line_idx, "File line not found")

    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ui.icon_ns_id, {file_line_idx, 0}, {file_line_idx, -1}, {details = true})
    
    local found_icon_hl = false
    for _, mark in ipairs(extmarks) do
      local details = mark[4]
      -- We don't know the exact group name (depends on devicons), but it should be there and not TriadDirectory
      if details.hl_group and details.hl_group ~= "TriadDirectory" and details.end_col then
         -- It's likely the icon highlight if it ends early in the line
         if details.end_col < 5 then 
            found_icon_hl = true 
         end
      end
    end
    
    assert.is_true(found_icon_hl, "Icon highlight not found on file line")
  end)
end)
