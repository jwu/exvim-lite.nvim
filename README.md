# exvim-lite.nvim

A lightweight Neovim plugin for project management, written in pure Lua.

exvim-lite reads your `.exvim` folder and applies project-specific settings, file organization, and fast searching capabilities.

## Requirements

- Neovim 0.8 or higher
- `ripgrep` (rg) for fast file searching

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'jwu/exvim-lite.nvim',
  config = function()
    require('ex').setup({
      -- Optional configuration
      project_winsize = 30,
      project_winsize_zoom = 60,
      project_winpos = 'left',  -- 'left' or 'right'
      search_winsize = 15,
      search_winsize_zoom = 40,
      search_winpos = 'bottom',  -- 'top' or 'bottom'
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'jwu/exvim-lite.nvim',
  config = function()
    require('ex').setup()
  end
}
```

## Usage

### Initialize a Project

```vim
:EXVIM [directory]
```

This creates a `.exvim/` folder in the specified directory (or current directory if not specified) with a `config.json` file.

### Configuration File

The `.exvim/config.json` file controls which files are included in your project:

```json
{
  "version": "2.0.0",
  "space": 2,
  "includes": [
    "*.c", "*.h", "*.lua", "*.py", "*.js", "*.ts", "*.vim"
  ],
  "ignores": [
    "**/.git", "**/.svn", "**/.exvim", "**/node_modules"
  ]
}
```

### Commands

**Buffer Navigation:**
- `:EXbn` - Next buffer
- `:EXbp` - Previous buffer  
- `:EXbalt` - Alternate buffer
- `:EXbd` - Delete buffer (keep window)

**Window Management:**
- `:EXsw` - Switch between edit and plugin windows
- `:EXgp` - Go to plugin window
- `:EXgc` - Close last edit plugin window

**Project Management:**
- `:EXProject [file]` - Open project window
- `:EXProjectFind [path]` - Find and highlight file/folder in project tree

**Search:**
- `:GS <pattern>` - Global search with ripgrep
- `:EXSearchCWord` - Search word under cursor

**Debug:**
- `:EXplugins` - List registered plugin windows

### Project Window Keybindings

- `<F1>` - Toggle help
- `<Space>` - Zoom in/out
- `<Enter>` - Open file or toggle folder
- `<Shift-Enter>` - Open file in split or open folder in file browser
- `<Ctrl-j/k>` - Jump to next/previous folder
- `R` - Refresh entire project
- `r` - Refresh current folder
- `o` - Create new file
- `O` - Create new folder

### Search Window Keybindings

- `<F1>` - Toggle help
- `<Space>` - Zoom in/out
- `<Enter>` - Go to search result
- `<Shift-Enter>` - Open in split window
- `<leader>r` - Filter results by pattern
- `<leader>fr` - Filter results by filename
- `<leader>d` - Reverse filter by pattern
- `<leader>fd` - Reverse filter by filename

## API

You can also use ex programmatically:

```lua
local ex = require('ex')

-- Access submodules
ex.utils.hint('Hello!')
ex.config.load('/path/to/.exvim/')
ex.buffer.navigate('bn')
ex.window.goto_edit_window()
```

## Project Structure

```
exvim-lite.nvim/
├── lua/
�?  └── ex/
�?      ├── init.lua       -- Main module & setup
�?      ├── utils.lua      -- Core utilities
�?      ├── config.lua     -- Configuration management
�?      ├── buffer.lua     -- Buffer operations
�?      ├── window.lua     -- Window management
�?      ├── plugin.lua     -- Plugin registration
�?      ├── project.lua    -- Project tree management
�?      └── search.lua     -- Search functionality
├── plugin/
�?  └── init.lua           -- Plugin initialization
├── ftplugin/              -- Filetype plugins (Lua)
├── syntax/                -- Syntax files (VimScript)
└── README.md
```

## Migration from VimScript Version

This version has been completely rewritten in Lua for better performance and maintainability. If you're upgrading from the old VimScript version:

1. The plugin name remains `exvim-lite.nvim`
2. All commands work the same way
3. Configuration is now done through `setup()` function
4. Core functionality is exposed through Lua API
5. Requires Neovim 0.8+ (no Vim support)

## License

MIT License - see LICENSE file for details
