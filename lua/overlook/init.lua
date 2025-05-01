local M = {}

-- Cache required modules
local peek_mod ---@type table | nil
local config_mod ---@type table | nil -- Add config cache

local function config()
  if not config_mod then
    config_mod = require("overlook.config")
  end
  return config_mod
end

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

---Public function to peek the definition under the cursor.
function M.peek_definition()
  peek().peek("definition")
end

---Public function to peek the current cursor position.
function M.peek_cursor()
  peek().peek("cursor")
end

local function setup_autocmd()
  local state = require("overlook.state")

  -- Setup Autocommands for dynamic keymap
  local augroup = vim.api.nvim_create_augroup("OverlookFocusKeymap", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      vim.schedule(state.update_keymap_state)
    end,
  })

  -- Add separate BufEnter for title updates
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      vim.schedule(state.update_title)
    end,
  })
end

-- Setup function: Call this from your main Neovim config
---@param opts? table User configuration options (optional).
function M.setup(opts)
  config().setup(opts) -- Pass opts to config module

  -- Define User Commands
  vim.api.nvim_create_user_command("OverlookMark", M.peek_mark, {
    desc = "Overlook: Peek a mark using stackable popups",
  })
  vim.api.nvim_create_user_command("OverlookDefinition", M.peek_definition, {
    desc = "Overlook: Peek definition under cursor using stackable popups",
  })
  vim.api.nvim_create_user_command("OverlookCursor", M.peek_cursor, {
    desc = "Overlook: Peek cursor position using stackable popups",
  })

  setup_autocmd()
end

return M
