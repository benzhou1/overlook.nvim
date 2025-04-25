local api = vim.api

describe("overlook.adapter.marks", function()
  local marks_adapter

  -- Mock vim.notify to check messages
  local notify_calls = {}
  local original_notify = vim.notify
  local mock_notify = function(msg, level, opts)
    table.insert(notify_calls, { msg = msg, level = level, opts = opts })
  end

  -- Mock buffer functions for specific test cases
  local original_buf_is_loaded = api.nvim_buf_is_loaded
  local original_buf_is_valid = api.nvim_buf_is_valid
  local original_buf_get_name = api.nvim_buf_get_name
  local original_getpos = vim.fn.getpos

  before_each(function()
    -- Reload the module before each test to reset state if necessary
    package.loaded["overlook.adapter.marks"] = nil
    marks_adapter = require("overlook.adapter.marks")
    notify_calls = {}
    vim.notify = mock_notify
    -- Reset mocks
    api.nvim_buf_is_loaded = original_buf_is_loaded
    api.nvim_buf_is_valid = original_buf_is_valid
    api.nvim_buf_get_name = original_buf_get_name
    vim.fn.getpos = original_getpos
  end)

  after_each(function()
    -- Restore original functions
    vim.notify = original_notify
    api.nvim_buf_is_loaded = original_buf_is_loaded
    api.nvim_buf_is_valid = original_buf_is_valid
    api.nvim_buf_get_name = original_buf_get_name
    vim.fn.getpos = original_getpos
    -- Clean up any marks set? (Potentially needed depending on tests)
  end)

  it("should return nil for invalid mark characters", function()
    assert.is_nil(marks_adapter.get(""))
    assert.are.equal(1, #notify_calls)
    assert.matches("Invalid mark character", notify_calls[1].msg)

    notify_calls = {} -- Reset for next check
    assert.is_nil(marks_adapter.get("ab"))
    assert.are.equal(1, #notify_calls)
    assert.matches("Invalid mark character", notify_calls[1].msg)

    notify_calls = {}
    assert.is_nil(marks_adapter.get(nil))
    assert.are.equal(1, #notify_calls)
    assert.matches("Invalid mark character", notify_calls[1].msg)
  end)

  it("should return nil if mark is not set", function()
    -- Mock getpos to simulate unset mark 'x'
    vim.fn.getpos = function(mark)
      if mark == "'x" then
        return { 0, 0, 0, 0 } -- Unset position
      end
      return original_getpos(mark)
    end

    assert.is_nil(marks_adapter.get("x"))
    assert.are.equal(1, #notify_calls)
    assert.matches("Mark 'x' is not set", notify_calls[1].msg)
  end)

  it("should return nil if buffer is not loaded", function()
    local mock_bufnr = 999
    -- Mock getpos to return a valid position but for a specific buffer
    vim.fn.getpos = function(mark)
      if mark == "'l" then
        return { mock_bufnr, 10, 5, 0 }
      end
      return original_getpos(mark)
    end
    -- Mock nvim_buf_is_loaded to return false for our mock buffer
    api.nvim_buf_is_loaded = function(bufnr)
      if bufnr == mock_bufnr then
        return false
      end
      return original_buf_is_loaded(bufnr)
    end

    assert.is_nil(marks_adapter.get("l"))
    assert.are.equal(1, #notify_calls)
    assert.matches("Buffer for mark 'l' is not loaded", notify_calls[1].msg)
  end)

  it("should return nil if buffer is not valid", function()
    local mock_bufnr = 998
    vim.fn.getpos = function(mark)
      if mark == "'v" then
        return { mock_bufnr, 20, 1, 0 }
      end
      return original_getpos(mark)
    end
    api.nvim_buf_is_loaded = function(bufnr)
      if bufnr == mock_bufnr then
        return true
      end -- Assume loaded
      return original_buf_is_loaded(bufnr)
    end
    api.nvim_buf_is_valid = function(bufnr)
      if bufnr == mock_bufnr then
        return false
      end -- But invalid
      return original_buf_is_valid(bufnr)
    end

    assert.is_nil(marks_adapter.get("v"))
    assert.are.equal(1, #notify_calls)
    assert.matches("Buffer for mark 'v' .* is invalid", notify_calls[1].msg)
  end)

  it("should return opts table for a valid mark", function()
    -- Setup a valid mark 'a' (e.g., pointing to current buffer, line 5, col 3)
    local current_bufnr = api.nvim_get_current_buf()
    local current_buf_name = api.nvim_buf_get_name(current_bufnr)
    local expected_lnum = 5
    local expected_col = 3

    vim.fn.getpos = function(mark)
      if mark == "'a" then
        return { current_bufnr, expected_lnum, expected_col, 0 }
      end
      return original_getpos(mark)
    end
    -- Ensure buffer is considered loaded and valid for this test
    api.nvim_buf_is_loaded = function(bufnr)
      if bufnr == current_bufnr then
        return true
      end
      return original_buf_is_loaded(bufnr)
    end
    api.nvim_buf_is_valid = function(bufnr)
      if bufnr == current_bufnr then
        return true
      end
      return original_buf_is_valid(bufnr)
    end
    api.nvim_buf_get_name = function(bufnr)
      if bufnr == current_bufnr then
        return current_buf_name
      end
      return original_buf_get_name(bufnr)
    end

    local opts = marks_adapter.get("a")
    assert.is_table(opts)
    assert.are.equal(current_bufnr, opts.target_bufnr)
    assert.are.equal(expected_lnum, opts.lnum)
    assert.are.equal(expected_col, opts.col)
    assert.is_string(opts.title)
    assert.matches(vim.fn.fnamemodify(current_buf_name, ":t"), opts.title) -- Check title contains filename
    assert.are.equal(0, #notify_calls) -- No errors expected
  end)
end)
