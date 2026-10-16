# overlook.nvim

Explore without losing context. Stackable, editable floating popups for Neovim.

## Demo

https://github.com/user-attachments/assets/ac784f7e-e4ad-45be-b2f5-60e8318c8089

## The Problem

You know the frustration: you're deep in a function, need to check a definition, so you jump to it... and now you've lost your place.
Or you use a peek feature but can't fix that typo you just spotted.

## The Solution

`overlook.nvim` creates **stackable floating popups** that are **actual buffers** - edit them, save them, navigate from them. Build a visual trail of your code exploration without ever losing where you started.

## Key Features

- 🔍 **Peek at definitions** - View LSP definitions, marks, or any location in floating windows
- ✏️ **Actually editable** - Spot a bug? Fix it right there in the popup and `:w` to save
- 📚 **Visual stack navigation** - See your entire exploration path as cascading popups
- 🔄 **Undo your exploration** - Accidentally closed a popup? Bring it back with `restore_popup()`
- 🪟 **Popup promotion** - Found something important? Convert any popup to a split/tab
- 🎯 **Window-local stacks** - Each window maintains its own popup stack for parallel exploration

## Why overlook.nvim?

The core philosophy is simple: **popups are buffers**. Everything else follows from that one decision. Because a popup is a real buffer in a real window, it is editable and saveable; every keybinding, plugin, and picker you already have works inside it; it can host the *next* peek (which is why popups stack); and when a quick glance turns into real work, it can be promoted to a split or tab. There is nothing special to learn - it behaves exactly like any other window.

### Real-world use cases:

1. **Trace through call chains**: Peek definition → find another reference → peek again → you now have a visual stack showing your exploration path
2. **Fix as you explore**: Reviewing a function and spot a typo? Fix it in the popup and save - no context switching needed
3. **Visual debugging**: Build a breadcrumb trail of function calls while stepping through the code

### What makes it different:

- All your keybindings work normally in popups
- Switch buffers inside popups - `:bnext`, `<C-^>`, telescope/fzf all work
- Popups automatically offset and resize to stay readable when stacked
- Full undo/redo support for your exploration history

## Requirements

