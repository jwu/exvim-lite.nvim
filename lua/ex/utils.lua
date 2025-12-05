-- Core utilities module for exvim-lite

local M = {}

-- Platform-specific path separator
M.sep = package.config:sub(1, 1)

-- Cache platform detection
local sysname = vim.uv.os_uname().sysname

---Check if running on Windows
---@return boolean
function M.is_windows()
  return sysname:find('Windows') ~= nil
end

---Check if running on macOS
---@return boolean
function M.is_mac()
  return sysname == 'Darwin'
end

---Check if running on Linux
---@return boolean
function M.is_linux()
  return sysname == 'Linux'
end

---Display hint message
---@param msg string
function M.hint(msg)
  vim.api.nvim_echo({{msg, 'ModeMsg'}}, false, {})
end

---Display warning message
---@param msg string
function M.warning(msg)
  vim.api.nvim_echo({{msg, 'WarningMsg'}}, false, {})
end

---Display error message
---@param msg string
function M.error(msg)
  vim.api.nvim_echo({{'Error(exVim): ' .. msg, 'ErrorMsg'}}, false, {})
end

---Display debug message
---@param msg string
function M.debug(msg)
  local info = debug.getinfo(2, 'Sl')
  local location = info.short_src .. ':' .. info.currentline
  vim.api.nvim_echo({{'Debug(exVim): ' .. msg .. ', ' .. location, 'Special'}}, false, {})
end

---Shorten message to fit in command line
---@param msg string
---@return string
function M.short_message(msg)
  local cols = vim.o.columns
  if #msg <= cols - 13 then
    return msg
  end

  local len = math.floor((cols - 13 - 3) / 2)
  return msg:sub(1, len) .. '...' .. msg:sub(-len)
end

---Clear target highlight
function M.hl_clear_target()
  vim.fn.matchdelete(vim.w.ex_target_match or -1)
  vim.w.ex_target_match = nil
end

---Highlight target line
---@param linenr number
function M.hl_target_line(linenr)
  M.hl_clear_target()

  local pattern = [[\%]] .. linenr .. [[l.*]]
  vim.w.ex_target_match = vim.fn.matchadd('EX_TARGET_LINE', pattern)
end

---Clear confirm highlight
function M.hl_clear_confirm()
  vim.fn.matchdelete(vim.w.ex_confirm_match or -1)
  vim.w.ex_confirm_match = nil
end

---Highlight confirm line
---@param linenr number
function M.hl_confirm_line(linenr)
  M.hl_clear_confirm()

  local pattern = [[\%]] .. linenr .. [[l.*]]
  vim.w.ex_confirm_match = vim.fn.matchadd('EX_CONFIRM_LINE', pattern)
end

---Get OS-specific path separator
---@return string
function M.os_sep()
  return M.sep
end

---Normalize path to absolute path
---@param path string
---@return string
function M.normalize_path(path)
  return vim.fs.normalize(path)
end

---Get relative path from cwd
---@param path string
---@return string
function M.relative_path(path)
  local abs_path = vim.fs.normalize(path)
  local cwd = vim.uv.cwd()
  
  -- Ensure both paths end without separator for comparison
  if abs_path:sub(-1) == M.sep then
    abs_path = abs_path:sub(1, -2)
  end
  if cwd:sub(-1) == M.sep then
    cwd = cwd:sub(1, -2)
  end

  -- If path starts with cwd, make it relative
  if abs_path:sub(1, #cwd) == cwd then
    local rel = abs_path:sub(#cwd + 2) -- +2 to skip the separator
    return rel ~= '' and rel or '.'
  end

  return abs_path
end

---Get file extension
---@param path string
---@return string
function M.get_extension(path)
  local basename = vim.fs.basename(path)
  local ext = basename:match('%.([^%.]+)$')
  return ext or ''
end

return M
