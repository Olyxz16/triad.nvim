-- tests/minimal_init.lua
local M = {}

function M.root(root)
  local f = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(f, ":p:h:h") .. "/" .. (root or "")
end

-- 1. Define paths for test dependencies
local load_path = M.root(".tests/site/pack/deps/start")
local plenary_dir = load_path .. "/plenary.nvim"
local devicons_dir = load_path .. "/nvim-web-devicons"

-- 2. Ensure the test directory structure exists
vim.fn.mkdir(load_path, "p")

-- 3. Download plenary.nvim if it doesn't exist
if vim.fn.isdirectory(plenary_dir) == 0 then
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/nvim-lua/plenary.nvim",
    plenary_dir,
  })
end

-- Download nvim-web-devicons if it doesn't exist
if vim.fn.isdirectory(devicons_dir) == 0 then
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/nvim-tree/nvim-web-devicons",
    devicons_dir,
  })
end

-- 4. Add plenary to the runtime path (rtp)
--    We add it to 'packpath' so we don't need to manually source plugin/ files
vim.opt.packpath:prepend(M.root(".tests/site"))

-- 5. Add the current plugin (triad.nvim) to the runtime path
vim.opt.rtp:append(M.root())
vim.cmd("runtime! plugin/triad.lua")

-- 6. Load necessary plugin files
--    This ensures the :PlenaryBustedDirectory command is registered
vim.cmd("runtime! plugin/plenary.vim")
require("plenary.busted")
