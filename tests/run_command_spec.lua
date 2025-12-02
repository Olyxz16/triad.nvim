local assert = require("luassert")

describe("Triad Command", function()
    -- Reset state before each test
    before_each(function()
        -- Close all windows except the last one to reset
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if #vim.api.nvim_list_wins() > 1 then
                pcall(vim.api.nvim_win_close, win, true)
            end
        end
    end)

    it("creates the user command :Triad during setup", function()
        require("triad").setup()
        -- assert that the command exists in the global list
        local commands = vim.api.nvim_get_commands({})
        assert.is_not_nil(commands["Triad"])
    end)

    it("opens the interface and sets filetype", function()
        require("triad").setup()
        
        -- Run the command
        vim.cmd("Triad")

        -- Check 1: Did we switch to a buffer with our custom filetype?
        assert.are.same("triad", vim.bo.filetype)

        -- Check 2: Do we have multiple windows open? 
        -- (Since Triad should be a 3-pane layout, we expect more than 1 window)
        local win_count = #vim.api.nvim_list_wins()
        assert.is_true(win_count > 1, "Expected Triad to open split windows")
    end)
end)
