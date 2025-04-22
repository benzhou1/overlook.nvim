local M = {}

-- Default configuration options for overlook.nvim
M.options = {
  -- UI settings for the popup windows
  ui = {
    -- Border style for popups. Accepts same values as nvim_open_win's 'border' option
    -- (e.g., 'none', 'single', 'double', 'rounded', 'solid', 'shadow').
    border = "rounded",

    -- Base z-index for the first popup. Subsequent popups increment from here.
    -- Higher values appear visually on top. Should be high enough to be above normal floats.
    z_index_base = 100,

    -- Default maximum width for the *first* popup. Actual size also depends on content and editor size.
    default_width = 80,

    -- Default maximum height for the *first* popup. Actual size also depends on content and editor size.

    default_height = 15,

    -- Initial row offset relative to the cursor for the *first* popup.
    -- 1 means one row below the cursor. Negative values mean above.
    row_offset = 1,
    -- Initial column offset relative to the cursor for the *first* popup.
    -- 0 means starting at the cursor column.
    col_offset = 0,

    -- Row offset for subsequent stacked popups relative to the previous popup's top-left corner.
    -- 1 means the next popup starts 1 row below the previous one.
    stack_row_offset = 0,
    -- Column offset for subsequent stacked popups relative to the previous popup's top-left corner.
    -- 1 means the next popup starts 1 column to the right of the previous one.
    stack_col_offset = 0,

    -- Amount by which the width decreases for each subsequent popup in the stack.
    width_decrement = 2,
    -- Amount by which the height decreases for each subsequent popup in the stack.
    height_decrement = 1,

    -- Minimum allowed width for any popup window, prevents shrinking to zero.
    min_width = 10,
    -- Minimum allowed height for any popup window (must be >= 3 for border+title+content).
    min_height = 3,
  },

  -- Adapter-specific configurations

  adapters = {
    -- Configuration for the 'marks' adapter
    marks = {
      -- Filetype to potentially set (less relevant now we show the actual buffer,
      -- but could be used by future adapters creating scratch buffers).
      filetype = "markdown",
    },
    -- lsp = {}, -- Placeholder for future LSP adapter config
    -- other_adapter = {}, -- Placeholder
  },
}

-- Merges user-provided options with the defaults.
-- Called from require('overlook').setup(opts) in user's config.
---@param user_opts? table User configuration options passed from their setup call.
function M.setup(user_opts)
  if user_opts then
    -- Use deep_extend to merge nested tables like 'ui' and 'adapters'.
    -- 'force' mode replaces arrays entirely if present, usually desired for config.
    M.options = vim.tbl_deep_extend("force", M.options, user_opts or {})
  end
  -- You could add validation for option values here later if needed.
  -- For example, ensure min_width is less than default_width.
end

-- Returns the currently active configuration table.
-- Primarily for internal use by other plugin modules via require('overlook.config').get()
-- or directly via require('overlook.config').options if setup timing is guaranteed.
function M.get()
  return M.options
end

return M
