local assert = require("luassert")
local cache = require("triad.cache")

describe("Triad Cache Module", function()
  before_each(function()
    cache.clear()
  end)

  it("should store and retrieve preview entries", function()
    local path = "/tmp/test_file.txt"
    local entry = { lines = { "Hello", "World" }, type = "text" }
    
    cache.set_preview(path, entry)
    local retrieved = cache.get_preview(path)
    
    assert.are.same(entry, retrieved)
  end)

  it("should return nil for non-existent entries", function()
    local path = "/tmp/non_existent.txt"
    local retrieved = cache.get_preview(path)
    assert.is_nil(retrieved)
  end)

  it("should clear the cache", function()
    local path = "/tmp/test_file.txt"
    local entry = { lines = { "Data" }, type = "text" }
    
    cache.set_preview(path, entry)
    cache.clear()
    
    local retrieved = cache.get_preview(path)
    assert.is_nil(retrieved)
  end)

  it("should store and retrieve directory listings", function()
    local path = "/tmp/test_dir"
    local files = { "file1", "file2" }
    
    cache.set_dir(path, files)
    local retrieved = cache.get_dir(path)
    
    assert.are.same(files, retrieved)
  end)
end)
