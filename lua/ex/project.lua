-- Project tree management module

local utils = require('ex.utils')
local window = require('ex.window')
local uv = vim.uv or vim.loop

local M = {}

-- State variables
local cur_project_file = ''
local ignore_patterns = ''
local include_patterns = ''
local zoom_in = false
local help_open = false
local level_list = {}

local help_default = {
  '" Press <F1> for help',
  '',
  '" <F1>: Toggle Help',
  '" <Space>: Zoom in/out project window',
  '" <Enter>: Open file or fold in/out folder',
  '" <2-LeftMouse>: Open file or fold in/out folder',
  '" <Shift-Enter>: Open file in split window or open folder in os file browser',
  '" <Ctrl-k>: Move cursor up to the nearest folder',
  '" <Ctrl-j>: Move cursor down to the nearest folder',
  '" <R>: Refresh the project',
  '" <r>: Refresh current folder',
  '" <O>: Create new folder',
  '" <o>: Create new file',
}

local help_short = {
  '" Press <F1> for help',
  '',
}

local help_text = help_short

-- Helper functions

---Check operating system (wrapper for utils functions)
---@param name string 'osx', 'windows', or 'linux'
---@return boolean
local function os_is(name)
  if name == 'osx' then
    return utils.is_mac()
  elseif name == 'windows' then
    return utils.is_windows()
  elseif name == 'linux' then
    return utils.is_linux()
  else
    utils.warning("Invalid name " .. name .. ", Please use 'osx', 'windows' or 'linux'")
    return false
  end
end

---Open path in OS file browser
---@param path string
local function os_open(path)
  local escaped_path = vim.fn.shellescape(path)

  if os_is('osx') then
    vim.cmd('silent !open ' .. escaped_path)
    utils.hint('open ' .. path)
  elseif os_is('windows') then
    local win_path = path:gsub('/', '\\')
    vim.cmd('silent !explorer ' .. vim.fn.shellescape(win_path))
    utils.hint('explorer ' .. win_path)
  else
    utils.warning('File browser not support in Linux')
  end
end

---Create pattern from list
---@param list table
---@return string
local function mk_pattern(list)
  local pattern = '\\m'

  for _, item in ipairs(list) do
    if item ~= '' then
      -- Escape special chars
      item = vim.fn.escape(item, '.~$')

      -- Replace patterns
      item = item:gsub('^/', '^')
      item = item:gsub('%*%*/%*', '.*')
      item = item:gsub('%*%*', '.*')
      item = item:gsub('([^.])%*', '%1[^/]*')
      item = item:gsub('^%*\\.(%S+)$', '[^/]*\\.%1$')

      pattern = pattern .. item .. '\\|'
    end
  end

  pattern = pattern:sub(1, -3) -- Remove last \|

  if os_is('windows') then
    pattern = pattern:gsub('/', '\\\\')
  end

  return pattern
end

---Search for pattern upward from line
---@param bufnr number Buffer number
---@param linenr number Starting line number
---@param pattern string Pattern to search
---@return number Line number or 0 if not found
local function search_for_pattern(bufnr, linenr, pattern)
  for ln = linenr, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, ln - 1, ln, false)[1]
    if line and line:match(pattern) then
      return ln
    end
  end
  return 0
end

---Get name from line
---@param bufnr number Buffer number
---@param linenr number Line number
---@return string
local function getname(bufnr, linenr)
  local line = vim.api.nvim_buf_get_lines(bufnr, linenr - 1, linenr, false)[1]
  if not line then return '' end

  line = line:gsub('.*%-(%[F%])?(.-)','%2')

  local idx_end_1 = line:find(' {')
  local idx_end_2 = line:find(' }')

  if idx_end_1 then
    line = line:sub(1, idx_end_1 - 1)
  elseif idx_end_2 then
    line = line:sub(1, idx_end_2 - 1)
  end

  return line
end

