-- Window management module

local utils = require('ex.utils')
local plugin_mod = require('ex.plugin')

local M = {}

local winid_generator = 0
local last_editbuf_winid = -1
local last_editplugin_bufnr = -1

---Generate new window ID
---@return number
local function new_winid()
  winid_generator = winid_generator + 1
  return winid_generator
end

---Convert custom window ID to window handle
---@param winid number
---@return number|nil Window handle or nil
local function winid2win(winid)
  if winid == -1 then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].ex_winid == winid then
      return win
    end
  end
  return nil
end

---Create new window
---@param bufname string Buffer name to open
---@param size number Window size
---@param pos string Position: 'left', 'right', 'top', 'bottom'
---@param nested boolean If true, create beside current window
---@param callback function Init callback when window created
function M.new(bufname, size, pos, nested, callback)
  local winpos = ''
  if nested then
    if pos == 'left' or pos == 'top' then
      winpos = 'leftabove'
    elseif pos == 'right' or pos == 'bottom' then
      winpos = 'rightbelow'
    end
  else
    if pos == 'left' or pos == 'top' then
      winpos = 'topleft'
    elseif pos == 'right' or pos == 'bottom' then
      winpos = 'botright'
    end
  end

  local vcmd = ''
  if pos == 'left' or pos == 'right' then
    vcmd = 'vertical'
  end

  -- Find or create buffer (vim.fn.bufnr handles name lookup better than API)
  local bufnr = vim.fn.bufnr(bufname)
  local bufcmd = ''
  if bufnr == -1 then
    bufcmd = vim.fn.fnameescape(bufname)
  else
    bufcmd = '+b' .. bufnr
  end

  vim.cmd('silent ' .. winpos .. ' ' .. vcmd .. ' ' .. size .. ' split ' .. bufcmd)

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('winfixheight', true, {win = win})
  vim.api.nvim_set_option_value('winfixwidth', true, {win = win})

  callback()
end

---Open window
---@param bufname string Buffer name to open
---@param size number Window size
---@param pos string Position: 'left', 'right', 'top', 'bottom'
---@param nested boolean If true, create beside current window
---@param focus boolean If true, keep focus on opened window
---@param callback function Init callback when window created
function M.open(bufname, size, pos, nested, focus, callback)
  M.new(bufname, size, pos, nested, callback)

  if not focus then
    M.goto_edit_window()
  end

  if vim.g.lightline then
    vim.fn['lightline#update']()
  end
end

---Close window (by window handle or number)
---@param win number Window handle or number
function M.close(win)
  if not win or win == -1 then
    return
  end

  -- Convert window number to handle if needed
  if type(win) == 'number' and win < 1000 then
    win = vim.fn.win_getid(win)
  end

  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  vim.api.nvim_set_current_win(win)

  local ok = pcall(vim.cmd, 'close')
  if not ok then
    utils.warning('Can not close last window')
  end

  vim.cmd('doautocmd BufEnter')
end

---Resize window
---@param win number Window handle or number
---@param pos string Position of window
---@param new_size number New size
function M.resize(win, pos, new_size)
  if not win or win == -1 then
    return
  end

  -- Convert window number to handle if needed
  if type(win) == 'number' and win < 1000 then
    win = vim.fn.win_getid(win)
  end

  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  vim.api.nvim_set_current_win(win)

  local vcmd = ''
  if pos == 'left' or pos == 'right' then
    vcmd = 'vertical'
  end

  vim.cmd('silent ' .. vcmd .. ' resize ' .. new_size)
end

---Record window information
function M.record()
  local win = vim.api.nvim_get_current_win()

  if not vim.w[win].ex_winid then
    vim.w[win].ex_winid = new_winid()
  end

  local bufnr = vim.api.nvim_win_get_buf(win)
  if plugin_mod.is_registered(bufnr) then
    last_editplugin_bufnr = bufnr
  else
    last_editbuf_winid = vim.w[win].ex_winid
  end
end

---Check if window is a plugin window
---@param win number Window handle or number
---@return boolean
function M.is_plugin_window(win)
  -- Handle both window handles and window numbers
  if type(win) == 'number' and win < 1000 then
    -- It's a window number, convert to handle
    win = vim.fn.win_getid(win)
  end

  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local bufnr = vim.api.nvim_win_get_buf(win)
  return plugin_mod.is_registered(bufnr)
end

---Get last edit buffer number
---@return number
function M.last_edit_bufnr()
  local win = winid2win(last_editbuf_winid)
  if not win then
    return -1
  end
  return vim.api.nvim_win_get_buf(win)
end

---Go to edit window
function M.goto_edit_window()
  local current_win = vim.api.nvim_get_current_win()
  if not M.is_plugin_window(current_win) then
    return
  end

  local target_win = winid2win(last_editbuf_winid)

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    if vim.api.nvim_get_current_win() ~= target_win then
      vim.api.nvim_set_current_win(target_win)
    end
  else
    -- Search for another edit window
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not M.is_plugin_window(win) then
        vim.api.nvim_set_current_win(win)
        return
      end
    end

    -- Create new scratch buffer
    vim.cmd('rightbelow vsplit')
    vim.cmd('enew')
    local bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].buflisted = true
    vim.bo[bufnr].bufhidden = 'delete'
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {'this is the scratch buffer'})
  end
end

---Go to plugin window
function M.goto_plugin_window()
  if not vim.api.nvim_buf_is_valid(last_editplugin_bufnr) then
    return
  end

  -- Find window containing the plugin buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == last_editplugin_bufnr then
      if vim.api.nvim_get_current_win() ~= win then
        vim.api.nvim_set_current_win(win)
      end
      return
    end
  end
end

---Switch between edit and plugin window
function M.switch_window()
  if M.is_plugin_window(vim.api.nvim_get_current_win()) then
    M.goto_edit_window()
  else
    M.goto_plugin_window()
  end
end

---Close last edit plugin window
function M.close_last_edit_plugin_window()
  if not vim.api.nvim_buf_is_valid(last_editplugin_bufnr) then
    return
  end

  -- Find window containing the plugin buffer
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == last_editplugin_bufnr then
      target_win = win
      break
    end
  end

  if not target_win then
    return
  end

  local filetype = vim.bo[last_editplugin_bufnr].filetype

  if filetype == 'exproject' or filetype == 'nerdtree' or filetype == 'NvimTree' then
    return
  end

  M.close(target_win)
end

return M
