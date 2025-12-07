---@class TriadCache
local M = {}

---@class PreviewCacheEntry
---@field lines string[]
---@field type "directory"|"text"|"binary"|"unknown"|"error"

---@type table<string, PreviewCacheEntry>
local preview_cache = {}

---@type table<string, string[]>
local dir_listing_cache = {}

--- Gets a preview from the cache.
---@param path string
---@return PreviewCacheEntry|nil
function M.get_preview(path)
  return preview_cache[path]
end

--- Sets a preview in the cache.
---@param path string
---@param entry PreviewCacheEntry
function M.set_preview(path, entry)
  preview_cache[path] = entry
end

--- Gets a directory listing from the cache.
---@param path string
---@return string[]|nil
function M.get_dir(path)
  return dir_listing_cache[path]
end

--- Sets a directory listing in the cache.
---@param path string
---@param files string[]
function M.set_dir(path, files)
  dir_listing_cache[path] = files
end

--- Clears the cache.
function M.clear()
  preview_cache = {}
  dir_listing_cache = {}
end

return M
