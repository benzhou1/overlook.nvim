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
function M.handle_win_close(closed_win_id) -- Renamed from handle_close
  -- HACK: go extra step to restore focus to the original window
  -- Better if i can override the WinClosed beharior, such as the win_id to go after close
  if M.original_win_id and api.nvim_win_is_valid(M.original_win_id) then
    api.nvim_set_current_win(M.original_win_id)
  end

  local _, index = M.find_by_win(closed_win_id) -- Use find_by_win
  if not index then
    return
  end
  table.remove(M.stack, index)

  -- Restore focus logic (same logic as before, focuses next stack item or original window)
  if M.size() > 0 then
    local next_top_popup = M.top()
    -- Check validity *before* focusing
    if next_top_popup then
      if api.nvim_win_is_valid(next_top_popup.win_id) then
        api.nvim_set_current_win(next_top_popup.win_id)
      else
        -- This case shouldn't happen if logic is correct, but handle defensively
        M.close_all(true) -- Force close remaining and reset
      end
    else
      -- Stack is now empty, try focusing the original window
      if M.original_win_id and api.nvim_win_is_valid(M.original_win_id) then
        api.nvim_set_current_win(M.original_win_id)
      else
        -- Fallback: focus any valid window (Neovim might do this anyway)
        local wins = api.nvim_list_wins()
        if wins and wins[1] then
          api.nvim_set_current_win(wins[1])
        end
      end
      M.original_win_id = nil
    end
  else
    -- Stack is now empty, try focusing the original window
    if M.original_win_id and api.nvim_win_is_valid(M.original_win_id) then
      api.nvim_set_current_win(M.original_win_id)
    else
      -- Fallback: focus any valid window (Neovim might do this anyway)
      local wins = api.nvim_list_wins()
      if wins and wins[1] then
        api.nvim_set_current_win(wins[1])
      end
    end
    M.original_win_id = nil
  end
end

-- close_all() - Logic remains similar, but targets windows based on stack info
--- Closes all overlook popups gracefully.
---@param force_close? boolean If true, uses force flag when closing windows.
function M.close_all(force_close)
  local original_win_to_restore = M.original_win_id
  local stack_copy = vim.deepcopy(M.stack) -- Copy stack to iterate safely

  -- Iterate over the copy, closing windows
  for i = #stack_copy, 1, -1 do
    local popup_info = stack_copy[i]
    if popup_info and api.nvim_win_is_valid(popup_info.win_id) then
      -- Closing the window *should* trigger WinClosed -> handle_win_close -> stack removal
      -- We rely on handle_win_close triggered by the *last* window close to restore original focus
      api.nvim_win_close(popup_info.win_id, force_close or false)
    end
  end

  -- Simple safeguard if handle_win_close failed to clear everything
  if M.size() > 0 then
    M.stack = {}
  end
  -- Restore focus explicitly if stack is now empty and original exists (in case last handle_win_close failed)
  if M.size() == 0 and M.original_win_id == nil then -- Check if handle_win_close already reset it
    if original_win_to_restore and api.nvim_win_is_valid(original_win_to_restore) then
      api.nvim_set_current_win(original_win_to_restore)
      M.original_win_id = nil -- Ensure it's cleared after manual restore
    end
  end
end

return M
