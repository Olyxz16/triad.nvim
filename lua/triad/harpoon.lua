local M = {}
local Path = require("plenary.path")

-- Try to load Harpoon v2 first, then v1
local has_harpoon_mod, harpoon_mod = pcall(require, "harpoon")
local has_harpoon_mark, harpoon_mark = pcall(require, "harpoon.mark")

-- Determine version
-- Harpoon v2 has a .list() method on the main module (or instance)
local is_v2 = has_harpoon_mod and type(harpoon_mod) == "table" and type(harpoon_mod.list) == "function"
-- Harpoon v1 uses harpoon.mark
local is_v1 = has_harpoon_mark

--- Checks if Harpoon (v1 or v2) is available.
--- @return boolean
function M.is_available()
  return is_v2 or is_v1
end

--- Gets a set of marked files.
--- @return table<string, boolean> marks Set of marked file paths (relative).
function M.get_marks()
  local marks = {}
  if is_v2 then
    local list = harpoon_mod:list()
    if list and list.items then
        for _, item in ipairs(list.items) do
          if item and item.value then
             marks[item.value] = true
          end
        end
    end
  elseif is_v1 then
    -- Strategy 1: get_all() (Some versions)
    if harpoon_mark.get_all then
        local ok, items = pcall(harpoon_mark.get_all)
        if ok and items then
            for _, item in ipairs(items) do
              if item and item.filename then
                marks[item.filename] = true
              end
            end
        end
    -- Strategy 2: get_length() + get_marked_file() (Other versions)
    elseif harpoon_mark.get_length and harpoon_mark.get_marked_file then
        local len = harpoon_mark.get_length()
        for i = 1, len do
            local item = harpoon_mark.get_marked_file(i)
            -- item can be a table { filename = "..." } or potentially just the string in some forks?
            -- usually table.
            if type(item) == "table" and item.filename then
                marks[item.filename] = true
            elseif type(item) == "string" then
                marks[item] = true
            end
        end
    end
  end
  return marks
end

--- Toggles the Harpoon mark for a given file.
--- @param path string Absolute path to the file.
function M.toggle(path)
  -- Harpoon stores paths relative to CWD usually.
  local cwd = vim.uv.cwd()
  local relative_path = Path:new(path):make_relative(cwd)

  if is_v2 then
    local list = harpoon_mod:list()
    local found_item = nil
    
    if list and list.items then
        for _, item in ipairs(list.items) do
          if item.value == relative_path then
            found_item = item
            break
          end
        end
        
        if found_item then
          list:remove(found_item)
        else
          list:add(relative_path)
        end
    end
  elseif is_v1 then
    -- Strategy 1: toggle_file() (Preferred if available)
    if harpoon_mark.toggle_file then
        harpoon_mark.toggle_file(relative_path)
        return
    end

    -- Strategy 2: Manual Check + Add/Remove
    local is_marked = false
    
    -- Check if marked
    if harpoon_mark.get_index_of then
       -- get_index_of usually returns nil if not found
       if harpoon_mark.get_index_of(relative_path) then
           is_marked = true
       end
    elseif harpoon_mark.get_all then
       local items = harpoon_mark.get_all()
       for _, item in ipairs(items) do
          if item.filename == relative_path then
             is_marked = true
             break
          end
       end
    end
    
    if is_marked then
      if harpoon_mark.rm_file then
          harpoon_mark.rm_file(relative_path)
      end
    else
      if harpoon_mark.add_file then
          harpoon_mark.add_file(relative_path)
      end
    end
  end
end

--- Checks if a file is marked.
--- @param path string Absolute path.
--- @return boolean
function M.is_marked(path)
  local relative_path = Path:new(path):make_relative(vim.uv.cwd())
  local marks = M.get_marks()
  return marks[relative_path] == true
end

return M
