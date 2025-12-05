-- exvim-lite main module

local uv = vim.uv or vim.loop

local M = {}

M.VERSION = '2.0.0'

-- Store global state
M.state = {
  exvim_ver = M.VERSION,
  exvim_dir = '',
  exvim_cwd = '',
  exvim_proj_name = '',
}

-- Load submodules
M.utils = require('ex.utils')
M.config = require('ex.config')
M.buffer = require('ex.buffer')
M.window = require('ex.window')
M.plugin = require('ex.plugin')
M.project = require('ex.project')
M.search = require('ex.search')

---Setup exvim-lite with user configuration
---@param opts table|nil Optional configuration
function M.setup(opts)
  opts = opts or {}

  -- Set global variables
  vim.g.exvim_ver = M.VERSION
  vim.g.exvim_dir = ''
  vim.g.exvim_cwd = ''

  -- ex_search default configuration
  vim.g.ex_search_winsize = opts.search_winsize or 15
  vim.g.ex_search_winsize_zoom = opts.search_winsize_zoom or 40
  vim.g.ex_search_winpos = opts.search_winpos or 'bottom'
  vim.g.ex_search_enable_sort = opts.search_enable_sort ~= false and 1 or 0
  vim.g.ex_search_sort_lines_threshold = opts.search_sort_lines_threshold or 100
  vim.g.ex_search_globs = opts.search_globs or ''

  -- ex_project default configuration
  vim.g.ex_project_file = opts.project_file or './.exvim/files.exproject'
  vim.g.ex_project_winsize = opts.project_winsize or 30
  vim.g.ex_project_winsize_zoom = opts.project_winsize_zoom or 60
  vim.g.ex_project_winpos = opts.project_winpos or 'left'
  vim.g.ex_project_globs = opts.project_globs or ''

  -- Setup highlights
  M.setup_highlights()

  -- Register default plugins
  M.register_default_plugins()

  -- Setup autocommands
  M.setup_autocmds()

  -- Setup user commands
  M.setup_commands()
end

---Setup highlight groups
function M.setup_highlights()
  vim.api.nvim_set_hl(0, 'EX_CONFIRM_LINE', {
    bg = '#702963',
    ctermbg = 'darkyellow',
    default = true
  })

  vim.api.nvim_set_hl(0, 'EX_TARGET_LINE', {
    bg = '#702963',
    ctermbg = 'darkyellow',
    default = true
  })

  vim.api.nvim_set_hl(0, 'EX_TRANSPARENT', {
    fg = 'background',
    ctermfg = 'darkgray',
    default = true
  })
end

---Register default plugins
function M.register_default_plugins()
  M.plugin.register('help', {buftype = 'help'})
  M.plugin.register('qf', {buftype = 'quickfix'})
  M.plugin.register('exsearch', {})
  M.plugin.register('exproject', {})
  M.plugin.register('nerdtree', {bufname = 'NERD_tree_%d+', buftype = 'nofile'})
  M.plugin.register('NvimTree', {})
end

---Check if vim started with minimal args
---@return boolean
local function barely_start_vim()
  if vim.fn.argc() == 0 then
    return true
  end

  local arg0 = vim.fn.argv(0)
  if vim.fn.findfile(vim.fn.fnamemodify(arg0, ':p')) ~= '' then
    return false
  end

  if vim.fn.fnamemodify(arg0, ':p:h') == vim.fn.fnamemodify(vim.g.exvim_dir, ':p:h:h') then
    return true
  end

  return false
end

---Find .exvim folder upward
local function find_exvim_folder()
  -- Use vim.fs.find for modern directory searching
  local found = vim.fs.find('.exvim', {
    upward = true,
    type = 'directory',
    path = vim.fn.getcwd(),
  })

  if #found == 0 then
    return
  end

  local path = found[1] .. '/'
  local target = vim.fn.argc() > 0 and vim.fn.fnamemodify(vim.fn.argv(0), ':p') or ''

  M.config.load(path)

  if target ~= '' and vim.fn.findfile(target) == '' then
    M.config.show()
  end

  -- Open project window
  if M.project then
    M.project.open()
    if target ~= '' and (vim.fn.findfile(target) ~= '' or vim.fn.finddir(target) ~= '') then
      M.project.find(target)
    end
  end
end

---Create new exvim project
---@param dir string Directory path
function M.new_exvim_project(dir)
  local path = vim.fn.fnamemodify(dir, ':p')
  if path == '' then
    M.utils.error("Can't find path: " .. dir)
    return
  end

  -- Check if .exvim already exists
  local exvim_path = path .. '.exvim'
  local stat = uv.fs_stat(exvim_path)

  if not stat then
    uv.fs_mkdir(exvim_path, 493) -- 493 = 0755 octal
  end

  M.config.load(exvim_path .. '/')
  M.config.show()
end

---Setup user commands
function M.setup_commands()
  vim.api.nvim_create_user_command('EXVIM', function(opts)
    M.new_exvim_project(opts.args)
  end, {nargs = '?', complete = 'dir'})

  vim.api.nvim_create_user_command('EXbn', function()
    M.buffer.navigate('bn')
  end, {})

  vim.api.nvim_create_user_command('EXbp', function()
    M.buffer.navigate('bp')
  end, {})

  vim.api.nvim_create_user_command('EXbalt', function()
    M.buffer.to_alternate_edit_buf()
  end, {})

  vim.api.nvim_create_user_command('EXbd', function()
    M.buffer.keep_window_bd()
  end, {})

  vim.api.nvim_create_user_command('EXsw', function()
    M.window.switch_window()
  end, {})

  vim.api.nvim_create_user_command('EXgp', function()
    M.window.goto_plugin_window()
  end, {})

  vim.api.nvim_create_user_command('EXgc', function()
    M.window.close_last_edit_plugin_window()
  end, {})

  vim.api.nvim_create_user_command('EXplugins', function()
    M.plugin.echo_registered()
  end, {})

  -- Project commands
  vim.api.nvim_create_user_command('EXProject', function(opts)
    M.project.open(opts.args)
  end, {nargs = '?', complete = 'file'})

  vim.api.nvim_create_user_command('EXProjectFind', function(opts)
    M.project.find(opts.args)
  end, {nargs = '?', complete = 'file'})

  -- Search commands
  vim.api.nvim_create_user_command('GS', function(opts)
    M.search.exec(opts.args, '-s')
  end, {nargs = 1})

  vim.api.nvim_create_user_command('EXSearchCWord', function()
    M.search.exec(vim.fn.expand('<cword>'), '-s')
  end, {})
end

---Setup autocommands
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup('EXVIM', {clear = true})

  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    nested = true,
    callback = find_exvim_folder,
  })

  vim.api.nvim_create_autocmd({'VimEnter', 'WinLeave'}, {
    group = group,
    callback = function()
      M.window.record()
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    callback = function()
      M.buffer.record()
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function()
      M.window.goto_edit_window()
    end,
  })
end

return M
