local M = {}

M.async = true

---@param location_opts? vim.lsp.LocationOpts
function M.async_create_popup(create_popup_callback, location_opts)
  location_opts = location_opts or {}

  vim.lsp.buf.definition {
    on_list = function(tt)
      -- vim.print("LSP Definition Locations: ", vim.inspect(tt))
      local item = tt.items[1]
      local uri = item.user_data.targetUri or item.user_data.uri
      if not uri then
        vim.notify("Overlook: No URI found in LSP definition item: " .. vim.inspect(tt), vim.log.levels.WARN)
        return
      end

      create_popup_callback {
        target_bufnr = vim.uri_to_bufnr(uri),
        lnum = item.lnum,
        col = item.col,
        title = item.filename,
      }
    end,
  }
end

return M
