local M = {}

-- Cache adapter module for performance
local marks_adapter ---@type table | nil
local function marks()
  if not marks_adapter then
    marks_adapter = require("overlook.adapter.marks")
  end
  return marks_adapter
end

---Public function to peek a mark using vim.ui.input.
function M.peek_mark()
  vim.ui.input({ prompt = "Overlook Mark:" }, function(input)
    -- Handle cancellation (input is nil)
    if input == nil then
      vim.notify("Overlook: Mark peek cancelled.", vim.log.levels.INFO)
      return
    end
    -- Handle empty input
    if input == "" then
      vim.notify("Overlook: No mark character entered.", vim.log.levels.WARN)
      return
    end
    -- Validate input length
    if #input == 1 then
      marks().peek(input) -- Call the adapter's peek function
    else
      vim.notify("Overlook Error: Invalid mark. Please enter a single character.", vim.log.levels.ERROR)
    end
  end)
end

-- Setup function: Call this from your main Neovim config
---@param opts? table User configuration options (optional).
function M.setup(opts)
  require("overlook.config").setup(opts)
  -- Define User Commands or Keymaps here later if desired
  -- Example:
  -- vim.api.nvim_create_user_command('OverlookMark', M.peek_mark, {
  --   desc = "Overlook: Peek a mark using stackable popups",
  -- })
  vim.notify("Overlook initialized.", vim.log.levels.INFO) -- Confirmation
end

return M