- Neovim >= 0.11 (CI tests against 0.11.x and nightly)
- An LSP client only for `peek_definition()` - `peek()`, `peek_cursor()`, and `peek_mark()` need nothing extra
- No external dependencies

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "WilliamHsieh/overlook.nvim",
  opts = {},

  -- Optional: set up common keybindings
  keys = {
    { "<leader>pd", function() require("overlook.api").peek_definition() end, desc = "Overlook: Peek definition" },
    { "<leader>pc", function() require("overlook.api").close_all() end, desc = "Overlook: Close all popup" },
    { "<leader>pu", function() require("overlook.api").restore_popup() end, desc = "Overlook: Restore popup" },
  },
}
```

## Quick Start

1. Install the plugin with your favorite package manager
2. Add a keybinding for `peek_definition()`
3. Navigate to any symbol and trigger the peek
4. Edit the popup content if needed
5. Press `q` to close or continue exploring

That's it! No complex setup required.

## Configuration

`overlook.nvim` works out of the box with sensible defaults - `opts = {}` is all you need. Pass a table to `setup()` to override only the pieces you care about. The example below sets non-default values to illustrate the shape:

```lua
require("overlook").setup({
  -- Overrides (not defaults) - shown to illustrate the shape
  ui = {
    border = "single",  -- default is "rounded"
    size_ratio = 0.8,   -- default is 0.65
  },

  -- Run custom logic when the last popup in a stack closes
  on_stack_empty = function()
    -- Your custom logic here
  end,
})
```

The full, always-current list of options and their defaults lives in `:h overlook-config` - it is generated from the source annotations, so it can't drift out of sync.

## Usage

### Essential keybindings

```lua
vim.keymap.set("n", "<leader>pd", require("overlook.api").peek_definition, { desc = "Peek definition" })
vim.keymap.set("n", "<leader>pp", require("overlook.api").peek_cursor, { desc = "Peek cursor" })
vim.keymap.set("n", "<leader>pu", require("overlook.api").restore_popup, { desc = "Restore last popup" })
vim.keymap.set("n", "<leader>pU", require("overlook.api").restore_all_popups, { desc = "Restore all popups" })
vim.keymap.set("n", "<leader>pc", require("overlook.api").close_all, { desc = "Close all popups" })
vim.keymap.set("n", "<leader>pf", require("overlook.api").switch_focus, { desc = "Switch focus" })
vim.keymap.set("n", "<leader>ps", require("overlook.api").open_in_split, { desc = "Open popup in split" })
vim.keymap.set("n", "<leader>pv", require("overlook.api").open_in_vsplit, { desc = "Open popup in vsplit" })
vim.keymap.set("n", "<leader>pt", require("overlook.api").open_in_tab, { desc = "Open popup in tab" })
vim.keymap.set("n", "<leader>po", require("overlook.api").open_in_original_window, { desc = "Open popup in current window" })
```

### API Functions

Check `:h overlook-api` for more details.

- `peek_definition()` - Peek at the LSP definition under cursor
- `peek_cursor()` - Create a popup at current cursor position
- `peek_mark()` - Prompt for a mark and peek at its location
- `peek(item)` - Peek at an LSP location, quickfix entry, or buffer you already have
- `restore_popup()` - Restore the last closed popup
- `restore_all_popups()` - Restore all closed popups
- `close_all()` - Close all overlook popups
- `switch_focus()` - Switch focus between popups and root window
- `open_in_split()` - Promote popup to horizontal split
- `open_in_vsplit()` - Promote popup to vertical split
- `open_in_tab()` - Promote popup to new tab
- `open_in_original_window()` - Replace current window with popup content

### Peek a specific location

`peek(item)` opens a popup at a location you already have. Call it from an LSP `on_list` callback when you want to pick the result yourself, or from any picker. The item may be:

- a quickfix entry (`filename` or `bufnr`, plus `lnum` / `col`) — the shape `vim.lsp.buf.definition({ on_list = ... })` puts in `opts.items`. The original LSP location, when present, is read from `user_data`
- an LSP location (`uri` + `range`) or location link (`targetUri` + `targetSelectionRange`)
- a buffer number (`bufnr` + `lnum` / `col`)

A `uri` is resolved with `vim.uri_to_bufnr`. `lnum` / `col` are 1-based. An LSP `range` is 0-based and is used only when `lnum` is absent. An item that does not identify a buffer and a position notifies and opens nothing.

```lua
-- Pick one LSP definition, then peek it.
vim.lsp.buf.definition({
  on_list = function(opts)
    vim.ui.select(opts.items, {
      prompt = opts.title or "Peek definition",
      format_item = function(item)
        return string.format("%s:%s:%s", item.filename or "", item.lnum or "", item.col or "")
      end,
    }, function(item)
      if item then
        require("overlook.api").peek(item)
      end
    end)
  end,
})
```

```lua
-- Peek somewhere you already know, without an LSP request.
require("overlook.api").peek({
  filename = "lua/overlook/api.lua",
  lnum = 1,
  col = 1,
})
```

`peek_definition()`, `peek_cursor()`, and `peek_mark()` behave exactly as before.

## Writing a custom peek source

A peek source is just a function: gather whatever context you need, build an options table, and call `require("overlook.window").open_popup(...)`. There is no registration step - once you have the function, bind it to a key exactly like any built-in.

```lua
local function peek_alternate_file()
  local alt = vim.fn.bufnr("#") -- the alternate buffer
  if alt == -1 then
    return vim.notify("Overlook: no alternate buffer", vim.log.levels.WARN)
  end
  require("overlook.window").open_popup({
    target_bufnr = alt,
    lnum = 1,
    col = 1,
    title = vim.fn.bufname(alt),
  })
end

vim.keymap.set("n", "<leader>pa", peek_alternate_file, { desc = "Peek alternate file" })
```

Async sources (LSP, pickers) work the same way - they just call `open_popup` later from their own callback. If the source already has an LSP location or a quickfix entry, `require("overlook.api").peek(item)` does the buffer lookup for you; see [Peek a specific location](#peek-a-specific-location). `:h overlook-peek` is the full contract, and `overlook.peek.*` holds the built-in examples.

## Development

- `make test` - run the plenary test suite
- `make vimdoc` - regenerate `doc/` from the source annotations (never edit `doc/*.txt` by hand)
- [stylua](https://github.com/JohnnyMorganz/StyLua) - format Lua code

## Acknowledgments

Special thanks to the [lspsaga.nvim](https://github.com/nvimdev/lspsaga.nvim) project for the original `peek_definition` implementation that inspired this plugin.
