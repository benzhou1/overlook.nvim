local api = vim.api
local M = {}

-- Cache required modules

local config_mod ---@type table | nil
local stack_mod ---@type table | nil
local function config() -- Revert to only return ui options
  if not config_mod then
    config_mod = require("overlook.config")
  end
  return (config_mod and config_mod.options and config_mod.options.ui)
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
  local ui_opts = config() -- Revert to getting only ui_opts
  if not api.nvim_buf_is_valid(opts.target_bufnr) then
    return nil
  end

  -- 1. Calculate Window Config
  local win_config = { relative = "editor", style = "minimal", focusable = true }
  local current_stack_size = stack().size()
  win_config.zindex = ui_opts.z_index_base + current_stack_size

  local width, height, row, col_abs

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
    win_config.row = cursor_relative_screen_row + ui_opts.row_offset
    -- Align the popup's left edge with the cursor's screen column (0-based offset)
    win_config.col = cursor_relative_screen_col + ui_opts.col_offset

    local max_editor_height =
      math.max(1, api.nvim_get_option_value("lines", {}) - api.nvim_get_option_value("cmdheight", {}) - 2)
    local max_editor_width = math.max(1, api.nvim_get_option_value("columns", {}) - 4)
    height = math.max(ui_opts.min_height, math.min(max_editor_height, ui_opts.default_height))
    width = math.max(ui_opts.min_width, math.min(max_editor_width, ui_opts.default_width))

    win_config.width = width
    win_config.height = height
  else
    -- Subsequent popups
    local prev = stack().top()

    if not prev or prev.width == nil or prev.height == nil or prev.row == nil or prev.col == nil then
      vim.notify("Overlook Internal Error: Invalid previous popup state.", vim.log.levels.ERROR)
      return nil
    end

    win_config.relative = "win"
    win_config.win = prev.win_id -- Specify the anchor window

    width = math.max(ui_opts.min_width, prev.width - ui_opts.width_decrement)
    height = math.max(ui_opts.min_height, prev.height - ui_opts.height_decrement)

    -- Row and Col are now offsets RELATIVE to the previous window
    row = ui_opts.stack_row_offset - (vim.o.winbar and 1 or 0) -- Adjust for winbar if enabled
    col_abs = ui_opts.stack_col_offset

    win_config.width = width + 1
    win_config.height = height
    win_config.row = row
    win_config.col = col_abs
  end

  win_config.border = border_definitions[ui_opts.border] or border_definitions.single
  win_config.title = opts.title or "default title"
  win_config.title_pos = "center"

  local original_win_id = nil
  if stack().size() == 0 then
    original_win_id = vim.api.nvim_get_current_win()
  end

  -- 2. Open Window
  local pre_open_win_id = api.nvim_get_current_win()
  local win_id = api.nvim_open_win(opts.target_bufnr, true, win_config)
  if not win_id or win_id == 0 then
    vim.notify("Overlook Error: Failed to open window.", vim.log.levels.ERROR)
    if api.nvim_win_is_valid(pre_open_win_id) then
      api.nvim_set_current_win(pre_open_win_id)
    end
    return nil
  end

  -- 3. Post-Open Setup
  api.nvim_win_set_cursor(win_id, { opts.lnum, math.max(0, opts.col - 1) })
  vim.api.nvim_win_call(win_id, function()
    vim.cmd("normal! zz")
  end)

  -- 4. Get final geometry and check validity
  local final_config = api.nvim_win_get_config(win_id)
  if final_config and final_config.width and final_config.height and final_config.row and final_config.col then
    width = final_config.width
    height = final_config.height
    row = math.floor(final_config.row)
    col_abs = math.floor(final_config.col)
  else
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

  -- 5. Add to Stack
  stack().push {
    win_id = win_id,
    buf_id = opts.target_bufnr,
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

  return { win_id = win_id, buf_id = opts.target_bufnr }
end

return M
