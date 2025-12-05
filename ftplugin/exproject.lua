-- exproject filetype plugin (Lua version)

-- Prevent loading twice
if vim.b.did_ftplugin_exproject then
  return
end
vim.b.did_ftplugin_exproject = true

-- Get project module
local project = require('ex.project')

-- Buffer-local settings
vim.bo.buftype = ''
vim.bo.bufhidden = 'hide'
vim.bo.swapfile = false
vim.bo.buflisted = false

vim.wo.cursorline = true
vim.wo.number = false
vim.wo.wrap = false
vim.wo.statusline = ''
vim.wo.signcolumn = 'no'

vim.wo.foldenable = true
vim.wo.foldmethod = 'marker'
vim.wo.foldmarker = '{,}'
vim.wo.foldtext = 'v:lua.require("ex.project").foldtext()'
vim.wo.foldminlines = 0

-- Key mappings
local opts = {buffer = true, silent = true, noremap = true}

vim.keymap.set('n', '<F1>', function()
  project.toggle_help()
end, opts)

vim.keymap.set('n', '<Space>', function()
  project.toggle_zoom()
end, opts)

vim.keymap.set('n', '<CR>', function()
  project.confirm_select('')
end, opts)

vim.keymap.set('n', '<2-LeftMouse>', function()
  project.confirm_select('')
end, opts)

vim.keymap.set('n', '<S-CR>', function()
  project.confirm_select('shift')
end, opts)

vim.keymap.set('n', '<S-2-LeftMouse>', function()
  project.confirm_select('shift')
end, opts)

vim.keymap.set('n', '<C-k>', function()
  project.cursor_jump('\\C\\[F\\]', 'up')
end, opts)

vim.keymap.set('n', '<C-j>', function()
  project.cursor_jump('\\C\\[F\\]', 'down')
end, opts)

vim.keymap.set('n', 'R', function()
  project.build_tree()
end, opts)

vim.keymap.set('n', 'r', function()
  project.refresh_current_folder()
end, opts)

vim.keymap.set('n', 'o', function()
  project.newfile()
end, opts)

vim.keymap.set('n', 'O', function()
  project.newfolder()
end, opts)
