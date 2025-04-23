local api = vim.api
local M = {}

-- Cache modules (ui, config) - same as before
local ui_mod ---@type table | nil
local function ui()
  if not ui_mod then
    ui_mod = require("overlook.ui")
  end
  return ui_mod
end

---Peeks a specific mark by opening its buffer in a popup.

---@param mark_char string
function M.peek(mark_char)
  -- Input validation (same as before)
  if not mark_char or #mark_char ~= 1 then
    return
  end

  local pos = vim.fn.getpos("'" .. mark_char)

  local bufnum = pos[1]
  local lnum = pos[2]
  local col = pos[3]
  -- local off = pos[4] -- Virtual column offset, usually not needed for display

  if bufnum == 0 or lnum == 0 then
    vim.notify("Overlook: Mark '" .. mark_char .. "' is not set.", vim.log.levels.INFO)
    return
  end

  -- Basic validation checks
  if not api.nvim_buf_is_loaded(bufnum) then
    -- Attempt to load it? Or just return?
    -- For now, just return, assuming it should be loaded.
    return
  end
  if not api.nvim_buf_is_valid(bufnum) then
    vim.notify(
      "Overlook Error: Buffer for mark '" .. mark_char .. "' (" .. bufnum .. ") is invalid.",
      vim.log.levels.ERROR
    )
    return
  end

  local filepath = api.nvim_buf_get_name(bufnum)
  local display_path = vim.fn.fnamemodify(filepath, ":~:.") -- Title content

  -- Create the popup, passing target buffer and position directly
  ui().create_popup {
    target_bufnr = bufnum,
    lnum = lnum,
    col = col,
    title = display_path,

    -- No need to format lines here anymore
    -- No need to pass target_info separately anymore
  }
  -- No need to set buffer variable vim.b[...]
end

return M
