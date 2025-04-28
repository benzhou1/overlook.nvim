local api = vim.api

local M = {}

-- Tracker for buffer-local keymap overrides
-- Key: bufnr
-- Value: { original_map_details: table | nil, ref_count: integer }
local buffer_keymap_tracker = {}

-- Helper function to restore original map - DEFINED BEFORE USE
local function restore_original_map(bufnr, original_map_details)
  if not original_map_details then
    return
  end
  local restore_opts = {
    noremap = original_map_details.map.noremap,
    silent = original_map_details.map.silent,
    script = original_map_details.map.script,
    expr = original_map_details.map.expr,
    callback = original_map_details.map.callback,
    desc = original_map_details.map.desc,
  }
  local rhs = original_map_details.map.rhs
  vim.api.nvim_buf_set_keymap(bufnr, original_map_details.mode, original_map_details.key, rhs or "", restore_opts)
end

---@class OverlookStackItem
---@field win_id integer Window ID of the popup
---@field buf_id integer Buffer ID of the *target* buffer shown in the popup
---@field z_index integer Z-index of the window
---@field width integer
---@field height integer
---@field row integer     -- Absolute screen row (1-based)
---@field col integer     -- Absolute screen col (1-based)
---@field original_win_id integer? -- Original window ID (if applicable)

---@type OverlookStackItem[]
M.stack = {}

---@type integer | nil
M.original_win_id = nil

---Returns the current size of the stack.
---@return integer
function M.size()
  return #M.stack
end

