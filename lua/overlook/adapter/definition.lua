local M = {}

M.async = true

---@param location_opts? vim.lsp.LocationOpts
function M.async_create_popup(create_popup_callback, location_opts)
  location_opts = location_opts or {}

  vim.lsp.buf.definition {
    on_list = function(tt)
      -- vim.print("LSP Definition Locations: ", vim.inspect(tt))
      local item = tt.items[1]
      local bufnr = vim.uri_to_bufnr(item.user_data.targetUri)

      create_popup_callback {
        target_bufnr = bufnr,
        lnum = item.lnum,
        col = item.col,
        title = item.filename,
      }
    end,
  }
end

return M
