-- ex plugin initialization
-- This file replaces the old plugin/init.vim

if vim.g.loaded_ex then
  return
end
vim.g.loaded_ex = 1

-- Check Neovim version (require 0.8+)
if vim.fn.has('nvim-0.8') == 0 then
  vim.api.nvim_echo({{"ex requires Neovim 0.8 or higher", "ErrorMsg"}}, true, {})
  return
end

-- Setup the plugin with default configuration
require('ex').setup()