---Returns the info for the top popup without removing it.
---@return OverlookStackItem | nil
function M.top()
  if M.size() == 0 then
    return nil
  end
  return M.stack[#M.stack] -- Last element is the top
end

---Finds a popup's info and index in the stack by buffer ID.
---@param win_id integer
---@return OverlookStackItem | nil, integer | nil @ Returns item info and its 1-based index.
function M.find_by_win(win_id) -- Renamed from find_by_buf
  for i = #M.stack, 1, -1 do
    if M.stack[i].win_id == win_id then
      return M.stack[i], i
    end
  end

  return nil, nil
end

---Pushes popup info onto the stack and stores original wid if needed.
---@param popup_info OverlookStackItem
function M.push(popup_info)
  if M.size() == 0 and popup_info.original_win_id then
    M.original_win_id = popup_info.original_win_id
  end
  table.insert(M.stack, popup_info)
end

---Handles cleanup and focus when an overlook popup WINDOW is closed.
--- Triggered by WinClosed autocommand (via ui.lua).
---@param closed_win_id integer
function M.handle_win_close(closed_win_id)
  local item, index = M.find_by_win(closed_win_id)
  if not index or not item then
    -- If the closed window wasn't in our stack, maybe it was the original window?
    -- Or some other unrelated window. Check if stack is empty and original exists.
    if M.size() == 0 and M.original_win_id and api.nvim_win_is_valid(M.original_win_id) then
      -- If the stack is empty, ensure focus goes back to the original window
      -- Use pcall for safety as this is an autocommand context
      pcall(api.nvim_set_current_win, M.original_win_id)
      M.original_win_id = nil -- Clear original ID as we are back
    end
    -- Otherwise, do nothing specific, let Neovim handle focus.
    return
  end

  local closed_bufnr = item.buf_id
  local tracker_entry = buffer_keymap_tracker[closed_bufnr]

  if tracker_entry then
    tracker_entry.ref_count = tracker_entry.ref_count - 1

    if tracker_entry.ref_count <= 0 then
      -- Last reference, delete temp map and restore original
      local close_key = (require("overlook.config").options.ui.keys or {}).close or "q"
      pcall(vim.api.nvim_buf_del_keymap, closed_bufnr, "n", close_key)

      -- Restore original if it exists
      if tracker_entry.original_map_details then
        restore_original_map(closed_bufnr, tracker_entry.original_map_details)
      end
      -- Remove tracker entry
      buffer_keymap_tracker[closed_bufnr] = nil -- Explicitly remove entry!
    end
  end

  -- Window was found in the stack. Remove it.
  table.remove(M.stack, index)

  -- Determine the window to focus next
  if M.size() > 0 then
    -- Focus the *new* top of the stack (which was the one below the closed one)
    local next_top_popup = M.top() -- M.top() now returns the correct window
    if next_top_popup and api.nvim_win_is_valid(next_top_popup.win_id) then
      pcall(api.nvim_set_current_win, next_top_popup.win_id)
    else
      -- This case might mean the window below was also closed unexpectedly or is invalid.
      -- Fallback to original window if possible, otherwise call close_all as a safety measure.
      if M.original_win_id and api.nvim_win_is_valid(M.original_win_id) then
        pcall(api.nvim_set_current_win, M.original_win_id)
        M.original_win_id = nil -- Clear original ID since stack should be empty now
      else
        -- If original is gone too, close everything remaining as a safety measure
        M.close_all(true) -- Call close_all! Found the bug.
        M.original_win_id = nil -- Ensure it's cleared
      end
    end
  else
    -- Stack is now empty, focus the original window
    if M.original_win_id and api.nvim_win_is_valid(M.original_win_id) then
      pcall(api.nvim_set_current_win, M.original_win_id)
    else
      -- Fallback: focus any valid window (Neovim might do this anyway)
      local wins = api.nvim_list_wins()
      if wins and #wins > 0 and api.nvim_win_is_valid(wins[1]) then
        pcall(api.nvim_set_current_win, wins[1])
      end
    end
    -- Clear the original window ID only when the stack is empty *and* we've attempted focus restoration
    M.original_win_id = nil

    -- Call the on_stack_empty hook ONLY if focus was successfully restored to the original window
    local config_mod = require("overlook.config")
    if config_mod and config_mod.options and type(config_mod.options.on_stack_empty) == "function" then
      -- Use pcall to prevent user errors in hook from breaking the plugin
      local ok, err = pcall(config_mod.options.on_stack_empty)
      if not ok then
        vim.notify("Overlook Error: on_stack_empty callback failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end
end

-- close_all() - Modified to use eventignore
--- Closes all overlook popups gracefully using eventignore.
---@param force_close? boolean If true, uses force flag when closing windows.
function M.close_all(force_close)
  local original_win_to_restore = M.original_win_id
  local stack_copy = vim.deepcopy(M.stack) -- Copy stack to iterate safely

  -- Delete temporary maps and restore original keymaps using the tracker
  local close_key = (require("overlook.config").options.ui.keys or {}).close or "q"
  for bufnr, entry in pairs(buffer_keymap_tracker) do
    -- Delete the temporary map regardless of ref count, as we are closing all
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", close_key)
    -- Restore the original map if one was stored
    if entry.original_map_details then
      restore_original_map(bufnr, entry.original_map_details)
    end
  end
  -- Clear the tracker completely
  buffer_keymap_tracker = {}

  -- Clear the stack state immediately -- MOVED LATER
  -- M.stack = {}
  -- M.original_win_id = nil

  -- Ignore WinClosed while we manually close everything
  vim.opt.eventignore:append("WinClosed")

  -- Iterate over the copy, closing windows
  for i = #stack_copy, 1, -1 do
    local popup_info = stack_copy[i]
    if popup_info and api.nvim_win_is_valid(popup_info.win_id) then
      pcall(api.nvim_win_close, popup_info.win_id, force_close or false) -- Ensure this runs
    end
  end

  -- Re-enable WinClosed
  vim.opt.eventignore:remove("WinClosed")

  -- Clear the stack state AFTER closing windows and restoring focus
  M.stack = {}
  M.original_win_id = nil

  -- Explicitly restore focus to the original window *after* all popups are closed.
  if original_win_to_restore and api.nvim_win_is_valid(original_win_to_restore) then
    pcall(api.nvim_set_current_win, original_win_to_restore)
  else
    -- Fallback IF AND ONLY IF original_win_to_restore was set but became invalid.
    -- Do not fallback if original_win_to_restore was nil initially.
    if original_win_to_restore then -- Check if we *tried* to restore an original
      local wins = api.nvim_list_wins()
      if wins and #wins > 0 then
        local target_win = wins[1] -- Focus first available window
        if api.nvim_win_is_valid(target_win) then
          pcall(api.nvim_set_current_win, target_win)
        end
      end
    end
  end

  -- Clean up the autocommand group to prevent leaks
  pcall(api.nvim_del_augroup_by_name, "OverlookPopupClose")
end

-- Functions to manage the tracker
function M.get_tracker_entry(bufnr)
  return buffer_keymap_tracker[bufnr]
end

function M.create_tracker_entry(bufnr, original_map_details)
  buffer_keymap_tracker[bufnr] = {
    original_map_details = original_map_details, -- This is the structured details { key=.., mode=.., map=.. }
    ref_count = 1,
  }
end

function M.increment_tracker_refcount(bufnr)
  if buffer_keymap_tracker[bufnr] then
    buffer_keymap_tracker[bufnr].ref_count = buffer_keymap_tracker[bufnr].ref_count + 1
  end
end

-- Function to reset the internal tracker (for testing)
function M.reset_keymap_tracker()
  buffer_keymap_tracker = {}
end

return M
