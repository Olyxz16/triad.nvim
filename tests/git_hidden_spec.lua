local assert = require("luassert")
local triad = require("triad")
local state = require("triad.state")
local git = require("triad.git")
local Path = require("plenary.path")

describe("Triad Hidden Files", function()
  local temp_dir
  local git_dir
  local parent_dir

  before_each(function()
    if state.current_win_id and vim.api.nvim_win_is_valid(state.current_win_id) then
       require("triad.ui").close_layout()
    end
    -- Structure:
    -- /temp
    --   .hidden_parent
    --   /repo (git root)
    --     .hidden_repo
    
    temp_dir = Path:new(vim.fn.tempname())
    temp_dir:mkdir()
    
    temp_dir:joinpath(".hidden_parent"):touch()
    
    git_dir = temp_dir:joinpath("repo")
    git_dir:mkdir()
    git_dir:joinpath(".hidden_repo"):touch()
    
    -- Init git
    vim.fn.system("git -C " .. git_dir:absolute() .. " init")
    
    -- Set config default (show_hidden = false)
    state.config = require("triad.config")
    state.config.show_hidden = false
  end)

  after_each(function()
    if temp_dir:exists() then
      temp_dir:rm({ recursive = true })
    end
  end)

  it("hides parent directory dotfiles even if inside git repo", function()
    -- Go to git repo
    vim.api.nvim_set_current_dir(git_dir:absolute())
    triad.open()
    
    -- Wait for git status async
    vim.wait(200)
    
    assert.is_true(state.is_git_repo, "Should be detected as git repo")
    assert.is_not_nil(state.git_root, "Git root should be set")
    
    -- Check Parent Pane Content (scanned from temp_dir)
    -- We need to access the buffer content of parent pane
    local parent_buf = state.parent_buf_id
    local lines = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
    local content = table.concat(lines, "\n")
    
    -- .hidden_parent should be HIDDEN because it is outside the repo
    assert.is_nil(content:find(".hidden_parent", 1, true), "Parent dotfile should be hidden: " .. content)
    
    -- Check Current Pane Content
    local current_buf = state.current_buf_id
    local curr_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
    local curr_content = table.concat(curr_lines, "\n")
    
    -- .hidden_repo should be SHOWN because we are in git mode and it is untracked (??) or just present
    -- Wait, standard behavior: show untracked files? Yes.
    assert.is_not_nil(curr_content:find(".hidden_repo", 1, true), "Repo dotfile should be shown (untracked)")
  end)
end)