---Get fold level of line
---@param bufnr number Buffer number
---@param linenr number Line number
---@return number
local function getfoldlevel(bufnr, linenr)
  local curline = vim.api.nvim_buf_get_lines(bufnr, linenr - 1, linenr, false)[1]
  if not curline then return 0 end

  local idx = curline:find('|[^|]*$')
  if not idx then return 0 end

  local prefix = curline:sub(1, idx)
  return math.floor(#prefix / 2)
end

---Get full path of line
---@param bufnr number Buffer number
---@param linenr number Line number
---@return string
local function getpath(bufnr, linenr)
  local foldlevel = getfoldlevel(bufnr, linenr)

  if foldlevel == 0 then
    local cwd = vim.fn.getcwd()
    if vim.g.exvim_cwd then
      cwd = vim.g.exvim_cwd
    end
    return cwd
  end

  local fullpath = ''
  local line = vim.api.nvim_buf_get_lines(bufnr, linenr - 1, linenr, false)[1]
  if line and line:match('%[F%]') then
    fullpath = getname(bufnr, linenr)
  end

  local searchpos = linenr

  while foldlevel > 1 do
    foldlevel = foldlevel - 1
    local level_pattern = string.rep('.', foldlevel * 2)
    local fold_pattern = '^ ' .. level_pattern .. '%[F%]'
    searchpos = search_for_pattern(bufnr, searchpos, fold_pattern)

    if searchpos > 0 then
      fullpath = getname(bufnr, searchpos) .. '/' .. fullpath
    else
      utils.warning('Fold not found')
      break
    end
  end

  return fullpath
end

---Set level list from line
---@param bufnr number Buffer number
---@param linenr number Line number
local function set_level_list(bufnr, linenr)
  level_list = {}

  local cur_line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1]
  if not cur_line then return end

  local idx = cur_line:find('|[^|]*$')
  if not idx then return end

  cur_line = cur_line:sub(2, idx - 2)

  for i = 1, #cur_line, 2 do
    if cur_line:sub(i, i) == '|' then
      table.insert(level_list, {is_last = false, dirname = ''})
    else
      table.insert(level_list, {is_last = true, dirname = ''})
    end
  end
end

---Build project tree recursively
---@param bufnr number Buffer number
---@param path string Path to build from
---@param ignore_pat string Ignore patterns
---@param include_pat string Include patterns
---@return number 0 if added, 1 if not added
local function build_tree(bufnr, path, ignore_pat, include_pat)
  local dirname = vim.fs.basename(path)
  local stat = uv.fs_stat(path)
  local is_dir = stat and stat.type == 'directory'

  if is_dir then
    -- Get directory entries using vim.uv
    local handle = uv.fs_scandir(path)
    if not handle then return 1 end

    local results = {}
    while true do
      local name, type = uv.fs_scandir_next(handle)
      if not name then break end
      table.insert(results, path .. '/' .. name)
    end

    table.sort(results)

    local list_idx = 1
    local list_count = 0
    local list_last = #results

    while list_count < list_last do
      local result = vim.fn.fnamemodify(results[list_idx], ':p:.')

      -- Check ignore patterns
      if vim.fn.match(result, ignore_pat) ~= -1 then
        table.remove(results, list_idx)
        list_count = list_count + 1
        goto continue
      end

      -- Check include patterns for files
      local result_stat = uv.fs_stat(result)
      if result_stat and result_stat.type ~= 'directory' then
        if vim.fn.match(result, include_pat) == -1 then
          table.remove(results, list_idx)
          list_count = list_count + 1
          goto continue
        end

        -- Move file to end
        local file = table.remove(results, list_idx)
        table.insert(results, file)
        list_count = list_count + 1
        goto continue
      end

      list_idx = list_idx + 1
      list_count = list_count + 1

      ::continue::
    end

    table.insert(level_list, {is_last = false, dirname = dirname})

    -- Recursively process
    list_last = #results
    list_idx = list_last
    level_list[#level_list].is_last = true

    while list_idx >= 1 do
      if list_idx ~= list_last then
        level_list[#level_list].is_last = false
      end

      if build_tree(bufnr, results[list_idx], ignore_pat, include_pat) == 1 then
        table.remove(results, list_idx)
        list_last = #results
      end

      list_idx = list_idx - 1
    end

    table.remove(level_list)

    if #results == 0 then
      return 1
    end
  end

  -- Build display string
  local space = string.rep(' |', #level_list) .. '-'
  space = ' ' .. space:sub(2)

  local end_fold = ''
  for i = #level_list, 1, -1 do
    if level_list[i].is_last then
      end_fold = end_fold .. ' }'
    else
      break
    end
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  if not is_dir then
    if end_fold ~= '' then
      local end_space = space:sub(1, space:find('%-') - 2)
      end_space = end_space:sub(1, end_space:find('|[^|]*$'))
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, {end_space})
    end

    vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, {space .. dirname .. end_fold})
    return 0
  else
    local dir_handle = uv.fs_scandir(path)
    local is_empty = true
    if dir_handle then
      local first_entry = uv.fs_scandir_next(dir_handle)
      is_empty = first_entry == nil
    end

    if is_empty then
      local end_space = space:sub(1, space:find('%-') - 1)
      if end_fold ~= '' then
        end_space = end_space:sub(1, -2)
        end_space = end_space:sub(1, end_space:find('|[^|]*$'))
      end
      end_fold = end_fold .. ' }'
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, {end_space})
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, {space .. '[F]' .. dirname .. ' {' .. end_fold})
    else
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, {space .. '[F]' .. dirname .. ' {'})
    end
  end

  return 0
