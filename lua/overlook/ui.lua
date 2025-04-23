local api = vim.api
local M = {}

-- Cache required modules

local config_mod ---@type table | nil
local stack_mod ---@type table | nil
local function config()
  if not config_mod then
    config_mod = require("overlook.config")
  end
  return (config_mod and config_mod.options and config_mod.options.ui) or {}
end
local function stack()
  if not stack_mod then
    stack_mod = require("overlook.stack")
  end
  return stack_mod
end

local group_id = api.nvim_create_augroup("OverlookPopupClose", { clear = true })

-- Define common border characters directly
local border_definitions = {
  none = { "", "", "", "", "", "", "", "" },
  single = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
  double = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
  rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
  solid = { "█", "█", "█", "█", "█", "█", "█", "█" },
  shadow = { " ", " ", " ", " ", "▀", "▀", "▀", " " },
}

---Creates and opens a floating window viewing the target buffer.
---@param opts table Options: { target_bufnr: integer, lnum: integer, col: integer, title?: string }
---@return { win_id: integer, buf_id: integer } | nil
function M.create_popup(opts)
  opts = opts or {}
  if not (opts.target_bufnr and opts.lnum and opts.col) then
    return nil
  end
  local target_bufnr = opts.target_bufnr
  local lnum = opts.lnum
  local col = opts.col
  local ui_opts = config()
  -- local title = opts.title or "" -- Title not used in this debug version
  if not api.nvim_buf_is_valid(target_bufnr) then
    return nil
  end

  -- 1. Calculate Window Config
  local win_config = { relative = "editor", style = "minimal", focusable = true }
  local current_stack_size = stack().size()
  win_config.zindex = (ui_opts.z_index_base or 100) + current_stack_size

  local width, height, row, col_abs

  -- Fallback defaults for config values
  local min_h = ui_opts.min_height or 3
  local def_h = ui_opts.default_height or 15

  local min_w = ui_opts.min_width or 10
  local def_w = ui_opts.default_width or 80
  local row_off = ui_opts.row_offset or 1
  local col_off = ui_opts.col_offset or 0
  local w_dec = ui_opts.width_decrement or 2

  local h_dec = ui_opts.height_decrement or 1
  local stack_r_off = ui_opts.stack_row_offset or 1
  local stack_c_off = ui_opts.stack_col_offset or 1
  -- local border_style = ui_opts.border or "rounded" -- Not used in this debug version

  if current_stack_size == 0 then
    -- First popup: Position relative to the CURRENT window, directly below the cursor screen position
    local current_win_id = api.nvim_get_current_win()
    local cursor_buf_pos = api.nvim_win_get_cursor(current_win_id) -- {row, col} 1-based row, 0-based col

    -- Get the absolute screen position of the cursor in the current window
    -- screenpos() returns 1-based {row, col}, needs 1-based col input
    local cursor_abs_screen_pos = vim.fn.screenpos(current_win_id, cursor_buf_pos[1], cursor_buf_pos[2] + 1)

    -- Get the top-left screen position of the current window (0-based)
    local win_pos = api.nvim_win_get_position(current_win_id) -- {row, col} 0-based

    -- Calculate the cursor's screen position relative to the window's top-left (0-based)
    local cursor_relative_screen_row = cursor_abs_screen_pos.row - win_pos[1] - 1
    local cursor_relative_screen_col = cursor_abs_screen_pos.col - win_pos[2] - 1

    win_config.relative = "win"
    win_config.win = current_win_id
    -- Place the popup's top edge on the same screen row as the cursor (0-based offset)
    win_config.row = cursor_relative_screen_row
    -- Align the popup's left edge with the cursor's screen column (0-based offset)
    win_config.col = cursor_relative_screen_col

    local max_editor_height =
      math.max(1, api.nvim_get_option_value("lines", {}) - api.nvim_get_option_value("cmdheight", {}) - 2)
    local max_editor_width = math.max(1, api.nvim_get_option_value("columns", {}) - 4)
    height = math.max(min_h, math.min(max_editor_height, def_h))
    width = math.max(min_w, math.min(max_editor_width, def_w))

    win_config.width = width
    win_config.height = height
    -- Updated Debug Log reflects the screen coordinate calculation
    vim.notify(
      string.format(
        "Overlook Debug: First Popup Calculated Initial Geom (Win Relative %d, On Cursor Screen Row): w=%d h=%d rel_r=%d rel_c=%d",
        current_win_id,
        width,
        height,
        win_config.row,
        win_config.col
      ),
      vim.log.levels.DEBUG
    ) -- DEBUG Updated Log
  else
    -- Subsequent popups
    local prev = stack().top()

    if not prev or prev.width == nil or prev.height == nil or prev.row == nil or prev.col == nil then
      vim.notify("Overlook Internal Error: Invalid previous popup state.", vim.log.levels.ERROR)
      return nil
    end

    vim.notify("Overlook Debug: Previous Popup Geom: " .. vim.inspect(prev), vim.log.levels.DEBUG) -- DEBUG

    -- *** MODIFIED SECTION START ***
    -- Position subsequent popups relative to the PREVIOUS popup window
    win_config.relative = "win"
    win_config.win = prev.win_id -- Specify the anchor window

    width = math.max(min_w, prev.width - w_dec)
    height = math.max(min_h, prev.height - h_dec)

    -- Row and Col are now offsets RELATIVE to the previous window
    row = stack_r_off - (vim.o.winbar and 1 or 0) -- Adjust for winbar if enabled
    col_abs = stack_c_off

    win_config.width = width + 1
    win_config.height = height
    win_config.row = row
    win_config.col = col_abs
    -- Restore log to reflect using configured offsets
    vim.notify(
      string.format(
        "Overlook Debug: Subsequent Popup Calculated Geom (Relative to Win %d): w=%d h=%d rel_r=%d rel_c=%d",
        prev.win_id,
        width,
        height,
        row,
        col_abs
      ),
      vim.log.levels.DEBUG
    )
    -- *** MODIFIED SECTION END ***
  end

  -- *** Force simple border for testing ***
  -- win_config.border = format_border_with_title(border_style, title, win_config.width) -- TITLE FORMATTING DISABLED
  win_config.border = border_definitions.single -- FORCE simple single border
  win_config.title = opts.title or "default title"
  win_config.title_pos = "center"

  local original_win_id = nil
  if stack().size() == 0 then
    original_win_id = vim.api.nvim_get_current_win()
  end

  vim.notify("Overlook Debug: Using FORCED simple border.", vim.log.levels.WARN) -- DEBUG
  vim.notify("Overlook Debug: Win Config Before Open: " .. vim.inspect(win_config), vim.log.levels.DEBUG) -- DEBUG

  -- 2. Open Window
  local pre_open_win_id = api.nvim_get_current_win()
  local win_id = api.nvim_open_win(target_bufnr, true, win_config)
  if not win_id or win_id == 0 then
    vim.notify("Overlook Error: Failed to open window.", vim.log.levels.ERROR)
    if api.nvim_win_is_valid(pre_open_win_id) then
      api.nvim_set_current_win(pre_open_win_id)
    end
    return nil
  end

  -- 3. Post-Open Setup
  api.nvim_win_set_cursor(win_id, { lnum, math.max(0, col - 1) })
  vim.api.nvim_win_call(win_id, function()
    vim.cmd("normal! zz")
  end)

  -- 4. Get final geometry and check validity
  local final_config = api.nvim_win_get_config(win_id)
  vim.notify("Overlook Debug: Final Config Received After Open: " .. vim.inspect(final_config), vim.log.levels.DEBUG) -- DEBUG
  if final_config and final_config.width and final_config.height and final_config.row and final_config.col then
    width = final_config.width
    height = final_config.height
    row = math.floor(final_config.row)
    col_abs = math.floor(final_config.col)
  else
    vim.notify("Overlook Warn: Could not get final window geometry. Using calculated values.", vim.log.levels.WARN)
    if width == nil or height == nil or row == nil or col_abs == nil then
      vim.notify("Overlook Error: Geometry unavailable. Aborting popup.", vim.log.levels.ERROR)
      if api.nvim_win_is_valid(win_id) then
        api.nvim_win_close(win_id, true)
      end
      if api.nvim_win_is_valid(pre_open_win_id) then
        api.nvim_set_current_win(pre_open_win_id)
      end
      return nil
    end
  end
  vim.notify(
    string.format(
      "Overlook Debug: Geometry to Store: w=%s h=%s r=%s c=%s",
      tostring(width),
      tostring(height),
      tostring(row),
      tostring(col_abs)
    ),
    vim.log.levels.DEBUG
  ) -- DEBUG

  -- 5. Add to Stack
  stack().push {
    win_id = win_id,
    buf_id = target_bufnr,
    z_index = win_config.zindex,
    width = width,
    height = height,
    row = row,
    col = col_abs,
    original_win_id = original_win_id,
  }

  -- 6. Setup WinClosed Autocommand
  api.nvim_create_autocmd("WinClosed", {
    group = group_id,
    pattern = tostring(win_id),
    once = true,
    callback = function(args)
      if tonumber(args.match) == win_id then
        vim.schedule(function()
          require("overlook.stack").handle_win_close(win_id)
        end)
      end
    end,
  })

  return { win_id = win_id, buf_id = target_bufnr }
end

return M
