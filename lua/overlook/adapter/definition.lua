local api = vim.api
local M = {}

--- Gets the options required for the peek popup for the definition under the cursor.
--- Returns nil if no definition is found or an error occurs.
---@return OverlookPopupOptions? opts Table suitable for overlook.ui.create_popup, or nil on error.
function M.get()
  local current_win = api.nvim_get_current_win()
  local current_buf = api.nvim_win_get_buf(current_win)

  local params = vim.lsp.util.make_position_params(current_win, 'utf-8')
  local timeout_ms = 1000 -- Adjust timeout as needed

  -- Use synchronous LSP request
  local result, err = vim.lsp.buf_request_sync(current_buf, "textDocument/definition", params, timeout_ms)

  if err then
    vim.notify("Overlook LSP Error: " .. tostring(err), vim.log.levels.ERROR) -- Use tostring for safety
    return nil
  end

  -- Process valid LSP result formats first
  local target_location = nil

  -- Iterate through results from potentially multiple LSP clients
  if type(result) == "table" then
    ---@diagnostic disable-next-line: unused-local
    for _client_id, client_response in pairs(result) do
      if client_response and not client_response.error and client_response.result then
        local client_locations = client_response.result
        local first_location = nil

        -- Check if the client returned a list or a single item
        if type(client_locations) == "table" then
          if client_locations[1] then -- List of Location or LocationLink
            first_location = client_locations[1]
          elseif client_locations.uri or client_locations.targetUri then -- Single Location or LocationLink
            first_location = client_locations
          end
        end

        -- If we found a location-like object, parse it
        if first_location then
          if first_location.targetUri then -- LocationLink
            local link_range = first_location.targetSelectionRange or first_location.targetRange
            if link_range then
              target_location = { uri = first_location.targetUri, range = link_range }
            end
          elseif first_location.uri then -- Location
            target_location = first_location
          end
        end

        -- If we successfully parsed a location from this client, stop looking
        if target_location then
          break
        end
      end
    end
  end

  -- If no valid location was extracted after checking all clients...
  if not target_location then
    -- Check if the original result table itself was empty (no clients responded?)
    if type(result) == "table" and vim.tbl_isempty(result) then
      vim.notify("Overlook: No definition found.", vim.log.levels.INFO)
    else
      vim.notify("Overlook Error: No definition found or unexpected LSP result format.", vim.log.levels.WARN)
    end
    return nil
  end

  -- If we have a target_location, proceed...
  local target_uri = target_location.uri
  local target_range = target_location.range

  -- Convert URI to buffer number and filename
  local target_bufnr = vim.uri_to_bufnr(target_uri)
  local target_filepath = vim.uri_to_fname(target_uri) -- Use fname for title

  if not api.nvim_buf_is_valid(target_bufnr) then
    -- Attempt to load the buffer if it's just not loaded yet
    vim.cmd("edit " .. vim.fn.fnameescape(target_filepath))
    target_bufnr = vim.uri_to_bufnr(target_uri) -- Re-evaluate bufnr
    if not api.nvim_buf_is_valid(target_bufnr) then
      vim.notify(
        "Overlook Error: Could not load or find valid buffer for definition: " .. target_filepath,
        vim.log.levels.ERROR
      )
      return nil
    end
  end

  -- LSP ranges are 0-indexed, Neovim API/UI uses 1-based
  local target_lnum = target_range.start.line + 1
  local target_col = target_range.start.character + 1 -- Use start character for column positioning

  local display_path = vim.fn.fnamemodify(target_filepath, ":~:.") -- Title content

  -- Return the options table for the popup
  local opts = {
    target_bufnr = target_bufnr,
    lnum = target_lnum,
    col = target_col,
    title = display_path,
  }
  return opts
end

return M
