-- Search functionality module

local utils = require('ex.utils')
local window = require('ex.window')

local M = {}

-- State variables
local title = '-Search Results-'
local confirm_at = -1
local zoom_in = false
local help_open = false

local help_default = {
  '" Press <F1> for help',
  '',
  '" <F1>: Toggle Help',
  '" <ESC>: Close Window',
  '" <Space>: Zoom in/out window',
  '" <Enter>: Go to the search result',
  '" <2-LeftMouse>: Go to the search result',
  '" <Shift-Enter>: Go to the search result in split window',
  '" <Shift-2-LeftMouse>: Go to the search result in split window',
  '" <leader>r: Filter out search result',
  '" <leader>fr: Filter out search result (files only)',
  '" <leader>d: Reverse filter out search result',
  '" <leader>fd: Reverse filter out search result (files only)',
}

local help_short = {
  '" Press <F1> for help',
  '',
}

local help_text = help_short

-- Helper functions

---Compare two search result lines for sorting
---@param line1 string
---@param line2 string
---@return number
local function search_result_comp(line1, line2)
  local line1lst = {line1:match('^([^:]*):(%d+):')}
  local line2lst = {line2:match('^([^:]*):(%d+):')}

  if #line1lst == 0 and #line2lst == 0 then
    return 0
  elseif #line1lst == 0 then
    return -1
  elseif #line2lst == 0 then
    return 1
  else
    if line1lst[1] ~= line2lst[1] then
      return line1lst[1] < line2lst[1] and -1 or 1
    else
      local linenum1 = tonumber(line1lst[2])
      local linenum2 = tonumber(line2lst[2])
      if linenum1 == linenum2 then
        return 0
      end
      return linenum1 < linenum2 and -1 or 1
    end
  end
end

---Sort search results
---@param bufnr number Buffer number
---@param start_line number
---@param end_line number
local function sort_search_result(bufnr, start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  table.sort(lines, function(a, b)
    return search_result_comp(a, b) < 0
  end)
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, lines)
end

-- Callbacks

local function on_close()
  zoom_in = false
  help_open = false
  window.goto_edit_window()
  utils.hl_clear_target()
end

-- Public functions

---Toggle help text
function M.toggle_help()
  help_open = not help_open
  local bufnr = vim.api.nvim_get_current_buf()

  -- Delete old help lines
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

---Initialize search buffer
function M.init_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = 'exsearch'

  local group = vim.api.nvim_create_augroup('EXVIM_SEARCH', {clear = true})
  vim.api.nvim_create_autocmd('BufWinLeave', {
    group = group,
    buffer = bufnr,
    callback = on_close,
  })

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 1 then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, help_text)
  end
end

---Open search window
function M.open_window()
  window.goto_edit_window()

  -- Find window containing search buffer
  local search_buf = vim.fn.bufnr(title)
  local search_win = nil
  if search_buf ~= -1 then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == search_buf then
        search_win = win
        break
      end
    end
  end

  if not search_win then
    window.open(
      title,
      vim.g.ex_search_winsize,
      vim.g.ex_search_winpos,
      true,
      true,
      M.init_buffer
    )
    if confirm_at ~= -1 then
      utils.hl_confirm_line(confirm_at)
    end
  else
    vim.api.nvim_set_current_win(search_win)
  end
end

---Close search window
---@return number 1 if closed, 0 if not found
function M.close_window()
  local search_buf = vim.fn.bufnr(title)
  if search_buf == -1 then
    return 0
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == search_buf then
      window.close(win)
      return 1
    end
  end
  return 0
end

---Toggle search window
function M.toggle_window()
  if M.close_window() == 0 then
    M.open_window()
  end
end

---Toggle zoom
function M.toggle_zoom()
  local search_buf = vim.fn.bufnr(title)
  if search_buf == -1 then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == search_buf then
      if zoom_in then
        zoom_in = false
        window.resize(win, vim.g.ex_search_winpos, vim.g.ex_search_winsize)
      else
        zoom_in = true
        window.resize(win, vim.g.ex_search_winpos, vim.g.ex_search_winsize_zoom)
      end
      break
    end
  end
end

