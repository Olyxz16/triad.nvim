local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local Path = require("plenary.path")
local fs = require("triad.fs")

describe("Triad Sorting", function()
  local temp_dir

  before_each(function()
    -- Cleanup windows
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       require("triad.ui").close_layout()
    end

    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    
    -- Create files and directories mixed up
    temp_dir:joinpath("z_file.txt"):touch()
    temp_dir:joinpath("a_file.txt"):touch()
    temp_dir:joinpath("m_dir"):mkdir()
    temp_dir:joinpath("b_dir"):mkdir()
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("sorts directories first, then files, alphabetically", function()
    -- Use internal FS function to check sort directly first
    local files = fs.read_dir(temp_dir:absolute())
    
    -- Expected order:
    -- b_dir
    -- m_dir
    -- a_file.txt
    -- z_file.txt
    
    assert.equals("b_dir", files[1])
    assert.equals("m_dir", files[2])
    assert.equals("a_file.txt", files[3])
    assert.equals("z_file.txt", files[4])
  end)
end)
