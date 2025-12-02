-- dev_init.lua

-- 1. Create a local directory to store plugins/state for this test environment
--    This ensures we don't pollute your main ~/.local/share/nvim
local dev_path = vim.fn.fnamemodify("./.dev", ":p")
local lazypath = dev_path .. "lazy/lazy.nvim"

-- 2. Bootstrap lazy.nvim (download it if it doesn't exist in our dev folder)
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- 3. Setup Lazy with our local plugin
require("lazy").setup({
  -- Dependencies
  { "nvim-lua/plenary.nvim" },
  { "nvim-tree/nvim-web-devicons" },

  -- YOUR LOCAL PLUGIN
  {
    dir = ".", -- Points to the current directory (triad.nvim)
    name = "triad.nvim",
    config = function()
      -- Calls the setup function of your plugin
      require("triad").setup({
        -- Put any default config options here to test them
      })

      -- Optional: Map a key to open it immediately for faster testing
      vim.keymap.set("n", "<leader>e", ":Triad<CR>", { noremap = true })
    end,
  },
}, {
  -- Configuration to keep this isolated
  root = dev_path .. "plugins",
  lockfile = dev_path .. "lazy-lock.json",
  state = dev_path .. "state",
})

-- 4. Basic Vim settings for a sane development environment
vim.opt.number = true
vim.opt.termguicolors = true
