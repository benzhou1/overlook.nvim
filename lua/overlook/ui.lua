local M = {}

---Creates and opens a floating window viewing the target buffer.
---@param opts OverlookPopupOptions
---@return OverlookPopup?
function M.create_popup(opts)
  local popup = require("overlook.popup").new(opts)
  if not popup then
    return nil
  end

  local stack = require("overlook.stack").win_get_stack(popup.root_winid)
  stack:push(popup)

  return popup
end

--- Promotes the top Overlook popup to a regular window (split, vsplit, or tab).
--- @param open_command string Command to run when promoting the popup to a window.
function M.promote_popup_to_window(open_command)
  local stack = require("overlook.stack").get_current_stack()

  if not stack or stack:empty() or not vim.w.is_overlook_popup then
    vim.notify("Overlook: No popup to promote.", vim.log.levels.INFO)
    return
  end

  local buf_id_to_open = vim.api.nvim_get_current_buf()

  ---@diagnostic disable-next-line: unused-local
  local _bufnum, lnum, col, _off = unpack(vim.fn.getpos("."))

  -- Close all overlook popups. This also clears the stack.
  stack:clear()

  -- Ensure the buffer is still valid and positive before trying to open it
  if not buf_id_to_open or not vim.api.nvim_buf_is_valid(buf_id_to_open) then
    vim.notify(
      string.format("Overlook Error: Buffer to promote is invalid (ID: %s).", tostring(buf_id_to_open)),
      vim.log.levels.ERROR
    )
    return
  end

  -- Open the buffer in the specified way
  local cmd = string.format("%s %d", open_command, buf_id_to_open)
  ---@diagnostic disable-next-line: param-type-mismatch
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    vim.notify(
      string.format("Overlook Error: Failed to execute command '%s': %s", cmd, tostring(err)),
      vim.log.levels.ERROR
    )
    return -- Ensure we don't proceed if window creation failed
  end

  -- set cursor position in the new window
  -- TODO: extract this to a util function
  vim.api.nvim_win_set_cursor(0, { lnum, math.max(0, col - 1) })
  vim.api.nvim_win_call(0, function()
    vim.cmd("normal! zz")
  end)
end

return M