end

-- Callbacks

local function on_close()
  zoom_in = false
  help_open = false
  window.goto_edit_window()
end

local function on_save()
  if help_open then
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor_pos[1]
    local cursor_col = cursor_pos[2]
    local offset = #help_default - #help_short
    cursor_line = cursor_line - offset

    M.toggle_help()
    vim.api.nvim_win_set_cursor(0, {cursor_line, cursor_col})
    vim.cmd('normal! zz')
  end
end

-- Public functions

---Toggle help text
function M.toggle_help()
  help_open = not help_open
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, #help_text, false, {})

  if help_open then
    help_text = help_default
  else
    help_text = help_short
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, help_text)
  vim.api.nvim_win_set_cursor(0, {1, 0})
  utils.hl_clear_confirm()
end

---Initialize project buffer
function M.init_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = 'exproject'

  local group = vim.api.nvim_create_augroup('EXVIM_PROJECT', {clear = true})
  vim.api.nvim_create_autocmd('BufWinLeave', {
    group = group,
    buffer = bufnr,
    callback = on_close,
  })
  vim.api.nvim_create_autocmd('BufWritePre', {
    group = group,
    buffer = bufnr,
    callback = on_save,
  })

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 1 then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, help_text)
  end
end

---Open project window
function M.open_window()
  window.goto_edit_window()

  if cur_project_file == '' then
    cur_project_file = vim.g.ex_project_file
  end

  -- Find window with project buffer
  local proj_buf = vim.fn.bufnr(cur_project_file)
  local proj_win = nil
  if proj_buf ~= -1 then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == proj_buf then
        proj_win = win
        break
      end
    end
  end

  if not proj_win then
    window.open(
      cur_project_file,
      vim.g.ex_project_winsize,
      vim.g.ex_project_winpos,
      false,
      true,
      M.init_buffer
    )
  else
    vim.api.nvim_set_current_win(proj_win)
  end
end

---Open project
---@param filename string|nil
function M.open(filename)
  filename = filename or ''

  if filename == '' then
    filename = vim.g.ex_project_file
  end

  if filename ~= cur_project_file then
    if cur_project_file ~= '' then
      local old_buf = vim.fn.bufnr(cur_project_file)
      if old_buf ~= -1 then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == old_buf then
            window.close(win)
            break
          end
        end
      end
    end
    cur_project_file = filename
  end

  M.open_window()
end

---Close project window
---@return number 1 if closed, 0 if not found
function M.close_window()
  if cur_project_file ~= '' then
    local proj_buf = vim.fn.bufnr(cur_project_file)
    if proj_buf ~= -1 then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == proj_buf then
          window.close(win)
          return 1
        end
      end
    end
  end
  return 0
end

---Toggle project window
function M.toggle_window()
  if M.close_window() == 0 then
    M.open_window()
  end
end

