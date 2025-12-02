local assert = require("luassert")
local fs = require("triad.fs")
local Path = require("plenary.path")

describe("Triad FS", function()
  local temp_dir
  local test_files = { "a.txt", "b.lua", ".hidden" }

  before_each(function()
    -- Create a temp directory
    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()

    -- Create test files
    for _, file in ipairs(test_files) do
      local p = temp_dir:joinpath(file)
      p:touch()
    end
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("reads directory contents correctly", function()
    -- Test with show_hidden = true (mock config if needed, or check default)
    -- By default fs.read_dir checks state.config.show_hidden.
    -- We need to mock state.config
    local state = require("triad.state")
    state.config = { show_hidden = true }

    local files = fs.read_dir(temp_dir:absolute())
    assert.is_not_nil(files)
    assert.equals(3, #files)
    assert.is_true(vim.tbl_contains(files, "a.txt"))
    assert.is_true(vim.tbl_contains(files, "b.lua"))
    assert.is_true(vim.tbl_contains(files, ".hidden"))
  end)

  it("respects show_hidden config", function()
    local state = require("triad.state")
    state.config = { show_hidden = false }

    local files = fs.read_dir(temp_dir:absolute())
    assert.is_not_nil(files)
    assert.equals(2, #files) -- Should filter out .hidden
    assert.is_true(vim.tbl_contains(files, "a.txt"))
    assert.is_false(vim.tbl_contains(files, ".hidden"))
  end)

  it("renames files", function()
    local old_path = temp_dir:joinpath("a.txt"):absolute()
    local new_path = temp_dir:joinpath("moved.txt"):absolute()

    local success, err = fs.rename(old_path, new_path)
    assert.is_true(success, err)
    
    assert.is_false(Path:new(old_path):exists())
    assert.is_true(Path:new(new_path):exists())
  end)

  it("deletes files", function()
    local path = temp_dir:joinpath("b.lua"):absolute()
    
    local success, err = fs.unlink(path)
    assert.is_true(success, err)
    
    assert.is_false(Path:new(path):exists())
  end)
end)
