-- Buffer management module

local utils = require('ex.utils')
local window = require('ex.window')
local plugin_mod = require('ex.plugin')

local M = {}

local alt_edit_bufnr = -1
local alt_edit_bufpos = {}

---Navigate to next/previous buffer
---@param cmd string Command: 'bn' or 'bp'
function M.navigate(cmd)
  if window.is_plugin_window(vim.api.nvim_get_current_win()) then
    window.goto_edit_window()
  end

  local ok, err = pcall(vim.cmd, cmd .. '!')
  if not ok then
    if err:match('E85:') then
      utils.warning('There is no listed buffer')
    end
  end
end

---Record current buffer info
function M.record()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buflisted
      and vim.api.nvim_buf_is_loaded(bufnr)
      and not plugin_mod.is_registered(bufnr) then
    alt_edit_bufnr = bufnr
    alt_edit_bufpos = vim.api.nvim_win_get_cursor(0)
  end
end

---Switch to alternate edit buffer
function M.to_alternate_edit_buf()
  if window.is_plugin_window(vim.api.nvim_get_current_win()) then
    utils.warning('Swap buffer in plugin window is not allowed!')
    return
  end

  local alt_bufnr = vim.fn.bufnr('#') -- No direct API for alternate buffer
  if vim.api.nvim_buf_is_valid(alt_bufnr)
      and vim.bo[alt_bufnr].buflisted
      and vim.api.nvim_buf_is_loaded(alt_bufnr)
      and not plugin_mod.is_registered(alt_bufnr) then

    local record_alt_bufpos = vim.deepcopy(alt_edit_bufpos)
    local record_alt_bufnr = alt_edit_bufnr
    vim.cmd('silent ' .. alt_bufnr .. 'b!')

    if alt_bufnr == record_alt_bufnr and record_alt_bufpos then
      vim.api.nvim_win_set_cursor(0, record_alt_bufpos)
    end
    return
  end

  -- Search for next listed buffer
  local cur_bufnr = vim.api.nvim_get_current_buf()
  local all_bufs = vim.api.nvim_list_bufs()

  -- Find next listed buffer after current
  for _, bufnr in ipairs(all_bufs) do
    if bufnr > cur_bufnr and vim.bo[bufnr].buflisted then
      vim.cmd('silent ' .. bufnr .. 'b!')
      return
    end
  end

  -- Wrap around: find first listed buffer
  for _, bufnr in ipairs(all_bufs) do
    if bufnr < cur_bufnr and vim.bo[bufnr].buflisted then
      vim.cmd('silent ' .. bufnr .. 'b!')
      return
    end
  end

  local alt_name = vim.api.nvim_buf_get_name(alt_bufnr)
  utils.warning("Can't swap to buffer " .. vim.fs.basename(alt_name) .. ', buffer not listed.')
end

---Delete buffer while keeping window open
function M.keep_window_bd()
  if window.is_plugin_window(vim.api.nvim_get_current_win()) then
    utils.warning("Can't close plugin window by <Leader>bd")
    return
  end

  -- Check if scratch buffer
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == '' and vim.bo.bufhidden == 'delete' and vim.bo.buftype == 'nofile' then
    return
  end

  if vim.bo.modified then
    utils.warning('Can not close: The buffer is unsaved.')
    return
  end

  local bd_bufnr = vim.api.nvim_get_current_buf()
  local cur_win = vim.api.nvim_get_current_win()

  -- Count listed buffers
  local buflisted_left = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= bd_bufnr and vim.bo[bufnr].buflisted then
      buflisted_left = buflisted_left + 1
    end
  end

  if buflisted_left == 0 then
    vim.cmd('enew')
    local new_buf = vim.api.nvim_get_current_buf()
    vim.bo[new_buf].buflisted = true
    vim.bo[new_buf].bufhidden = 'delete'
    vim.bo[new_buf].buftype = 'nofile'
    vim.bo[new_buf].swapfile = false
    vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, {'this is the scratch buffer'})

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not window.is_plugin_window(win) then
        vim.api.nvim_win_set_buf(win, new_buf)
      end
    end
  else
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not window.is_plugin_window(win) and vim.api.nvim_win_get_buf(win) == bd_bufnr then
        vim.api.nvim_set_current_win(win)
        local prevbuf = vim.fn.bufnr('#') -- No direct API
        if prevbuf > 0 and vim.bo[prevbuf].buflisted and prevbuf ~= bd_bufnr then
          vim.cmd('b #')
        else
          vim.cmd('bn')
        end
      end
    end
  end

  vim.api.nvim_set_current_win(cur_win)
  vim.api.nvim_buf_delete(bd_bufnr, {force = true})
end

return M