---Toggle zoom
function M.toggle_zoom()
  if cur_project_file ~= '' then
    local proj_buf = vim.fn.bufnr(cur_project_file)
    if proj_buf ~= -1 then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == proj_buf then
          if zoom_in then
            zoom_in = false
            window.resize(win, vim.g.ex_project_winpos, vim.g.ex_project_winsize)
          else
            zoom_in = true
            window.resize(win, vim.g.ex_project_winpos, vim.g.ex_project_winsize_zoom)
          end
          break
        end
      end
    end
  end
end

---Get foldtext for project buffer
---@return string
function M.foldtext()
  local line = vim.fn.getline(vim.v.foldstart)
  line = line:gsub('%[F%](.-) {.*', '[+]%1 ')
  return line
end

---Confirm selection in project tree
---@param modifier string '' or 'shift'
function M.confirm_select(modifier)
  local bufnr = vim.api.nvim_get_current_buf()
  local curline = vim.api.nvim_get_current_line()

  if not curline:match('|%-') and not curline:match('^ %[F%]') then
    utils.warning('Please select a file or folder')
    return
  end

  local editcmd = 'e'
  if modifier == 'shift' then
    editcmd = 'bel sp'
  end

  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  -- Handle folder
  if vim.fn.foldclosed('.') ~= -1 or curline:match('%[F%]') then
    if modifier == 'shift' then
      os_open(getpath(bufnr, cursor_line))
    else
      vim.cmd('normal! za')
    end
    return
  end

  local fullpath = getpath(bufnr, cursor_line) .. getname(bufnr, cursor_line)
  vim.api.nvim_win_set_cursor(0, {cursor_line, cursor_col})

  fullpath = vim.fn.fnamemodify(fullpath, ':p')
  fullpath = vim.fn.fnameescape(fullpath)

  local filetype = vim.fn.fnamemodify(fullpath, ':e')
  if filetype == 'err' or filetype == 'exe' then
    return
  end

  utils.hint(vim.fn.fnamemodify(fullpath, ':p:.'))

  if zoom_in then
    M.toggle_zoom()
  end

  window.goto_edit_window()

  local cur_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p')
  local target_file = vim.fn.fnamemodify(fullpath, ':p')
  if cur_file ~= target_file then
    vim.cmd('silent ' .. editcmd .. ' ' .. fullpath)
  end
end

---Build project tree
function M.build_tree()
  level_list = {}

  local cwd = vim.fn.getcwd()
  if vim.g.exvim_cwd then
    cwd = vim.g.exvim_cwd
  end

  print('Creating ex_project: ' .. cwd)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  build_tree(bufnr, cwd, ignore_patterns, include_patterns)

  vim.api.nvim_win_set_cursor(0, {1, 0})
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, help_text)
  vim.cmd('silent w!')
  print('ex_project: ' .. cwd .. ' created!')
end

---Find file in project tree
---@param path string|nil
function M.find(path)
  window.goto_edit_window()

  path = path or ''
  if path == '' then
    path = vim.api.nvim_buf_get_name(0)
  end

  -- Strip last separator
  if path:sub(-1) == utils.os_sep() then
    path = path:sub(1, -2)
  end

  local filename = vim.fs.basename(path)
  local filepath = vim.fn.fnamemodify(path, ':p')
  local stat = uv.fs_stat(filepath)
  local is_dir = stat and stat.type == 'directory'

  M.open_window()

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  vim.api.nvim_win_set_cursor(0, {1, 0})

  local found = false
  while not found do
    if vim.fn.search(filename, 'W') > 0 then
      local linenr = vim.api.nvim_win_get_cursor(0)[1]
      local searchfilename = getpath(bufnr, linenr)

      if not is_dir then
        searchfilename = searchfilename .. getname(bufnr, linenr)
      end

      if vim.fn.fnamemodify(searchfilename, ':p') == filepath then
        vim.api.nvim_win_set_cursor(0, {linenr, 0})
        vim.cmd('silent normal! zv')
        vim.cmd('silent normal! zz')
        found = true
        print('Locate file: ' .. path)
        break
      end
    else
      vim.api.nvim_win_set_cursor(0, {cursor_line, cursor_col})
      utils.warning('File not found: ' .. vim.fn.fnamemodify(filepath, ':p:.'))
      window.goto_edit_window()
      return
    end
  end
