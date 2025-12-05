-- exsearch filetype plugin (Lua version)

-- Prevent loading twice
if vim.b.did_ftplugin_exsearch then
  return
end
vim.b.did_ftplugin_exsearch = true

-- Get search module
local search = require('ex.search')

-- Buffer-local settings
vim.bo.buftype = 'nofile'
vim.bo.bufhidden = 'hide'
vim.bo.swapfile = false
vim.bo.buflisted = false

vim.wo.cursorline = true
vim.wo.number = true
vim.wo.wrap = false
vim.wo.statusline = ''
vim.wo.signcolumn = 'no'

-- Key mappings
local opts = {buffer = true, silent = true, noremap = true}

vim.keymap.set('n', '<F1>', function()
  search.toggle_help()
end, opts)

vim.keymap.set('n', '<ESC>', function()
  search.close_window()
end, opts)

vim.keymap.set('n', '<Space>', function()
  search.toggle_zoom()
end, opts)

vim.keymap.set('n', '<CR>', function()
  search.confirm_select('')
end, opts)

vim.keymap.set('n', '<2-LeftMouse>', function()
  search.confirm_select('')
end, opts)

vim.keymap.set('n', '<S-CR>', function()
  search.confirm_select('shift')
end, opts)

vim.keymap.set('n', '<S-2-LeftMouse>', function()
  search.confirm_select('shift')
end, opts)

vim.keymap.set('n', '<leader>r', function()
  search.filter(vim.fn.getreg('/'), 'pattern', false)
end, opts)

vim.keymap.set('n', '<leader>fr', function()
  search.filter(vim.fn.getreg('/'), 'file', false)
end, opts)

vim.keymap.set('n', '<leader>d', function()
  search.filter(vim.fn.getreg('/'), 'pattern', true)
end, opts)

vim.keymap.set('n', '<leader>fd', function()
  search.filter(vim.fn.getreg('/'), 'file', true)
end, opts)

-- Buffer-local commands
vim.api.nvim_buf_create_user_command(0, 'R', function(cmd_opts)
  search.filter(cmd_opts.args, 'pattern', false)
end, {nargs = 1})

vim.api.nvim_buf_create_user_command(0, 'FR', function(cmd_opts)
  search.filter(cmd_opts.args, 'file', false)
end, {nargs = 1})

vim.api.nvim_buf_create_user_command(0, 'D', function(cmd_opts)
  search.filter(cmd_opts.args, 'pattern', true)
end, {nargs = 1})

vim.api.nvim_buf_create_user_command(0, 'FD', function(cmd_opts)
  search.filter(cmd_opts.args, 'file', true)
end, {nargs = 1})
