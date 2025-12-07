local assert = require("luassert")
local spy = require("luassert.spy")

describe("Triad Harpoon Integration", function()
    local triad_harpoon
    
    before_each(function()
        -- Reset package.loaded to force reload
        package.loaded["triad.harpoon"] = nil
        package.loaded["harpoon"] = nil
        package.loaded["harpoon.mark"] = nil
    end)

    it("should detect availability false when no harpoon is present", function()
        triad_harpoon = require("triad.harpoon")
        assert.is_false(triad_harpoon.is_available())
    end)

    describe("Harpoon v2", function()
        local mock_harpoon_v2
        local mock_list
        
        before_each(function()
            mock_list = {
                items = { { value = "foo.lua" }, { value = "bar.lua" } },
                add = function(self, item) table.insert(self.items, { value = item }) end,
                remove = function(self, item) 
                    for i, v in ipairs(self.items) do
                        if v == item then table.remove(self.items, i) break end
                    end
                end
            }
            -- Spy on methods
            spy.on(mock_list, "add")
            spy.on(mock_list, "remove")

            mock_harpoon_v2 = {
                list = function() return mock_list end
            }
            package.loaded["harpoon"] = mock_harpoon_v2
            triad_harpoon = require("triad.harpoon")
        end)

        it("should detect availability true", function()
            assert.is_true(triad_harpoon.is_available())
        end)

        it("should get marks", function()
            local marks = triad_harpoon.get_marks()
            assert.is_true(marks["foo.lua"])
            assert.is_true(marks["bar.lua"])
            assert.is_nil(marks["baz.lua"])
        end)

        it("should toggle (add) mark", function()
            local cwd = vim.uv.cwd()
            local new_file = cwd .. "/baz.lua"
            triad_harpoon.toggle(new_file)
            
            assert.spy(mock_list.add).was_called()
            local marks = triad_harpoon.get_marks()
            assert.is_true(marks["baz.lua"])
        end)

        it("should toggle (remove) mark", function()
            local cwd = vim.uv.cwd()
            local existing_file = cwd .. "/foo.lua"
            triad_harpoon.toggle(existing_file)
            
            assert.spy(mock_list.remove).was_called()
            local marks = triad_harpoon.get_marks()
            assert.is_nil(marks["foo.lua"])
        end)
    end)

    describe("Harpoon v1 (Legacy/Fork API)", function()
        local mock_harpoon_mark
        local marks_storage
        
        before_each(function()
            marks_storage = { { filename = "foo.lua" }, { filename = "bar.lua" } }
            
            mock_harpoon_mark = {
                -- NO get_all
                get_length = function() return #marks_storage end,
                get_marked_file = function(i) return marks_storage[i] end,
                toggle_file = function(file) 
                    local found = false
                    for i, item in ipairs(marks_storage) do
                        if item.filename == file then
                            table.remove(marks_storage, i)
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(marks_storage, { filename = file })
                    end
                end,
                get_index_of = function(file)
                    for i, item in ipairs(marks_storage) do
                        if item.filename == file then return i end
                    end
                    return nil
                end
            }
            
            spy.on(mock_harpoon_mark, "toggle_file")

            package.loaded["harpoon.mark"] = mock_harpoon_mark
            -- Ensure harpoon v2 is NOT loaded
            package.loaded["harpoon"] = nil
            
            triad_harpoon = require("triad.harpoon")
        end)

        it("should detect availability true", function()
            assert.is_true(triad_harpoon.is_available())
        end)

        it("should get marks using get_length/get_marked_file", function()
            local marks = triad_harpoon.get_marks()
            assert.is_true(marks["foo.lua"])
            assert.is_true(marks["bar.lua"])
        end)

        it("should toggle using toggle_file", function()
            local cwd = vim.uv.cwd()
            local new_file = cwd .. "/baz.lua"
            triad_harpoon.toggle(new_file)
            
            assert.spy(mock_harpoon_mark.toggle_file).was_called_with("baz.lua")
            
            local marks = triad_harpoon.get_marks()
            assert.is_true(marks["baz.lua"])
        end)
    end)
end)