local api = vim.api
local lsp = vim.lsp

describe("overlook.adapter.definition", function()
  local definition_adapter

  -- Mock relevant APIs
  local notify_calls = {}
  local original_notify = vim.notify
  local mock_notify = function(msg, level, opts)
    table.insert(notify_calls, { msg = msg, level = level, opts = opts })
  end

  local original_lsp_request_sync = lsp.buf_request_sync
  local mock_lsp_request_sync = function(bufnr, method, params, timeout)
    -- Default mock: No definition found
    return nil, nil -- result, err
  end

  local original_uri_to_bufnr = vim.uri_to_bufnr
  local mock_uri_to_bufnr = function(uri)
    if uri == "file:///path/to/definition.lua" then
      return 2
    end
    return 0
  end

  local original_uri_to_fname = vim.uri_to_fname
  local mock_uri_to_fname = function(uri)
    if uri == "file:///path/to/definition.lua" then
      return "/path/to/definition.lua"
    end
    return ""
  end

  local original_buf_is_valid = api.nvim_buf_is_valid
  local mock_buf_is_valid = function(bufnr)
    if bufnr == 2 then
      return true
    end -- Mock buffer 2 is valid
    return false
  end

  local original_win_get_buf = api.nvim_win_get_buf
  local original_win_get_cursor = api.nvim_win_get_cursor
  local original_get_current_win = api.nvim_get_current_win

  -- Add mock for lsp.util.make_position_params
  local original_make_position_params = lsp.util.make_position_params
  local mock_make_position_params = function(winid)
    -- Return a dummy but valid params structure
    return {
      textDocument = { uri = "file:///path/to/current.lua" }, -- Dummy URI
      position = { line = 4, character = 10 }, -- Dummy position (0-based)
    }
  end

  -- Add mock for vim.cmd
  local vim_cmd_calls = {}
  local original_vim_cmd = vim.cmd
  local mock_vim_cmd = function(cmd_str)
    table.insert(vim_cmd_calls, cmd_str)
  end

  before_each(function()
    -- Reset mocks and state
    notify_calls = {}
    vim.notify = mock_notify
    lsp.buf_request_sync = mock_lsp_request_sync
    lsp.util.make_position_params = mock_make_position_params
    vim.uri_to_bufnr = mock_uri_to_bufnr
    vim.uri_to_fname = mock_uri_to_fname
    api.nvim_buf_is_valid = mock_buf_is_valid
    vim.cmd = mock_vim_cmd
    vim_cmd_calls = {}
    api.nvim_get_current_win = function()
      return 1
    end
    api.nvim_win_get_buf = function(win)
      if win == 1 then
        return 1
      end
      return 0
    end
    api.nvim_win_get_cursor = function(win)
      if win == 1 then
        return { 5, 10 }
      end
      return { 0, 0 }
    end

    -- Reload the adapter module (re-added)
    package.loaded["overlook.adapter.definition"] = nil
    definition_adapter = require("overlook.adapter.definition")
  end)

  after_each(function()
    -- Restore original functions
    vim.notify = original_notify
    lsp.buf_request_sync = original_lsp_request_sync
    vim.uri_to_bufnr = original_uri_to_bufnr
    vim.uri_to_fname = original_uri_to_fname
    api.nvim_buf_is_valid = original_buf_is_valid
    api.nvim_win_get_buf = original_win_get_buf
    api.nvim_win_get_cursor = original_win_get_cursor
    api.nvim_get_current_win = original_get_current_win
    lsp.util.make_position_params = original_make_position_params -- Restore original
    vim.cmd = original_vim_cmd -- Restore original
  end)

  it("should return nil and notify if LSP request errors", function()
    lsp.buf_request_sync = function(...)
      return nil, "LSP timeout"
    end
    assert.is_nil(definition_adapter.get())
    assert.are.equal(1, #notify_calls)
    assert.matches("LSP Error: LSP timeout", notify_calls[1].msg)
  end)

  it("should return nil and notify if no definition is found", function()
    lsp.buf_request_sync = function(...)
      return {}, nil
    end -- Empty result table
    assert.is_nil(definition_adapter.get())
    assert.are.equal(1, #notify_calls)
    assert.matches("No definition found", notify_calls[1].msg)
  end)

  it("should return nil and notify if LSP result format is unexpected", function()
    lsp.buf_request_sync = function(...)
      return "invalid_format", nil
    end
    assert.is_nil(definition_adapter.get())
    assert.are.equal(1, #notify_calls)
    assert.matches("No definition found or unexpected LSP result format", notify_calls[1].msg)
  end)

  it("should return opts table for a valid definition (Location[])", function()
    local def_uri = "file:///path/to/definition.lua"
    local def_lnum = 19 -- 0-indexed
    local def_col = 4 -- 0-indexed
    local mock_location = {
      uri = def_uri,
      range = {
        start = { line = def_lnum, character = def_col },
      },
    }
    -- Mock LSP response wrapped in client ID structure
    lsp.buf_request_sync = function(...)
      return { [2] = { result = { mock_location } } }, nil
    end

    local opts = definition_adapter.get()
    assert.is_table(opts)
    assert.are.equal(2, opts.target_bufnr) -- From mock_uri_to_bufnr
    assert.are.equal(def_lnum + 1, opts.lnum)
    assert.are.equal(def_col + 1, opts.col)
    assert.matches("definition.lua", opts.title)
    assert.are.equal(0, #notify_calls)
  end)

  it("should return opts table for a valid definition (LocationLink)", function()
    local def_uri = "file:///path/to/definition.lua"
    local def_lnum = 25
    local def_col = 8
    local mock_result = {
      {
        targetUri = def_uri,
        targetSelectionRange = {
          start = { line = def_lnum, character = def_col },
        },
        -- other LocationLink fields ignored
      },
    }
    lsp.buf_request_sync = function(...)
      return { [2] = { result = mock_result } }, nil
    end

    local opts = definition_adapter.get()
    assert.is_table(opts)
    assert.are.equal(2, opts.target_bufnr)
    assert.are.equal(def_lnum + 1, opts.lnum)
    assert.are.equal(def_col + 1, opts.col)
    assert.matches("definition.lua", opts.title)
    assert.are.equal(0, #notify_calls)
  end)

  it("should return opts table for a valid definition (single Location)", function()
    local def_uri = "file:///path/to/definition.lua"
    local def_lnum = 50
    local def_col = 1
    local mock_result = {
      uri = def_uri,
      range = {
        start = { line = def_lnum, character = def_col },
      },
    }
    lsp.buf_request_sync = function(...)
      return { [1] = { result = mock_result } }, nil
    end

    local opts = definition_adapter.get()
    assert.is_table(opts)
    assert.are.equal(2, opts.target_bufnr)
    assert.are.equal(def_lnum + 1, opts.lnum)
    assert.are.equal(def_col + 1, opts.col)
    assert.matches("definition.lua", opts.title)
    assert.are.equal(0, #notify_calls)
  end)

  it("should attempt to load buffer if not initially valid", function()
    local def_uri = "file:///path/to/unloaded.lua"
    local def_filepath = "/path/to/unloaded.lua"
    local unloaded_bufnr = 3
    local mock_result = { uri = def_uri, range = { start = { line = 1, character = 1 } } }

    -- Mock LSP response (client ID keyed)
    lsp.buf_request_sync = function(...)
      return { [1] = { result = mock_result } }, nil
    end
    -- Mock URI conversion
    vim.uri_to_bufnr = function(uri)
      return (uri == def_uri) and unloaded_bufnr or 0
    end
    vim.uri_to_fname = function(uri)
      return (uri == def_uri) and def_filepath or ""
    end

    -- Mock buffer validity: invalid initially, valid after edit
    local is_valid_call_count = 0
    api.nvim_buf_is_valid = function(bufnr)
      if bufnr == unloaded_bufnr then
        is_valid_call_count = is_valid_call_count + 1
        return is_valid_call_count > 1 -- Return true only on the second call (after simulated edit)
      end
      return false
    end

    local opts = definition_adapter.get()

    -- Assertions
    assert.is_table(opts) -- Should succeed now
    assert.are.equal(1, #vim_cmd_calls) -- Check that vim.cmd was called
    assert.matches("edit " .. vim.fn.fnameescape(def_filepath), vim_cmd_calls[1]) -- Check the edit command
    assert.are.equal(unloaded_bufnr, opts.target_bufnr)
    assert.are.equal(0, #notify_calls) -- No errors expected
  end)

  -- Note: Test for buffer loading logic is omitted for brevity,
  -- but would involve mocking vim.cmd and api.nvim_buf_is_valid more elaborately.
end)
