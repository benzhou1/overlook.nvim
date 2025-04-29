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

-- Access the tracker (needs modification in stack.lua if not exposed)
-- For now, assume stack() returns the module table including the tracker for simplicity
-- A better approach might be dedicated functions in stack.lua like stack.increment_keymap_refcount(bufnr)
-- and stack.set_initial_keymap(bufnr, key, ...) etc.
-- Let's require stack explicitly to call potentially new functions if needed.
local stack_module = require("overlook.stack")

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
  local win_config = { relative = "win", style = "minimal", focusable = true }
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

    win_config.win = current_win_id
    win_config.col = cursor_relative_screen_col + ui_opts.col_offset

    -- Calculate max window dimensions accurately
    local max_window_height = api.nvim_win_get_height(current_win_id)
    local max_window_width = api.nvim_win_get_width(current_win_id)

    -- Adjust available space/fittable size calculation based on accurate max_editor_height
    local place_above = cursor_relative_screen_row > max_window_height / 2

    -- 2. Calculate Available Space based on placement
    local screen_space_above = cursor_relative_screen_row
    local screen_space_below = max_window_height - cursor_relative_screen_row
    -- Subtract 2 from width for potential borders/padding
    local screen_space_right = max_window_width - cursor_relative_screen_col - 2
    local border_vertical_overhead = 2 -- Assume 1 row top border, 1 row bottom border
    local border_horizontal_overhead = 2 -- Assume 1 col left, 1 col right

    local max_fittable_content_height
    if place_above then
      max_fittable_content_height = math.max(0, screen_space_above - border_vertical_overhead)
    else
      max_fittable_content_height = math.max(0, screen_space_below - border_vertical_overhead)
    end
    local max_fittable_content_width = math.max(0, screen_space_right - border_horizontal_overhead)

    -- 3. Calculate Target Dimensions (Content Size)
    local target_height = math.min(math.floor(max_window_height * ui_opts.size_ratio), max_fittable_content_height)
    local target_width = math.min(math.floor(max_window_width * ui_opts.size_ratio), max_fittable_content_width)
    target_width = math.floor(max_window_width * ui_opts.size_ratio)

    -- 4. Apply Constraints (min/max editor size) - Apply to Content Size
    height = math.max(ui_opts.min_height, target_height)
    width = math.max(ui_opts.min_width, target_width)

    -- 5. Set Final Position based on placement and calculated size
    win_config.col = cursor_relative_screen_col + ui_opts.col_offset
    if place_above then
      -- Place window *above* cursor line, adjusted by offset
      -- Revert to using 'height' and keep -1 adjustment
      local initial_target_row = screen_space_above - height - border_vertical_overhead - ui_opts.row_offset - 1

      if initial_target_row < 0 then
        -- Window is too tall for the space above, reduce height and place at top
        local overflow = -initial_target_row
        height = height - overflow
        height = math.max(height, ui_opts.min_height)
        -- Revert final_win_height logic
        win_config.row = 0
      else
        -- Window fits, place at calculated row
        win_config.row = initial_target_row
      end
    else
      -- Place window *below* cursor line, adjusted by offset
      -- Remove +2 row adjustment
      win_config.row = cursor_relative_screen_row + ui_opts.row_offset

      -- Make height one row smaller, respecting min_height
      height = height - 1
      height = math.max(height, ui_opts.min_height)
    end

    win_config.width = width
    win_config.height = height
  else
    -- Subsequent popups
    local prev = stack().top()

    if not prev or prev.width == nil or prev.height == nil or prev.row == nil or prev.col == nil then
      return nil
    end

    win_config.win = prev.win_id -- Specify the anchor window

    width = math.max(ui_opts.min_width, prev.width - ui_opts.width_decrement)
    height = math.max(ui_opts.min_height, prev.height - ui_opts.height_decrement)

    -- Row and Col are now offsets RELATIVE to the previous window
    -- Check winbar for the *previous* window specifically
    local prev_winbar_enabled = vim.api.nvim_get_option_value("winbar", { win = prev.win_id }) ~= ""
    row = ui_opts.stack_row_offset - (prev_winbar_enabled and 1 or 0) -- Adjust based on previous window's winbar
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

  -- Manage buffer-local keymap using tracker
  local target_bufnr = opts.target_bufnr
  local close_key = (config() and config().keys and config().keys.close) or "q"
  local tracker_entry = stack_module.get_tracker_entry(target_bufnr) -- Assume this function exists in stack.lua

  if not tracker_entry then
    -- First reference for this buffer
    local original_map_details = nil
    local existing_maps = vim.api.nvim_buf_get_keymap(target_bufnr, "n")
    for _, map in ipairs(existing_maps) do
      if map.lhs == close_key then
        original_map_details = {
          key = close_key,
          mode = "n",
          map = {
            rhs = map.rhs,
            noremap = map.noremap == 1,
            silent = map.silent == 1,
            script = map.script == 1,
            expr = map.expr == 1,
            callback = map.callback,
            desc = map.desc or "",
          },
        }
        if original_map_details.map.callback then
          original_map_details.map.rhs = nil
        end
        break
      end
    end

    -- Set our temporary mapping
    local close_cmd = "<Cmd>close<CR>"
    vim.api.nvim_buf_set_keymap(
      target_bufnr,
      "n",
      close_key,
      close_cmd,
      { noremap = true, silent = true, nowait = true, desc = "Overlook: Close popup" }
    )

    -- Create tracker entry
    stack_module.create_tracker_entry(target_bufnr, original_map_details)
  else
    -- Buffer already tracked, just increment ref count
    stack_module.increment_tracker_refcount(target_bufnr)
  end

  -- 4. Get final geometry and check validity
  local final_config = api.nvim_win_get_config(win_id)
  if final_config and final_config.width and final_config.height and final_config.row and final_config.col then
    width = final_config.width
    height = final_config.height
    row = math.floor(final_config.row)
    col_abs = math.floor(final_config.col)
  else
    if width == nil or height == nil or row == nil or col_abs == nil then
      if api.nvim_win_is_valid(win_id) then
        api.nvim_win_close(win_id, true)
      end
      if api.nvim_win_is_valid(pre_open_win_id) then
        api.nvim_set_current_win(pre_open_win_id)
      end
      return nil
    end
  end

  -- 5. Add to Stack (keymap info is now handled by the tracker)
  local stack_item = {
    win_id = win_id,
    buf_id = target_bufnr,
    z_index = win_config.zindex,
    width = width,
    height = height,
    row = row,
    col = col_abs,
    original_win_id = original_win_id,
  }
  stack().push(stack_item) -- Push item without keymap details

  -- 6. Setup WinClosed Autocommand
  api.nvim_create_autocmd("WinClosed", {
    group = group_id,
    pattern = tostring(win_id),
    once = true,
    callback = function(args)
      if tonumber(args.match) == win_id then
        -- Call handle_win_close directly, without vim.schedule
        require("overlook.stack").handle_win_close(win_id)
      end
    end,
  })

  return { win_id = win_id, buf_id = opts.target_bufnr }
end

return M
