local git = require("triad.git")
local state = require("triad.state")
local Job = require("plenary.job")
local ui = require("triad.ui") -- Load UI to ensure it doesn't crash on render calls

describe("Git Integration", function()
  local cwd

  before_each(function()
    cwd = vim.fn.tempname()
    vim.fn.mkdir(cwd, "p")
    state.current_dir = cwd
    state.git_status_data = {}
    state.current_buf_id = vim.api.nvim_create_buf(false, true) -- Mock buffer for render calls
    -- Initialize config to prevent crashes in ui.lua
    require("triad").setup() 
    state.config = require("triad.config") -- Fallback if setup doesn't set it immediately or correctly in test env
    
    -- Init git repo
    Job:new({ command = "git", args = { "init" }, cwd = cwd }):sync()
    -- Force branch name to master to be safe
    Job:new({ command = "git", args = { "symbolic-ref", "HEAD", "refs/heads/master" }, cwd = cwd }):sync()
    
    Job:new({ command = "git", args = { "config", "user.email", "you@example.com" }, cwd = cwd }):sync()
    Job:new({ command = "git", args = { "config", "user.name", "Your Name" }, cwd = cwd }):sync()
  end)

  after_each(function()
    vim.fn.delete(cwd, "rf")
    if vim.api.nvim_buf_is_valid(state.current_buf_id) then
      vim.api.nvim_buf_delete(state.current_buf_id, { force = true })
    end
  end)

  it("detects untracked files (??)", function()
    local file = cwd .. "/untracked.txt"
    vim.fn.writefile({"hello"}, file)
    
    git.fetch_git_status()
    
    vim.wait(2000, function() return state.git_status_data["untracked.txt"] ~= nil end)
    
    assert.are.same("??", state.git_status_data["untracked.txt"])
  end)

  it("detects added files (A )", function()
    local file = cwd .. "/added.txt"
    vim.fn.writefile({"hello"}, file)
    Job:new({ command = "git", args = { "add", "." }, cwd = cwd }):sync()
    
    git.fetch_git_status()
    
    vim.wait(2000, function() return state.git_status_data["added.txt"] ~= nil end)
    
    assert.are.same("A ", state.git_status_data["added.txt"])
  end)

  it("detects modified files ( M)", function()
    local file = cwd .. "/modified.txt"
    vim.fn.writefile({"v1"}, file)
    Job:new({ command = "git", args = { "add", "." }, cwd = cwd }):sync()
    Job:new({ command = "git", args = { "commit", "-m", "init" }, cwd = cwd }):sync()
    
    vim.fn.writefile({"v2"}, file)
    
    git.fetch_git_status()
    
    vim.wait(2000, function() return state.git_status_data["modified.txt"] ~= nil end)
    
    assert.are.same(" M", state.git_status_data["modified.txt"])
  end)

    it("detects conflict files (UU)", function()
    -- To create a conflict:
    -- 1. Create file on main
    -- 2. Branch to feature
    -- 3. Modify file on feature & commit
    -- 4. Checkout main, modify file & commit
    -- 5. Merge feature -> Conflict
    
    local file = cwd .. "/conflict.txt"
    vim.fn.writefile({"base"}, file)
    Job:new({ command = "git", args = { "add", "." }, cwd = cwd }):sync()
    Job:new({ command = "git", args = { "commit", "-m", "init" }, cwd = cwd }):sync()
    
    Job:new({ command = "git", args = { "checkout", "-b", "feature" }, cwd = cwd }):sync()
    vim.fn.writefile({"feature"}, file)
    Job:new({ command = "git", args = { "commit", "-am", "feature" }, cwd = cwd }):sync()
    
    Job:new({ command = "git", args = { "checkout", "master" }, cwd = cwd }):sync()
    vim.fn.writefile({"master"}, file)
    Job:new({ command = "git", args = { "commit", "-am", "master" }, cwd = cwd }):sync()
    
    -- Merge returns exit code 1 on conflict, so don't panic
    pcall(function()
        Job:new({ command = "git", args = { "merge", "feature" }, cwd = cwd }):sync()
    end)

    git.fetch_git_status()
    
    vim.wait(2000, function() return state.git_status_data["conflict.txt"] ~= nil end)
    
    assert.are.same("UU", state.git_status_data["conflict.txt"])
  end)

  it("renders icons in the buffer", function()
    local file = cwd .. "/modified.txt"
    vim.fn.writefile({"v1"}, file)
    Job:new({ command = "git", args = { "add", "." }, cwd = cwd }):sync()
    Job:new({ command = "git", args = { "commit", "-m", "init" }, cwd = cwd }):sync()
    vim.fn.writefile({"v2"}, file)
    
    git.fetch_git_status()
    
    vim.wait(2000, function() return state.git_status_data["modified.txt"] ~= nil end)
    
    -- Wait a bit more for render to happen (it's scheduled)
    vim.wait(100) 
    
    local lines = vim.api.nvim_buf_get_lines(state.current_buf_id, 0, -1, false)
    local found = false
    local modified_icon = state.config.git_icons.modified
    for _, line in ipairs(lines) do
       -- Check if line contains icon and filename
       -- Note: The line also contains devicon.
       if line:find(modified_icon, 1, true) and line:find("modified.txt", 1, true) then
         found = true
         break
       end
    end
    assert.is_true(found, "Did not find modified icon in buffer lines: " .. vim.inspect(lines))
  end)
end)
