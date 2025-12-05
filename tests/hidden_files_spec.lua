local fs = require("triad.fs")
local git = require("triad.git")
local state = require("triad.state")
local Job = require("plenary.job")
local assert = require("luassert")

describe("Hidden Files Logic", function()
  local cwd
  local buf_id

  before_each(function()
    -- Setup Temp Dir
    cwd = vim.fn.tempname()
    vim.fn.mkdir(cwd, "p")
    
    -- Setup State
    require("triad").setup()
    state.current_dir = cwd
    state.is_git_repo = false
    state.git_status_data = {}
    state.config.show_hidden = false

    -- Mock Buffer (needed if ui functions are called, but we are testing fs mostly)
    buf_id = vim.api.nvim_create_buf(false, true)
    state.current_buf_id = buf_id
  end)

  after_each(function()
    vim.fn.delete(cwd, "rf")
    if vim.api.nvim_buf_is_valid(buf_id) then
       vim.api.nvim_buf_delete(buf_id, { force = true })
    end
  end)

  it("hides dotfiles by default in non-git mode", function()
    vim.fn.writefile({}, cwd .. "/normal.txt")
    vim.fn.writefile({}, cwd .. "/.hidden")
    
    state.is_git_repo = false
    
    local files = fs.read_dir(cwd)
    
    assert.is_true(vim.tbl_contains(files, "normal.txt"))
    assert.is_false(vim.tbl_contains(files, ".hidden"))
  end)
  
  it("toggles hidden files in non-git mode", function()
    vim.fn.writefile({}, cwd .. "/.hidden")
    state.is_git_repo = false
    
    state.config.show_hidden = true
    local files = fs.read_dir(cwd)
    assert.is_true(vim.tbl_contains(files, ".hidden"))
    
    state.config.show_hidden = false
    files = fs.read_dir(cwd)
    assert.is_false(vim.tbl_contains(files, ".hidden"))
  end)

  it("Git Mode: shows dotfiles but hides ignored files", function()
    -- Setup Git Repo
    Job:new({ command = "git", args = { "init" }, cwd = cwd }):sync()
    state.is_git_repo = true -- Manually set or wait for git.fetch_git_status
    
    -- Create Files
    vim.fn.writefile({}, cwd .. "/normal.txt")
    vim.fn.writefile({}, cwd .. "/.dotfile")
    vim.fn.writefile({}, cwd .. "/ignored.txt")
    vim.fn.writefile({"ignored.txt"}, cwd .. "/.gitignore")
    
    -- Update Git Status (Async)
    git.fetch_git_status()
    
    -- Wait for git status to populate
    vim.wait(2000, function() 
        -- Check if status data is populated. 
        -- Note: .dotfile is UNTRACKED (??), ignored.txt is IGNORED (!!)
        -- git status returns absolute paths
        local check_path = cwd .. "/ignored.txt"
        return state.git_status_data[check_path] ~= nil
    end)
    
    -- Ensure our manual verify found it
    local ignored_path = cwd .. "/ignored.txt"
    assert.match("!!", state.git_status_data[ignored_path] or "")

    -- Check Visibility
    local files = fs.read_dir(cwd)
    
    assert.is_true(vim.tbl_contains(files, "normal.txt"))
    assert.is_true(vim.tbl_contains(files, ".dotfile"), "Dotfiles should be visible in git mode")
    assert.is_true(vim.tbl_contains(files, ".gitignore"), "Gitignore should be visible")
    assert.is_false(vim.tbl_contains(files, "ignored.txt"), "Ignored file should be hidden")
  end)

  it("Git Mode: show_hidden=true shows ignored files", function()
    -- Setup Git Repo
    Job:new({ command = "git", args = { "init" }, cwd = cwd }):sync()
    state.is_git_repo = true
    
    vim.fn.writefile({}, cwd .. "/ignored.txt")
    vim.fn.writefile({"ignored.txt"}, cwd .. "/.gitignore")
    
    git.fetch_git_status()
    vim.wait(2000, function() return state.git_status_data[cwd .. "/ignored.txt"] ~= nil end)
    
    state.config.show_hidden = true
    local files = fs.read_dir(cwd)
    
    assert.is_true(vim.tbl_contains(files, "ignored.txt"))
  end)

  it("Git Mode: hides ignored DIRECTORIES", function()
    Job:new({ command = "git", args = { "init" }, cwd = cwd }):sync()
    state.is_git_repo = true
    
    local ignored_dir = cwd .. "/ignored_dir"
    vim.fn.mkdir(ignored_dir, "p")
    vim.fn.writefile({}, ignored_dir .. "/file.txt")
    vim.fn.writefile({"ignored_dir/"}, cwd .. "/.gitignore")
    
    git.fetch_git_status()
    
    -- Wait for status. 
    -- Git reports directory as ignored: "!! ignored_dir/"
    local ignored_key = ignored_dir
    vim.wait(2000, function() return state.git_status_data[ignored_key] ~= nil end)
    
    -- Verify git status data actually caught it
    assert.match("!!", state.git_status_data[ignored_key] or "")

    -- Check Visibility
    local files = fs.read_dir(cwd)
    assert.is_false(vim.tbl_contains(files, "ignored_dir"), "Ignored directory should be hidden")
  end)
end)