end

---Refresh current folder
function M.refresh_current_folder()
  level_list = {}

  local bufnr = vim.api.nvim_get_current_buf()
  local curline = vim.api.nvim_get_current_line()

  if not curline:match('|%-') and not curline:match('^ %[F%]') then
    utils.warning('Please select a file or folder')
    return
  end

  if vim.fn.foldclosed('.') ~= -1 then
    vim.cmd('normal! zr')
  end

  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  local fold_level = getfoldlevel(bufnr, cursor_line)
  fold_level = fold_level - 1
  local level_pattern = string.rep('.', fold_level * 2)
  local fold_pattern = '^ ' .. level_pattern .. '%[F%]'
  local full_path_name = ''

  if not curline:match('%[F%]') then
    if vim.fn.search(fold_pattern, 'b') > 0 then
      full_path_name = getname(bufnr, vim.api.nvim_win_get_cursor(0)[1])
      vim.api.nvim_win_set_cursor(0, {cursor_line, cursor_col})
    else
      utils.warning('The project may broke, fold pattern not found: ' .. fold_pattern)
      return
    end
  else
    full_path_name = getname(bufnr, cursor_line)
    fold_level = fold_level + 1
  end

  local dirname = full_path_name

  if fold_level == 0 then
    full_path_name = ''
  end

  local is_root = fold_level == 0

  if not is_root then
    while fold_level > 1 do
      fold_level = fold_level - 1
      level_pattern = string.rep('.', fold_level * 2)
      fold_pattern = '^ ' .. level_pattern .. '%[F%]'

      if vim.fn.search(fold_pattern, 'b') > 0 then
        full_path_name = getname(bufnr, vim.api.nvim_win_get_cursor(0)[1]) .. '/' .. full_path_name
      else
        utils.warning('The project may broke, fold pattern not found: ' .. fold_pattern)
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(0, {cursor_line, cursor_col})

  full_path_name = vim.fn.fnamemodify(full_path_name, ':p')
  full_path_name = full_path_name:sub(1, -2)
  print('ex-project: Refresh folder: ' .. full_path_name)

  if not is_root then
    set_level_list(bufnr, cursor_line)
  end

  vim.cmd('normal! zc')
  vim.cmd('normal! "_2dd')

  build_tree(bufnr, full_path_name, ignore_patterns, include_patterns)

  local cur_line = vim.api.nvim_get_current_line()
  local pattern = '%[F%].*' .. dirname .. ' {'

  if not cur_line:match(pattern) then
    utils.warning('The folder is empty')
    return
  end

  local idx_start = cur_line:find(']')
  local start_part = cur_line:sub(1, idx_start)
  local idx_end = cur_line:find(' {')
  local end_part = cur_line:sub(idx_end)

  vim.api.nvim_buf_set_lines(bufnr, cursor_line - 1, cursor_line, false, {start_part .. dirname .. end_part})
  vim.cmd('silent w!')
  print('ex-project: Refresh folder: ' .. full_path_name .. ' done!')
end

---Set filter patterns
---@param ignores table
---@param includes table
function M.set_filters(ignores, includes)
  ignore_patterns = mk_pattern(ignores)
  include_patterns = mk_pattern(includes)
end

---Show filter patterns
function M.show_filters()
  print('ignores: ' .. ignore_patterns .. '\n\nincludes: ' .. include_patterns)
end