---Confirm selection in search results
---@param modifier string '' or 'shift'
function M.confirm_select(modifier)
  local line = vim.api.nvim_get_current_line()

  local filename = line
  local idx = line:find(':')
  if idx then
    filename = line:sub(1, idx - 1)
  end

  if vim.fn.findfile(filename) == '' then
    utils.warning(filename .. ' not found!')
    return
  end

  confirm_at = vim.api.nvim_win_get_cursor(0)[1]
  utils.hl_confirm_line(confirm_at)

  window.goto_edit_window()

  if modifier == 'shift' then
    local linenr = 1
    if idx then
      local rest = line:sub(idx + 1)
      local idx2 = rest:find(':')
      if idx2 then
        linenr = tonumber(rest:sub(1, idx2 - 1)) or 1
      end
    end

    vim.cmd('silent pedit +' .. linenr .. ' ' .. vim.fn.escape(filename, ' '))
    -- Try to go to preview window
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.wo[win].previewwindow then
        vim.api.nvim_set_current_win(win)
        utils.hl_target_line(vim.api.nvim_win_get_cursor(0)[1])
        break
      end
    end
    window.goto_plugin_window()
  else
    local cur_buf = vim.api.nvim_get_current_buf()
    local target_buf = vim.fn.bufnr(filename)
    if cur_buf ~= target_buf then
      vim.cmd('silent e ' .. vim.fn.escape(filename, ' '))
    end

    if idx then
      local rest = line:sub(idx + 1)
      local idx2 = rest:find(':')
      if idx2 then
        local linenr = tonumber(rest:sub(1, idx2 - 1)) or 1
        vim.api.nvim_win_set_cursor(0, {linenr, 0})

        local pattern = rest:sub(idx2 + 2)
        pattern = '\\V' .. pattern:gsub('\\', '\\\\')

        if vim.fn.search(pattern, 'cw') == 0 then
          utils.warning('Line pattern not found: ' .. pattern)
        end
      end
    end

    vim.cmd('normal! zz')
    utils.hl_target_line(vim.api.nvim_win_get_cursor(0)[1])
    window.goto_plugin_window()
  end
end

---Execute search with ripgrep
---@param pattern string Search pattern
---@param method string Search method
function M.exec(pattern, method)
  confirm_at = -1

  print('search ' .. pattern .. '...(smart case)')

  -- Use vim.system (Neovim 0.10+)
  local obj = vim.system({'rg', '--no-heading', '--line-number', '--smart-case', '--no-ignore', '--hidden', pattern}, {
    cwd = vim.uv.cwd(),
    text = true,
  })
  local output = obj:wait()
  local result = output.stdout or ''

  M.open_window()

  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- Add help
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, help_text)
  local start_line = #help_text + 1

  -- Add results
  local header = '---------- ' .. pattern .. ' ----------'
  local lines = vim.split(result, '\n', {trimempty = true})
  table.insert(lines, 1, header)
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, start_line - 1, false, lines)

  local end_line = vim.api.nvim_buf_line_count(bufnr)

  -- Sort results if enabled
  if vim.g.ex_search_enable_sort == 1 then
    local line_count = end_line - start_line
    if line_count <= vim.g.ex_search_sort_lines_threshold then
      sort_search_result(bufnr, start_line + 1, end_line)
    end
  end

  -- Position cursor
  vim.api.nvim_win_set_cursor(0, {1, 0})
  vim.fn.search(header, 'w')
  vim.cmd('normal! zz')
end

---Filter search results
---@param pattern string Filter pattern
---@param option string 'pattern' or 'file'
---@param reverse boolean Reverse filter (exclude matches)
function M.filter(pattern, option, reverse)
  if pattern == '' then
    utils.warning('Search pattern is empty. Please provide your search pattern')
    return
  end

  local final_pattern = pattern
  if option == 'pattern' then
    final_pattern = '^.\\+:\\d\\+:.*\\zs' .. pattern
  elseif option == 'file' then
    final_pattern = '\\(.\\+:\\d\\+:\\)\\&' .. pattern
  end

  local start_line = #help_text + 2
  local range = start_line .. ',$'

  if reverse then
    local search_results = '\\(.\\+:\\d\\+:\\).*'
    vim.cmd('silent ' .. range .. 'v/' .. search_results .. '/d')
    vim.cmd('silent ' .. range .. 'g/' .. final_pattern .. '/d')
  else
    vim.cmd('silent ' .. range .. 'v/' .. final_pattern .. '/d')
  end

  vim.api.nvim_win_set_cursor(0, {start_line, 0})
  utils.hint('Filter ' .. option .. ': ' .. pattern)
end

return M
