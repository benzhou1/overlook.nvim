local M = {}

local ui_mod ---@type table | nil
local function ui()
  if not ui_mod then
    ui_mod = require("overlook.ui")
  end
  return ui_mod
end

local adapters = {
  marks = require("overlook.adapter.marks"),
  definition = require("overlook.adapter.definition"),
}

--- Generic peek function that calls the appropriate adapter's get() method
--- @param adapter_type string The type of adapter ('marks', 'definition', etc.)
--- @param ... any Arguments to pass to the adapter's get() function
function M.peek(adapter_type, ...)
  local adapter = adapters[adapter_type]
  if not adapter or type(adapter.get) ~= "function" then
    vim.notify(
      "Overlook Error: Invalid adapter type or adapter missing get() function: " .. adapter_type,
      vim.log.levels.ERROR
    )
    return
  end

  local opts = adapter.get(...)
  if not opts then
    -- Adapter handled error or no data, message should have been shown by adapter
    return
  end

  -- TODO: Validate opts table structure?

  ui().create_popup(opts)
end

return M
