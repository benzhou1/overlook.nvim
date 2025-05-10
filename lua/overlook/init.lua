local M = {}

local function setup_autocmd()
  local state = require("overlook.state")

  -- Setup Autocommands for dynamic keymap
  local augroup = vim.api.nvim_create_augroup("OverlookStateManagement", { clear = true })
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

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup, -- Use the same group or a new one
    pattern = "*",
    callback = function() -- args contain args.buf
      -- Defer to ensure window/buffer context is fully established
      vim.schedule(function()
        state.handle_style_for_buffer_in_window()
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      state.cleanup_touched_buffer(args.buf)
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
