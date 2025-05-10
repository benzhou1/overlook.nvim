local api = vim.api

local M = {}

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

---Returns true if the stack is empty, false otherwise.
---@return boolean
function M.empty()
  return M.size() == 0
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
        M.clear(true)
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

    -- Call the on_stack_empty hook if defined
    local config_mod = require("overlook.config")
    if config_mod and config_mod.options and type(config_mod.options.on_stack_empty) == "function" then
      -- Use pcall to prevent user errors in hook from breaking the plugin
      local ok, err = pcall(config_mod.options.on_stack_empty)
      if not ok then
        vim.notify("Overlook Error: on_stack_empty callback failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end

  -- Explicitly update the keymap state after handling window close and focus change
  -- Use vim.schedule to ensure this runs after Neovim has processed the focus change
  vim.schedule(function()
    require("overlook.state").update_keymap()
  end)
end

-- clear() - Modified to use eventignore
--- Closes all overlook popups gracefully using eventignore.
---@param force_close? boolean If true, uses force flag when closing windows.
function M.clear(force_close)
  local original_win_to_restore = M.original_win_id
  local stack_copy = vim.deepcopy(M.stack) -- Copy stack to iterate safely

  -- Ignore WinClosed while we manually close everything
  vim.opt.eventignore:append("WinClosed")

  -- Iterate over the copy, closing windows
  for i = #stack_copy, 1, -1 do
    local popup_info = stack_copy[i]
    if popup_info and api.nvim_win_is_valid(popup_info.win_id) then
      pcall(api.nvim_win_close, popup_info.win_id, force_close or false)
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
    -- Do not fallback if original_win_to_restore was nil initially.
    if original_win_to_restore then
      local wins = api.nvim_list_wins()
      if wins and #wins > 0 then
        local target_win = wins[1]
        if api.nvim_win_is_valid(target_win) then
          pcall(api.nvim_set_current_win, target_win)
        end
      end
    end
  end

  -- Clean up the autocommand group to prevent leaks
  pcall(api.nvim_clear_autocmds, { group = "OverlookPopupClose" })

  -- Explicitly update the keymap state after closing all windows and restoring focus
  -- Use vim.schedule to ensure this runs after Neovim has processed the focus change
  vim.schedule(function()
    require("overlook.state").update_keymap()
  end)
end

return M
