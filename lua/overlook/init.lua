local M = {}

-- Cache peek module for performance
local peek_mod ---@type table | nil
local function peek()
  if not peek_mod then
    peek_mod = require("overlook.peek")
  end
  return peek_mod
end

---Public function to peek a mark using vim.ui.input.
function M.peek_mark()
  vim.ui.input({ prompt = "Overlook Mark:" }, function(input)
    -- Handle cancellation (input is nil)
    if input == nil then
      -- vim.notify("Overlook: Mark peek cancelled.", vim.log.levels.INFO) -- Optional: Less verbose
      return
    end
    -- Handle empty input
    if input == "" then
      return
    end
    -- Validate input length
    if #input == 1 then
      peek().peek("marks", input) -- Call the generic peek function
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
  vim.api.nvim_create_user_command("OverlookMark", M.peek_mark, {
    desc = "Overlook: Peek a mark using stackable popups",
  })
  -- Example Keymap:
  -- vim.keymap.set("n", "<leader>om", M.peek_mark, { desc = "Overlook: Peek Mark" })
end

return M
