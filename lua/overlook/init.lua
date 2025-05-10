local M = {}

local function setup_autocmd()
  local state = require("overlook.state")

  -- Setup Autocommands for dynamic keymap
  local augroup = vim.api.nvim_create_augroup("OverlookFocusKeymap", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = augroup,
    pattern = "*",
    callback = function()
      vim.schedule(state.update_keymap)
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
  require("overlook.config").setup(opts)
  setup_autocmd()
end

return M
