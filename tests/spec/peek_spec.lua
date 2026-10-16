describe("overlook.api.peek", function()
  local api_mod
  local notify_calls
  local original_notify
  local created_files

  local function write_temp(lines)
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, path)
    table.insert(created_files, path)
    return path
  end

  local function popup_cursor(popup)
    return vim.api.nvim_win_get_cursor(popup.winid)
  end

  before_each(function()
    notify_calls = {}
    created_files = {}
    original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    package.loaded["overlook.peek.location"] = nil
    package.loaded["overlook.api"] = nil
    api_mod = require("overlook.api")
  end)

  after_each(function()
    vim.notify = original_notify
    pcall(function()
      require("overlook.window").current():close_all()
    end)
    for _, path in ipairs(created_files) do
      local bufnr = vim.fn.bufnr(path)
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
      os.remove(path)
    end
    package.loaded["overlook.peek.location"] = nil
    package.loaded["overlook.api"] = nil
  end)

  it("opens a popup for a uri item", function()
    local path = write_temp { "alpha", "beta", "gamma" }
    local uri = vim.uri_from_fname(path)

    local popup = api_mod.peek {
      uri = uri,
      range = {
        start = { line = 1, character = 2 },
        ["end"] = { line = 1, character = 4 },
      },
    }

    assert.is_not_nil(popup)
    assert.are.equal(vim.uri_to_bufnr(uri), popup.opts.target_bufnr)
    assert.are.equal(2, popup.opts.lnum)
    assert.are.equal(3, popup.opts.col)
    assert.are.same({ 2, 2 }, popup_cursor(popup))
    assert.are.same({ "alpha", "beta", "gamma" }, vim.api.nvim_buf_get_lines(popup.opts.target_bufnr, 0, -1, false))
    assert.are.equal(0, #notify_calls)
  end)

  it("opens a popup for a filename item", function()
    local path = write_temp { "one", "two", "three" }

    local popup = api_mod.peek {
      filename = path,
      lnum = 3,
      col = 2,
    }

    assert.is_not_nil(popup)
    assert.are.equal(vim.fn.bufnr(path), popup.opts.target_bufnr)
    assert.are.equal(3, popup.opts.lnum)
    assert.are.equal(2, popup.opts.col)
    assert.are.same({ 3, 1 }, popup_cursor(popup))
    assert.are.same({ "one", "two", "three" }, vim.api.nvim_buf_get_lines(popup.opts.target_bufnr, 0, -1, false))
    assert.are.equal(0, #notify_calls)
  end)

  it("opens a popup for a bufnr item", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "red", "green", "blue" })

    local popup = api_mod.peek {
      bufnr = buf,
      lnum = 2,
      col = 4,
    }

    assert.is_not_nil(popup)
    assert.are.equal(buf, popup.opts.target_bufnr)
    assert.are.equal(2, popup.opts.lnum)
    assert.are.equal(4, popup.opts.col)
    assert.are.same({ 2, 3 }, popup_cursor(popup))
    assert.are.same({ "red", "green", "blue" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.are.equal(0, #notify_calls)

    require("overlook.window").current():close_all()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("opens a popup for an on_list quickfix item", function()
    local path = write_temp { "alpha", "beta", "gamma" }
    local uri = vim.uri_from_fname(path)
    -- locations_to_items() shape: 1-based lnum/col, original LocationLink on user_data.
    -- A mismatched range proves lnum/col wins over the nested LSP position.
    local popup = api_mod.peek {
      filename = path,
      lnum = 2,
      col = 3,
      text = "beta",
      user_data = {
        targetUri = uri,
        targetSelectionRange = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 1 },
        },
        targetRange = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 2, character = 0 },
        },
      },
    }

    assert.is_not_nil(popup)
    assert.are.equal(vim.uri_to_bufnr(uri), popup.opts.target_bufnr)
    assert.are.equal(2, popup.opts.lnum)
    assert.are.equal(3, popup.opts.col)
    assert.are.same({ 2, 2 }, popup_cursor(popup))
    assert.are.equal(0, #notify_calls)
  end)

  it("handles an invalid item gracefully", function()
    local window = require("overlook.window").current()
    local before = window:size()
    local ok, popup = pcall(api_mod.peek, nil)
    assert.is_true(ok)
    assert.is_nil(popup)

    local items = {
      {},
      { lnum = 1, col = 1 },
      { filename = "/no/such/overlook/peek-location.lua", lnum = 1, col = 1 },
      { bufnr = -1, lnum = 1, col = 1 },
      { uri = "not a uri", range = { start = { line = 0, character = 0 } } },
    }
    for _, item in ipairs(items) do
      ok, popup = pcall(api_mod.peek, item)
      assert.is_true(ok)
      assert.is_nil(popup)
    end

    assert.are.equal(before, window:size())
    assert.are.equal(1 + #items, #notify_calls)
    for _, call in ipairs(notify_calls) do
      assert.are.equal(vim.log.levels.WARN, call.level)
      assert.matches("Overlook:", call.msg)
    end
  end)
end)
