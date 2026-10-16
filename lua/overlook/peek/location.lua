--- Open a popup at a caller-supplied location.
---
--- Accepts one LSP Location, LocationLink, or quickfix entry (the `items`
--- shape `vim.lsp.buf.*({ on_list = ... })` passes through) and turns it
--- into OverlookPopupOptions. Resolution order for the buffer is:
---   1. a document URI (`uri` / `targetUri`, including under `user_data`)
---   2. a valid `bufnr` (quickfix uses bufnr when it is non-zero)
---   3. `filename`
--- A 1-based `lnum`/`col` wins over an LSP range, because quickfix entries
--- from |vim.lsp.util.locations_to_items()| already converted the position
--- to bytes. Raw ranges are 0-based; `character` is a UTF-16 code unit, the
--- LSP default when no client negotiated another encoding.
---
--- Returns nil (and notifies) when the item does not identify a buffer and a
--- position. Never raises: a bad URI or an unloadable path is a warning.

---@param value any
---@return string|nil
local function nonempty_string(value)
  if type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

--- Load `bufnr` if needed. Returns nil when the buffer is not a real, loadable one.
---@param bufnr integer|nil
---@return integer|nil
local function load_buffer(bufnr)
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    local ok = pcall(vim.fn.bufload, bufnr)
    if not ok or not vim.api.nvim_buf_is_valid(bufnr) then
      return nil
    end
  end
  return bufnr
end

---@param uri string
---@return integer|nil
local function bufnr_from_uri(uri)
  local ok, bufnr = pcall(vim.uri_to_bufnr, uri)
  if not ok or type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  -- uri_to_bufnr creates a buffer even when the file does not exist. Peeking
  -- that empty buffer hides a bad URI, so require a readable file unless the
  -- buffer was already loaded by the caller.
  if vim.fn.filereadable(name) == 0 and not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end
  return load_buffer(bufnr)
end

---@param filename string
---@return integer|nil
local function bufnr_from_filename(filename)
  local path = vim.fn.fnamemodify(filename, ":p")
  local existing = vim.fn.bufnr(path)
  if existing == -1 then
    existing = vim.fn.bufnr(filename)
  end
  if existing ~= -1 then
    return load_buffer(existing)
  end
  local readable = (vim.fn.filereadable(path) == 1 and path) or (vim.fn.filereadable(filename) == 1 and filename) or nil
  if not readable then
    return nil
  end
  return load_buffer(vim.fn.bufadd(readable))
end

---@param item OverlookPeekItem
---@return integer|nil
local function resolve_bufnr(item)
  local user_data = type(item.user_data) == "table" and item.user_data or nil
  local uris = {
    item.uri,
    item.targetUri,
    user_data and user_data.uri,
    user_data and user_data.targetUri,
  }
  for _, uri in ipairs(uris) do
    if nonempty_string(uri) then
      local bufnr = bufnr_from_uri(uri)
      if bufnr then
        return bufnr
      end
    end
  end

  -- Quickfix: a non-zero bufnr names the buffer; filename is the fallback.
  local from_bufnr = load_buffer(item.bufnr)
  if from_bufnr then
    return from_bufnr
  end

  local filename = nonempty_string(item.filename) or (user_data and nonempty_string(user_data.filename))
  if filename then
    return bufnr_from_filename(filename)
  end

  return nil
end

--- LSP `character` is a UTF-16 code unit. Fall back to a raw +1 conversion if
--- the installed Neovim cannot translate it.
---@param line_text string
---@param character integer|nil
---@return integer
local function lsp_character_to_col(line_text, character)
  if type(character) ~= "number" or character < 0 then
    character = 0
  end
  local ok, byte = pcall(vim.str_byteindex, line_text, "utf-16", character, false)
  if ok and type(byte) == "number" then
    return byte + 1
  end
  return character + 1
end

---@param source table|nil
---@return { line: integer, character: integer|nil }|nil
local function range_start(source)
  if type(source) ~= "table" then
    return nil
  end
  local range = source.range or source.targetSelectionRange or source.targetRange
  if type(range) ~= "table" or type(range.start) ~= "table" then
    return nil
  end
  if type(range.start.line) ~= "number" or range.start.line < 0 then
    return nil
  end
  return range.start
end

---@param item OverlookPeekItem
---@param bufnr integer
---@return integer|nil lnum
---@return integer|nil col
local function resolve_position(item, bufnr)
  if type(item.lnum) == "number" and item.lnum >= 1 then
    local col = type(item.col) == "number" and item.col >= 1 and item.col or 1
    return item.lnum, col
  end

  local start_pos = range_start(item) or range_start(item.user_data)
  if not start_pos then
    return nil
  end
  local text = vim.api.nvim_buf_get_lines(bufnr, start_pos.line, start_pos.line + 1, false)[1] or ""
  return start_pos.line + 1, lsp_character_to_col(text, start_pos.character)
end

---@param item OverlookPeekItem
---@param bufnr integer
---@return string
local function resolve_title(item, bufnr)
  if nonempty_string(item.title) then
    return item.title
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= "" then
    return vim.fn.fnamemodify(name, ":~:.")
  end
  if nonempty_string(item.filename) then
    return vim.fn.fnamemodify(item.filename, ":~:.")
  end
  return "Overlook"
end

---@param item OverlookPeekItem|nil
---@return OverlookPopup|nil
return function(item)
  if type(item) ~= "table" then
    vim.notify("Overlook: invalid peek item.", vim.log.levels.WARN)
    return nil
  end

  local bufnr = resolve_bufnr(item)
  if not bufnr then
    vim.notify("Overlook: could not resolve a buffer for the peek item.", vim.log.levels.WARN)
    return nil
  end

  local lnum, col = resolve_position(item, bufnr)
  if not lnum then
    vim.notify("Overlook: peek item is missing a position.", vim.log.levels.WARN)
    return nil
  end

  return require("overlook.window").open_popup {
    target_bufnr = bufnr,
    lnum = lnum,
    col = col,
    title = resolve_title(item, bufnr),
  }
end
