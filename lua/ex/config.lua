-- Configuration management module

local utils = require('ex.utils')
local uv = vim.uv or vim.loop

local M = {}

local old_titlestring = vim.o.titlestring
local old_tagrelative = vim.o.tagrelative
local old_tags = vim.o.tags

---Reset configuration to previous state
function M.reset()
  vim.o.titlestring = old_titlestring
  vim.o.tagrelative = old_tagrelative
  vim.o.tags = old_tags
end

---Create new default configuration file
---@param file string Path to configuration file
function M.new_config(file)
  local config = {
    version = vim.g.exvim_ver,
    space = 2,
    includes = {
      '*.asm', '*.bash', '*.bat', '*.c', '*.cc', '*.cg', '*.cginc',
      '*.cp', '*.cpp', '*.cs', '*.css', '*.cxx', '*.fx', '*.fxh',
      '*.glsl', '*.go', '*.h', '*.hh', '*.hlsl', '*.hpp', '*.html',
      '*.hxx', '*.inl', '*.js', '*.json', '*.lua', '*.m', '*.mak',
      '*.makefile', '*.markdown', '*.md', '*.mk', '*.perl', '*.pl',
      '*.psh', '*.py', '*.rb', '*.rs', '*.ruby', '*.sh', '*.shader',
      '*.shd', '*.toml', '*.ts', '*.vim', '*.vsh', '*.xml', '*.yaml'
    },
    ignores = {
      '**/.DS_Store', '**/.git', '**/.svn', '**/.vs', '**/.vscode',
      '**/.exvim', '**/*.meta', '/ProjectSettings/', '/[Ll]ibrary/',
      '/[Ll]ogs/', '/[Bb]uild/', '/[Oo]bj/', '/[Tt]emp/'
    }
  }

  -- Use vim.json and vim.uv for file I/O
  local json_str = vim.json.encode(config)
  local fd = uv.fs_open(file, 'w', 438) -- 438 = 0666 octal
  if fd then
    uv.fs_write(fd, json_str, -1)
    uv.fs_close(fd)
  else
    utils.error("Failed to create config file: " .. file)
  end
end

---Build glob patterns for ripgrep
---@param patterns table List of patterns
---@param is_ignore boolean True for ignore patterns
---@return string
local function build_rg_globs(patterns, is_ignore)
  local globs = {}
  local prefix = is_ignore and '-g !' or '-g '

  for _, pattern in ipairs(patterns) do
    if utils.is_windows() then
      table.insert(globs, prefix .. pattern)
    else
      table.insert(globs, prefix .. "'" .. pattern .. "'")
    end
  end

  return table.concat(globs, ' ')
end

---Load configuration from directory
---@param dir string Directory containing config.json
function M.load(dir)
  local file = vim.fn.fnamemodify(dir .. 'config.json', ':p')

  -- Check if file exists using vim.uv
  local stat = uv.fs_stat(file)
  if not stat then
    M.new_config(file)
  end

  -- Read file using vim.uv
  local fd = uv.fs_open(file, 'r', 438)
  if not fd then
    utils.error("Failed to open config file: " .. file)
    return
  end

  local stat_result = uv.fs_fstat(fd)
  local data = uv.fs_read(fd, stat_result.size, 0)
  uv.fs_close(fd)

  if not data then
    utils.error("Failed to read config file: " .. file)
    return
  end

  -- Decode JSON using vim.json
  local ok, conf = pcall(vim.json.decode, data)
  if not ok then
    utils.error("Failed to parse config file: " .. file)
    return
  end

  if conf.version ~= vim.g.exvim_ver then
    M.new_config(file)
    return
  end

  if vim.fn.executable('rg') == 0 then
    utils.warning('rg is not executable, please install it first.')
    return
  end

  local ignores = build_rg_globs(conf.ignores, true)
  local includes = build_rg_globs(conf.includes, false)
  local rg_globs = includes .. ' ' .. ignores

  vim.g.exvim_dir = vim.fn.fnamemodify(dir, ':p')
  vim.g.exvim_cwd = vim.fn.fnamemodify(dir, ':p:h:h')
  vim.g.exvim_proj_name = vim.fs.basename(vim.g.exvim_cwd)

  vim.api.nvim_set_current_dir(vim.g.exvim_cwd)
  old_titlestring = vim.o.titlestring
  vim.o.titlestring = '[' .. vim.g.exvim_proj_name .. '] ' .. vim.g.exvim_cwd

  vim.o.signcolumn = 'yes'

  vim.o.tabstop = conf.space
  vim.o.softtabstop = conf.space
  vim.o.shiftwidth = conf.space

  old_tagrelative = vim.o.tagrelative
  vim.o.tagrelative = false

  old_tags = vim.o.tags
  vim.o.tags = old_tags .. ',' .. vim.fn.fnameescape(vim.g.exvim_dir .. 'tags')

  vim.g.ex_project_file = vim.fn.fnamemodify(dir .. 'files.exproject', ':p')

  -- Load project filters
  local project = require('ex.project')
  project.set_filters(conf.ignores, conf.includes)

  vim.g.ex_search_globs = rg_globs

  if vim.g.loaded_ctrlp then
    vim.g.ctrlp_user_command = 'rg %s --no-ignore --hidden --files ' .. rg_globs
  end

  if vim.g.loaded_nerd_tree then
    vim.g.NERDTreeIgnore = {}
    for _, ig in ipairs(conf.ignores) do
      if ig:match('^%*%..*') then
        table.insert(vim.g.NERDTreeIgnore, '\\' .. ig:sub(2))
      end
    end
  end

  if _G.___bufferline_private ~= nil then
    vim.fn['show_bufferline']()
  end
end

---Show configuration file
function M.show()
  local file = vim.fn.fnamemodify(vim.g.exvim_dir .. 'config.json', ':p')
  local stat = uv.fs_stat(file)
  if stat then
    vim.cmd('silent e ' .. vim.fn.escape(file, ' '))

    local bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].bufhidden = 'hide'
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].buflisted = false
    vim.bo[bufnr].wrap = false

    vim.api.nvim_create_autocmd('BufWritePost', {
      buffer = bufnr,
      callback = function()
        M.load(vim.g.exvim_dir)
      end,
    })
  end
end

return M
