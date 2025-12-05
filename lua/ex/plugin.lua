-- Plugin registration system

local M = {}

---@class PluginRule
---@field bufname? string Pattern to match buffer name
---@field buftype? string Buffer type to match
---@field [string] any Other buffer options to match

---@type table<string, PluginRule[]>
local registered_plugins = {}

---Register a plugin with specific buffer characteristics
---@param filetype string Filetype to register (can be empty)
---@param options PluginRule Options to check for plugin identification
function M.register(filetype, options)
  local ft = filetype
  if ft == '' then
    ft = '__EMPTY__'
  end

  if not registered_plugins[ft] then
    registered_plugins[ft] = {}
  end

  if next(options) ~= nil then
    table.insert(registered_plugins[ft], options)
  end
end

---Check if buffer is a registered plugin buffer
---@param bufnr number Buffer number
---@return boolean
function M.is_registered(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local ft = vim.bo[bufnr].filetype

  if ft == '' then
    ft = '__EMPTY__'
  end

  if not registered_plugins[ft] then
    return false
  end

  local rules = registered_plugins[ft]
  if #rules == 0 then
    return true
  end

  for _, rule in ipairs(rules) do
    local failed = false

    for key, value in pairs(rule) do
      if key == 'bufname' then
        if not bufname:match(value) then
          failed = true
          break
        end
      else
        local buf_option = vim.bo[bufnr][key]
        if buf_option ~= value then
          failed = true
          break
        end
      end
    end

    if not failed then
      return true
    end
  end

  return false
end

---Echo registered plugins for debugging
function M.echo_registered()
  print('List of registered plugins:')
  for ft, rules in pairs(registered_plugins) do
    if #rules == 0 then
      print(ft .. ': {}')
    else
      for _, rule in ipairs(rules) do
        print(ft .. ': ' .. vim.inspect(rule))
      end
    end
  end
end

return M
