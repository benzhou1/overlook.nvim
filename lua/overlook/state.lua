local api = vim.api
local Config = require("overlook.config")
local Stack = require("overlook.stack")

local M = {}

-- State for dynamic keymap
local currently_mapped_info = {
  bufnr = nil,
  original_map_details = nil,
}

-- Helper to find and reconstruct original map details
local function find_original_map(bufnr, mode, lhs)
  -- Use pcall for safety, vim.keymap.get can error on invalid buffer
  local ok, maps = pcall(vim.keymap.get, mode, { buffer = bufnr })
  if not ok or not maps then
    return nil
  end

  for _, map in ipairs(maps) do
    if map.lhs == lhs then
      -- Reconstruct opts, ensuring buffer is present and removing mutually exclusive fields
      local opts = vim.deepcopy(map)
      opts.buffer = bufnr -- Ensure buffer is in opts
      opts.mode = nil
      opts.lhs = nil
      opts.sid = nil -- Remove fields not used by set
      opts.reg = nil
      opts.script = opts.script == 1 -- Convert 1/0 to boolean
      opts.noremap = opts.noremap == 1
      opts.silent = opts.silent == 1
      opts.expr = opts.expr == 1
      opts.nowait = opts.nowait == 1
      opts.unique = opts.unique == 1

      local rhs_or_callback = opts.callback -- Prefer callback if it exists
      if rhs_or_callback then
        opts.callback = nil
        opts.rhs = nil
      else
        rhs_or_callback = opts.rhs
        opts.rhs = nil
        opts.callback = nil
      end

      return { mode = map.mode, lhs = map.lhs, rhs_or_callback = rhs_or_callback, opts = opts }
    end
  end
  return nil
end

---Handles updating the dynamic 'close' keymap based on focus and stack state.
function M.update_keymap_state()
  -- Safeguard for tests where vim.api might not be ready immediately
  if not vim.api then
    return
  end
  local current_win = api.nvim_get_current_win()
  -- Add check for valid buffer before proceeding
  local current_buf = api.nvim_win_get_buf(current_win)
  if not api.nvim_buf_is_valid(current_buf) then
    return -- Avoid errors if buffer somehow invalid
  end

  local top_item = Stack.top() -- Use local require
  local top_win_id = top_item and top_item.win_id or nil
  local cfg = Config.options -- Use local require
  local close_key = (cfg and cfg.ui and cfg.ui.keys and cfg.ui.keys.close) or "q"

  -- Target buffer for the keymap is the buffer in the current window ONLY if it's the top popup
  local target_bufnr_for_keymap = (top_win_id and current_win == top_win_id) and current_buf or nil

  if currently_mapped_info.bufnr == target_bufnr_for_keymap then
    return -- State is already correct for keymap
  end

  -- State needs changing: Clear old map first (if any)
  if currently_mapped_info.bufnr then
    local previous_bufnr = currently_mapped_info.bufnr

    -- Clear keymap
    local ok_del, err_del = pcall(vim.keymap.del, "n", close_key, { buffer = previous_bufnr })
    if not ok_del then
      vim.notify("Overlook: Error deleting old keymap: " .. tostring(err_del), vim.log.levels.WARN)
    end

    -- Restore original keymap if it existed
    if currently_mapped_info.original_map_details then
      local map = currently_mapped_info.original_map_details
      local ok_set, err_set = pcall(vim.keymap.set, map.mode, map.lhs, map.rhs_or_callback, map.opts)
      if not ok_set then
        vim.notify(
          "Overlook: Error restoring original keymap for buffer "
            .. tostring(previous_bufnr)
            .. ": "
            .. tostring(err_set),
          vim.log.levels.WARN
        )
      end
    end

    currently_mapped_info = { bufnr = nil, original_map_details = nil } -- Reset state
  end

  -- Set new map if needed
  if target_bufnr_for_keymap then
    -- Find and store original map BEFORE setting the new one
    local original_details = find_original_map(target_bufnr_for_keymap, "n", close_key)
    if original_details then
      currently_mapped_info.original_map_details = original_details
    end

    -- Set the custom map
    local close_cmd = "<Cmd>close<CR>"
    local ok_set_new, err_set_new = pcall(vim.keymap.set, "n", close_key, close_cmd, {
      buffer = target_bufnr_for_keymap,
      noremap = true,
      silent = true,
      nowait = true,
      desc = "Overlook: Close popup",
    })

    if not ok_set_new then
      vim.notify("Overlook: Error setting close keymap: " .. tostring(err_set_new), vim.log.levels.ERROR)
      currently_mapped_info = { bufnr = nil, original_map_details = nil } -- Reset state on error
    else
      currently_mapped_info.bufnr = target_bufnr_for_keymap -- Update state only on success
    end
  end
end

---Sets the window title based on the buffer if the current window is the top popup.
function M.update_title()
  if not vim.api then
    return
  end
  local current_win = api.nvim_get_current_win()
  local current_buf = api.nvim_win_get_buf(current_win)
  if not api.nvim_buf_is_valid(current_buf) then
    return
  end

  local top_item = Stack.top() -- Use local require
  local top_win_id = top_item and top_item.win_id or nil

  -- Only act if the current window IS the top overlook popup
  if top_win_id and current_win == top_win_id then
    local buf_name = api.nvim_buf_get_name(current_buf)
    local display_title
    if buf_name and buf_name ~= "" then
      display_title = vim.fn.fnamemodify(buf_name, ":~:.")
    else
      display_title = "(No Name)" -- Fallback title
    end

    -- Get current config and set the title
    local ok_cfg, current_cfg = pcall(api.nvim_win_get_config, current_win)
    if ok_cfg and current_cfg then
      current_cfg.title = display_title
      -- Use pcall for safety, but maybe notify on error?
      local ok_set, err_set = pcall(api.nvim_win_set_config, current_win, current_cfg)
      if not ok_set then
        vim.notify("Overlook: Failed to set window title: " .. tostring(err_set), vim.log.levels.WARN)
      end
    else
      vim.notify("Overlook: Failed to get window config for title", vim.log.levels.WARN)
    end
  end
end

return M