---Create new file in project
function M.newfile()
  local bufnr = vim.api.nvim_get_current_buf()
  local cur_line = vim.api.nvim_get_current_line()

  if not cur_line:match('( |)+%-.*') then
    utils.warning("Can't create new file here. Please move your cursor to a file or a folder.")
    return
  end

  local reg_t = vim.fn.getreg('t')

  if vim.fn.foldclosed('.') ~= -1 then
    vim.cmd('normal! j"tyy"t2p$a-')
    vim.fn.setreg('t', reg_t)
    return
  end

  if cur_line:match('%[F%]') then
    local idx = cur_line:find('}')
    if not idx then
      vim.cmd('normal! j"tyy"tP')
      vim.fn.search('|%-', 'c')
      vim.cmd('normal! c$|-')
      vim.cmd('startinsert!')
    else
      local suffix = cur_line:sub(idx - 1)
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      vim.api.nvim_buf_set_lines(bufnr, cursor_line - 1, cursor_line, false, {cur_line:sub(1, idx - 2)})
      local file_line = cur_line:sub(1, cur_line:find('%-')) .. ' |-' .. suffix
      vim.api.nvim_buf_set_lines(bufnr, cursor_line, cursor_line, false, {file_line})
      vim.fn.search(' }', 'c')
      vim.cmd('startinsert')
    end
  else
    local idx = cur_line:find('}')
    if not idx then
      vim.cmd('normal! "tyyj"tP')
      vim.fn.search('|%-', 'c')
      vim.cmd('normal! c$|-')
      vim.cmd('startinsert!')
    else
      local suffix = cur_line:sub(idx - 1)
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      vim.api.nvim_buf_set_lines(bufnr, cursor_line - 1, cursor_line, false, {cur_line:sub(1, idx - 2)})
      local file_line = cur_line:sub(1, cur_line:find('%-')) .. '-' .. suffix
      vim.api.nvim_buf_set_lines(bufnr, cursor_line, cursor_line, false, {file_line})
      vim.fn.search(' }', 'c')
      vim.cmd('startinsert')
    end
  end

  vim.fn.setreg('t', reg_t)
end

---Create new folder in project
function M.newfolder()
  local bufnr = vim.api.nvim_get_current_buf()
  local cur_line = vim.api.nvim_get_current_line()

  if not cur_line:match('%[F%]') then
    utils.warning("Can't create new folder here, Please move your cursor to a parent folder.")
    return
  end

  vim.api.nvim_echo({{'Folder Name: ', 'Question'}}, false, {})
  local foldername = vim.fn.input('')

  if foldername == '' then
    utils.warning("Can't create empty folder.")
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local path = getpath(bufnr, cursor_line)

  if vim.fn.finddir(foldername, path) ~= '' then
    utils.warning(' The folder ' .. foldername .. ' already exists!')
    return
  end

  if path == '' then
    path = '.'
  end

  uv.fs_mkdir(path .. '/' .. foldername, 493) -- 493 = 0755 octal
  utils.hint(' created!')

  local reg_t = vim.fn.getreg('t')

  if vim.fn.foldclosed('.') ~= -1 then
    vim.cmd('normal! j"tyy"t2p$a-[F]' .. foldername .. ' { }')
    vim.fn.setreg('t', reg_t)
    return
  end

  local idx = cur_line:find('}')
  if not idx then
    local file_line = cur_line
    vim.api.nvim_buf_set_lines(bufnr, cursor_line, cursor_line, false, {file_line})
    vim.fn.search('%-[F]', 'c')
    vim.cmd('normal! c$ |-[F]' .. foldername .. ' { }')
  else
    local suffix = cur_line:sub(idx - 1)
    vim.api.nvim_buf_set_lines(bufnr, cursor_line - 1, cursor_line, false, {cur_line:sub(1, idx - 2)})
    local file_line = cur_line:sub(1, cur_line:find('%-')) .. ' |-[F]' .. foldername .. ' { }' .. suffix
    vim.api.nvim_buf_set_lines(bufnr, cursor_line, cursor_line, false, {file_line})
  end

  vim.fn.setreg('t', reg_t)
end

---Jump cursor to folder
---@param search_pattern string
---@param search_direction string 'up' or 'down'
function M.cursor_jump(search_pattern, search_direction)
  local save_cursor = vim.api.nvim_win_get_cursor(0)

  local search_flags = ''
  if search_direction == 'up' then
    search_flags = 'bW'
    vim.cmd('normal! ^')
  else
    search_flags = 'W'
    vim.cmd('normal! $')
  end

  local jump_line = vim.fn.search(search_pattern, search_flags)
  if jump_line == 0 then
    vim.api.nvim_win_set_cursor(0, save_cursor)
  end
end

return M
