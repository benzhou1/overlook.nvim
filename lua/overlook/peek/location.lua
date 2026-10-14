--- Resolve an LSP location list into an Overlook popup.
---
--- Definition uses this helper. A references or implementation source can call
--- `open` from its own `on_list` callback with a different empty message and
--- prompt; see |overlook-peek|.
---
--- One item opens immediately. Several items follow |OverlookOnMultiple|
--- (`on_multiple` in |overlook-config|):
--- - `"first"` (default) opens the first item.
--- - `"select"` calls `vim.ui.select`. Entries are
---   `relative/path:line: text` (path relative to the working directory, line
---   text trimmed). A UI that replaces `vim.ui.select`, such as
---   telescope-ui-select or `require("fzf-lua").register_ui_select()`, receives
---   the same list.
--- - a function is called as `on_multiple(items, open_fn)`. `open_fn(item)`
---   opens that item through |overlook.window.open_popup|.
local M = {}

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
function M.peek(item)
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


---@class OverlookLocationOpenOpts
---@field empty_message? string Notification (INFO) when `items` is empty.
---@field no_uri_message? string Notification (WARN) when the chosen item has no URI.
---@field prompt? string Prompt passed to `vim.ui.select`.
---@field kind? string Kind hint passed to `vim.ui.select`.

--- Format one quickfix-style LSP item for `vim.ui.select`.
---
--- Shape: `relative/path:line: text`. The path is relative to the working
--- directory when the file is under it. Line text is trimmed.
---@param item table
---@return string
function M.format_item(item)
  if type(item) ~= "table" then
    return ""
  end

  local filename = item.filename or ""
  local relative = filename == "" and "" or vim.fn.fnamemodify(filename, ":.")
  local lnum = tonumber(item.lnum) or 0
  local text = type(item.text) == "string" and vim.trim(item.text) or ""
  return string.format("%s:%d: %s", relative, lnum, text)
end

--- Open one LSP location item in a popup.
---
--- The URI is read from `user_data.targetUri` (LocationLink) or
--- `user_data.uri` (Location), which is where Neovim stores the original LSP
--- location on a quickfix item.
---@param item table
---@param no_uri_message? string
---@return boolean opened
function M.open_item(item, no_uri_message)
  if type(item) ~= "table" then
    return false
  end

  local user_data = item.user_data
  local uri = type(user_data) == "table" and (user_data.targetUri or user_data.uri) or nil
  if not uri then
    vim.notify(no_uri_message or "Overlook: No URI found in LSP location item.", vim.log.levels.WARN)
    return false
  end

  require("overlook.window").open_popup {
    target_bufnr = vim.uri_to_bufnr(uri),
    lnum = item.lnum,
    col = item.col,
    title = item.filename,
  }
  return true
end

--- Resolve `on_multiple`, warning when the configured value is not recognized.
--- `nil` uses the default `"first"` so a partial config keeps the previous behavior.
---@param value any
---@return "select"|"first"|fun(items: table[], open_fn: fun(item: table))
local function resolve_on_multiple(value)
  if value == nil or value == "first" then
    return "first"
  end
  if value == "select" or type(value) == "function" then
    return value
  end

  vim.notify("Overlook: unknown on_multiple (" .. tostring(value) .. "); using vim.ui.select.", vim.log.levels.WARN)
  return "select"
end

--- Open a popup for an LSP location list.
---
--- - Zero items: notify `empty_message` and return.
--- - One item: open it directly, with no prompt.
--- - Several items: follow |OverlookOnMultiple|.
---
--- Cancelling `vim.ui.select` (or calling `open_fn` with `nil`) opens nothing.
---@param items? table[] Quickfix-style items from an LSP `on_list` callback.
---@param opts? OverlookLocationOpenOpts
---@return nil
function M.open(items, opts)
  opts = opts or {}
  if type(items) ~= "table" or #items == 0 then
    vim.notify(opts.empty_message or "Overlook: No location found.", vim.log.levels.INFO)
    return
  end

  if #items == 1 then
    M.open_item(items[1], opts.no_uri_message)
    return
  end

  local on_multiple = resolve_on_multiple(require("overlook.config").get().on_multiple)

  local function open_chosen(item)
    if item == nil then
      return
    end
    M.open_item(item, opts.no_uri_message)
  end

  if on_multiple == "first" then
    open_chosen(items[1])
    return
  end

  if type(on_multiple) == "function" then
    on_multiple(items, open_chosen)
    return
  end

  vim.ui.select(items, {
    prompt = opts.prompt or "Overlook: Select location",
    format_item = M.format_item,
    kind = opts.kind or "overlook.location",
  }, function(choice)
    open_chosen(choice)
  end)
end

return M
