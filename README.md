# overlook.nvim

A Neovim plugin that provides floating popup windows for peeking at code locations without losing your current context. Inspired by [lspsaga.nvim](https://github.com/nvimdev/lspsaga.nvim)'s peek_definition feature, `overlook.nvim` takes the concept further by building a complete popup solution around it.

## Demo

[Video placeholder - Demo of overlook.nvim in action]

## Features

- 🔍 **Peek at definitions** - View LSP definitions in floating windows
- ✏️ **Editable popups** - All popups are fully modifiable buffers, perfect for quick edits
- 📚 **Stack management** - Stacks of popups are window-local, multiple stacks are allowed
- 🔄 **Restore popups** - Undo closed popups
- 🪟 **Window promotion** - Convert popups to regular splits/tabs
- ⚙️ **Highly customizable** - Configure borders, sizes, offsets, and keybindings

## Why overlook.nvim?

I loved lspsaga's peek_definition feature so much that I decided to extract and expand upon it as a dedicated plugin. The core philosophy is that **popups should behave exactly like normal buffers** - you can navigate, edit, save, and do anything you would in a regular window. This makes it perfect for:

- Making quick fixes without losing your context
- Exploring codebases by following definition to create nested popups
- Visually backtrace-able modification history

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "WilliamHsieh/overlook.nvim",
  opts = {},
}
```

## Setup

```lua
require("overlook").setup({
  -- UI settings for popup windows
  ui = {
    border = "rounded",              -- Border style: "none", "single", "double", "rounded", etc.
    z_index_base = 30,              -- Base z-index for first popup
    row_offset = 2,                 -- Initial row offset from cursor
    col_offset = 5,                 -- Initial column offset from cursor
    stack_row_offset = 1,           -- Vertical offset for stacked popups
    stack_col_offset = 2,           -- Horizontal offset for stacked popups
    width_decrement = 2,            -- Width reduction for each stacked popup
    height_decrement = 1,           -- Height reduction for each stacked popup
    min_width = 10,                 -- Minimum popup width
    min_height = 3,                 -- Minimum popup height
    size_ratio = 0.65,              -- Default size ratio (0.0 to 1.0)
    keys = {
      close = "q",                  -- Key to close the topmost popup
    },
  },

  -- Adapter configurations
  adapters = {
    marks = {},                     -- Marks adapter config
  },

  -- Optional callback when all popups are closed
  on_stack_empty = function()
    -- Your custom logic here
  end,
})
```

## Usage

### Keybindings

Set up your preferred keybindings:

```lua
vim.keymap.set("n", "<leader>pd", require("overlook.api").peek_definition, { desc = "Peek definition" })
vim.keymap.set("n", "<leader>pp", require("overlook.api").peek_cursor, { desc = "Peek cursor" })
vim.keymap.set("n", "<leader>pu", require("overlook.api").restore_popup, { desc = "Restore last popup" })
vim.keymap.set("n", "<leader>pU", require("overlook.api").restore_all_popups, { desc = "Restore all popups" })
vim.keymap.set("n", "<leader>pc", require("overlook.api").close_all, { desc = "Close all popups" })
vim.keymap.set("n", "<leader>ps", require("overlook.api").open_in_split, { desc = "Open popup in split" })
vim.keymap.set("n", "<leader>pv", require("overlook.api").open_in_vsplit, { desc = "Open popup in vsplit" })
vim.keymap.set("n", "<leader>pt", require("overlook.api").open_in_tab, { desc = "Open popup in tab" })
vim.keymap.set("n", "<leader>po", require("overlook.api").open_in_original_window, { desc = "Open popup in current window" })
```

### API Functions

- `peek_definition()` - Peek at the LSP definition under cursor
- `peek_cursor()` - Create a popup at current cursor position
- `peek_mark()` - Prompt for a mark and peek at its location
- `restore_popup()` - Restore the last closed popup
- `restore_all_popups()` - Restore all closed popups
- `close_all()` - Close all overlook popups
- `open_in_split()` - Promote popup to horizontal split
- `open_in_vsplit()` - Promote popup to vertical split
- `open_in_tab()` - Promote popup to new tab
- `open_in_original_window()` - Replace current window with popup content

### Working with Popups

Popups in overlook.nvim are **fully functional buffers**, you can:

- Edit content directly in the popup
- Save changes with `:w`
- Use all your normal keybindings and commands
- Navigate with LSP goto definition to create nested popups

> **Tip:** Press `q` inside any popup to close it and return to your previous context.

## Acknowledgments

Special thanks to the [lspsaga.nvim](https://github.com/nvimdev/lspsaga.nvim) project for the original peek_definition implementation that inspired this plugin.