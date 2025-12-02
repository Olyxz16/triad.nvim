
vim.api.nvim_create_user_command('Triad', function()
  require('triad').open()
end, {
  desc = 'Open Triad file explorer',
  bang = true,
})
