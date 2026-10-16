describe("overlook.peek.definition", function()
  local definition
  local open_popup_calls
  local notify_calls
  local select_calls
  local seen_uris
  local created_dirs
  local on_multiple
  local original_notify
  local original_lsp_definition
  local original_uri_to_bufnr
  local original_ui_select
  local original_config

  local function lsp_item(overrides)
    return vim.tbl_extend("force", {
      lnum = 1,
      col = 1,
      filename = "target.lua",
      text = "return target",
      user_data = {},
    }, overrides or {})
  end

  -- Real files: list opening goes through M.peek, which rejects a URI whose
  -- file is not readable. The file is reached through a symlink so the path
  -- on the item differs from the buffer name. Neovim resolves that symlink
  -- when it loads the buffer (/var -> /private/var on macOS is the same case).
  local function temp_source(name, nlines)
    local real_dir = vim.fn.tempname()
    vim.fn.mkdir(real_dir, "p")
    local link = vim.fn.tempname()
    local linked, err = vim.uv.fs_symlink(real_dir, link)
    if not linked then
      error("temp symlink failed: " .. tostring(err))
    end
    local path = link .. "/" .. name
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local lines = {}
    for i = 1, nlines or 20 do
      lines[i] = "line " .. i
    end
    vim.fn.writefile(lines, path)
    table.insert(created_dirs, link)
    table.insert(created_dirs, real_dir)
    return path, vim.uri_from_fname(path)
  end

  local function one_definition()
    local path, uri = temp_source("target.lua", 12)
    return {
      lnum = 12,
      col = 7,
      filename = path,
      user_data = { uri = uri },
    }, uri
  end

  local function two_definitions()
    local cpp, cpp_uri = temp_source("src/widget.cpp", 12)
    local header, header_uri = temp_source("src/widget.h", 8)
    local first = lsp_item {
      filename = cpp,
      lnum = 10,
      col = 3,
      text = "  void Widget::draw()",
      user_data = { uri = cpp_uri },
    }
    local second = lsp_item {
      filename = header,
      lnum = 4,
      col = 8,
      text = "void Widget::draw();",
      user_data = { targetUri = header_uri },
    }
    return first, second
  end

  -- Title is the buffer name (`:~:.`), which is the resolved path.
  local function popup_title(path)
    return vim.fn.fnamemodify(vim.fn.resolve(path), ":~:.")
  end

  before_each(function()
    open_popup_calls = {}
    notify_calls = {}
    select_calls = {}
    seen_uris = {}
    created_dirs = {}
    on_multiple = "first"

    package.loaded["overlook.window"] = {
      open_popup = function(opts)
        table.insert(open_popup_calls, opts)
      end,
    }

    original_config = package.loaded["overlook.config"]
    package.loaded["overlook.config"] = {
      get = function()
        return { on_multiple = on_multiple }
      end,
    }

    original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    original_ui_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      table.insert(select_calls, { items = items, opts = opts, on_choice = on_choice })
    end

    original_lsp_definition = vim.lsp.buf.definition
    original_uri_to_bufnr = vim.uri_to_bufnr
    vim.uri_to_bufnr = function(uri)
      table.insert(seen_uris, uri)
      return original_uri_to_bufnr(uri)
    end

    package.loaded["overlook.peek.location"] = nil
    package.loaded["overlook.peek.definition"] = nil
    definition = require("overlook.peek.definition")
  end)

  after_each(function()
    vim.notify = original_notify
    vim.ui.select = original_ui_select
    vim.lsp.buf.definition = original_lsp_definition
    vim.uri_to_bufnr = original_uri_to_bufnr
    package.loaded["overlook.config"] = original_config
    package.loaded["overlook.window"] = nil
    package.loaded["overlook.peek.location"] = nil
    package.loaded["overlook.peek.definition"] = nil
    for _, dir in ipairs(created_dirs) do
      vim.fn.delete(dir, "rf")
    end
  end)

  it("opens a popup directly when there is a single result and on_multiple is select", function()
    on_multiple = "select"
    local item, uri = one_definition()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { item } }
    end

    definition()

    assert.are.equal(0, #select_calls)
    assert.are.equal(1, #open_popup_calls)
    local o = open_popup_calls[1]
    assert.are.equal(original_uri_to_bufnr(uri), o.target_bufnr)
    assert.are.equal(12, o.lnum)
    assert.are.equal(7, o.col)
    assert.are.equal(popup_title(item.filename), o.title)
    assert.are.equal(uri, seen_uris[1])
    assert.are.equal(0, #notify_calls)
  end)

  it("opens a popup directly when there is a single result and on_multiple is a function", function()
    local called = false
    on_multiple = function()
      called = true
    end
    local item = one_definition()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { item } }
    end

    definition()

    assert.is_false(called)
    assert.are.equal(0, #select_calls)
    assert.are.equal(1, #open_popup_calls)
    assert.are.equal(12, open_popup_calls[1].lnum)
    assert.are.equal(popup_title(item.filename), open_popup_calls[1].title)
    assert.are.equal(0, #notify_calls)
  end)

  it("opens a popup directly when there is a single result", function()
    local item, uri = one_definition()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { item } }
    end

    definition()

    assert.are.equal(0, #select_calls)
    assert.are.equal(1, #open_popup_calls)
    local o = open_popup_calls[1]
    assert.are.equal(original_uri_to_bufnr(uri), o.target_bufnr)
    assert.are.equal(12, o.lnum)
    assert.are.equal(7, o.col)
    assert.are.equal(popup_title(item.filename), o.title)
    assert.are.equal(uri, seen_uris[1])
    assert.are.equal(0, #notify_calls)
  end)

  it("prompts with vim.ui.select for multiple results and opens the choice", function()
    on_multiple = "select"
    local first, second = two_definitions()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, second } }
    end

    definition()

    assert.are.equal(1, #select_calls)
    assert.are.equal(0, #open_popup_calls)
    assert.are.equal(0, #notify_calls)

    local call = select_calls[1]
    assert.are.equal(first, call.items[1])
    assert.are.equal(second, call.items[2])
    assert.are.equal("Overlook: Select definition", call.opts.prompt)
    assert.are.equal("overlook.definition", call.opts.kind)
    assert.are.equal(
      vim.fn.fnamemodify(first.filename, ":.") .. ":10: void Widget::draw()",
      call.opts.format_item(first)
    )
    assert.are.equal(
      vim.fn.fnamemodify(second.filename, ":.") .. ":4: void Widget::draw();",
      call.opts.format_item(second)
    )

    call.on_choice(second)

    assert.are.equal(1, #open_popup_calls)
    local o = open_popup_calls[1]
    assert.are.equal(original_uri_to_bufnr(second.user_data.targetUri), o.target_bufnr)
    assert.are.equal(4, o.lnum)
    assert.are.equal(8, o.col)
    assert.are.equal(popup_title(second.filename), o.title)
    assert.are.equal(second.user_data.targetUri, seen_uris[1])
  end)

  it("opens nothing when vim.ui.select is cancelled", function()
    on_multiple = "select"
    local first, second = two_definitions()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, second } }
    end

    definition()
    select_calls[1].on_choice(nil)

    assert.are.equal(0, #open_popup_calls)
    assert.are.equal(0, #notify_calls)
  end)

  it("opens the first location by default when several results match", function()
    local first, second = two_definitions()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, second } }
    end

    definition()

    assert.are.equal(0, #select_calls)
    assert.are.equal(1, #open_popup_calls)
    assert.are.equal(10, open_popup_calls[1].lnum)
    assert.are.equal(3, open_popup_calls[1].col)
    assert.are.equal(popup_title(first.filename), open_popup_calls[1].title)
    assert.are.equal(first.user_data.uri, seen_uris[1])
    assert.are.equal(0, #notify_calls)
  end)

  it("treats a missing on_multiple as first", function()
    on_multiple = nil
    local first, second = two_definitions()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, second } }
    end

    definition()

    assert.are.equal(0, #select_calls)
    assert.are.equal(1, #open_popup_calls)
    assert.are.equal(popup_title(first.filename), open_popup_calls[1].title)
  end)

  it("calls a custom on_multiple function with the items and an opener", function()
    local seen
    on_multiple = function(items, open_fn)
      seen = { items = items, open_fn = open_fn }
      open_fn(items[2])
    end
    local first, second = two_definitions()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, second } }
    end

    definition()

    assert.are.equal(0, #select_calls)
    assert.are.equal(first, seen.items[1])
    assert.are.equal(second, seen.items[2])
    assert.are.equal("function", type(seen.open_fn))
    assert.are.equal(1, #open_popup_calls)
    assert.are.equal(4, open_popup_calls[1].lnum)
    assert.are.equal(second.user_data.targetUri, seen_uris[1])
    assert.are.equal(0, #notify_calls)
  end)

  it("opens nothing when a custom handler calls open_fn(nil)", function()
    on_multiple = function(items, open_fn)
      open_fn(nil)
    end
    local first, second = two_definitions()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, second } }
    end

    definition()

    assert.are.equal(0, #select_calls)
    assert.are.equal(0, #open_popup_calls)
    assert.are.equal(0, #notify_calls)
  end)

  it("falls back to first when on_multiple is not recognized", function()
    on_multiple = "quickfix"
    local first, second = two_definitions()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, second } }
    end

    definition()

    assert.are.equal(1, #notify_calls)
    assert.matches('using "first"', notify_calls[1].msg)
    assert.are.equal(vim.log.levels.WARN, notify_calls[1].level)
    assert.are.equal(0, #select_calls)
    assert.are.equal(1, #open_popup_calls)
    assert.are.equal(popup_title(first.filename), open_popup_calls[1].title)
    assert.are.equal(10, open_popup_calls[1].lnum)
  end)

  it("defaults on_multiple to first", function()
    local saved = package.loaded["overlook.config"]
    package.loaded["overlook.config"] = nil
    local config = require("overlook.config")

    assert.are.equal("first", config.get().on_multiple)
    config.setup()
    assert.are.equal("first", config.get().on_multiple)
    config.setup { ui = { border = "single" } }
    assert.are.equal("first", config.get().on_multiple)
    assert.are.equal(0, #notify_calls)

    local handler = function() end
    config.setup { on_multiple = handler }
    assert.are.equal(handler, config.get().on_multiple)
    assert.are.equal(0, #notify_calls)

    config.setup { on_multiple = "quickfix" }
    assert.are.equal("first", config.get().on_multiple)
    assert.are.equal(1, #notify_calls)
    assert.matches('using "first"', notify_calls[1].msg)
    assert.are.equal(vim.log.levels.WARN, notify_calls[1].level)

    package.loaded["overlook.config"] = saved
  end)

  it("opens one popup when duplicate locations share uri, line, and column", function()
    on_multiple = "select"
    local path, uri = temp_source("lib.lua", 4)
    local item = lsp_item {
      filename = path,
      lnum = 3,
      col = 12,
      text = "function M.widget()",
      user_data = { uri = uri },
    }
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { item, vim.deepcopy(item) } }
    end

    definition()

    assert.are.equal(0, #select_calls)
    assert.are.equal(1, #open_popup_calls)
    assert.are.equal(3, open_popup_calls[1].lnum)
    assert.are.equal(12, open_popup_calls[1].col)
    assert.are.equal(popup_title(item.filename), open_popup_calls[1].title)
    assert.are.equal(0, #notify_calls)
  end)

  it("dedupes by filename when an item has no uri and keeps the first of each location", function()
    on_multiple = "select"
    local cwd = vim.fn.getcwd()
    local first = lsp_item {
      filename = cwd .. "/src/widget.cpp",
      lnum = 10,
      col = 3,
      text = "  void Widget::draw()",
      user_data = {},
    }
    local same_place = vim.deepcopy(first)
    same_place.text = "different text, same location"
    local second = lsp_item {
      filename = cwd .. "/src/widget.h",
      lnum = 4,
      col = 8,
      text = "void Widget::draw();",
      user_data = { targetUri = "file:///src/widget.h" },
    }
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { first, same_place, second, vim.deepcopy(second) } }
    end

    definition()

    assert.are.equal(1, #select_calls)
    assert.are.equal(0, #open_popup_calls)
    assert.are.equal(2, #select_calls[1].items)
    assert.are.equal(first, select_calls[1].items[1])
    assert.are.equal(second, select_calls[1].items[2])
  end)

  it("forwards location opts and keeps Overlook's on_list handler", function()
    local received
    vim.lsp.buf.definition = function(o)
      received = o
      o.on_list { items = {} }
    end

    definition { reuse_win = true, on_list = function() end }

    assert.is_true(received.reuse_win)
    assert.are.equal(0, #open_popup_calls)
    assert.are.equal(1, #notify_calls)
    assert.matches("No definition found", notify_calls[1].msg)
  end)

  it("notifies INFO and does not open (no crash) on empty results", function()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = {} }
    end

    local ok = pcall(definition)

    assert.is_true(ok)
    assert.are.equal(0, #select_calls)
    assert.are.equal(0, #open_popup_calls)
    assert.are.equal(1, #notify_calls)
    assert.matches("No definition found", notify_calls[1].msg)
    assert.are.equal(vim.log.levels.INFO, notify_calls[1].level)
  end)

  it("notifies WARN and does not open when the item has no resolvable buffer", function()
    vim.lsp.buf.definition = function(o)
      o.on_list { items = { { lnum = 1, col = 1, filename = "/no/such/overlook/missing.lua", user_data = {} } } }
    end

    local ok = pcall(definition)

    assert.is_true(ok)
    assert.are.equal(0, #open_popup_calls)
    assert.are.equal(1, #notify_calls)
    assert.matches("could not resolve a buffer", notify_calls[1].msg)
    assert.are.equal(vim.log.levels.WARN, notify_calls[1].level)
  end)
end)
