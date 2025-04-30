describe("Cursor Adapter", function()
  local peek_mod = require("overlook.peek")
  local ui_mod = require("overlook.ui")

  local original_create_popup
  local original_notify
  local mock_calls

  before_each(function()
    -- Reset mock calls table
    mock_calls = {
      create_popup = {},
      notify = {},
    }

    -- Store and mock ui.create_popup
    original_create_popup = ui_mod.create_popup
    ui_mod.create_popup = function(opts)
      table.insert(mock_calls.create_popup, opts)
    end

    -- Store and mock vim.notify
    original_notify = vim.notify
    vim.notify = function(msg, level, opts)
      table.insert(mock_calls.notify, { msg = msg, level = level, opts = opts })
    end
  end)

  after_each(function()
    -- Restore original functions
    if original_create_popup then
      ui_mod.create_popup = original_create_popup
    end
    if original_notify then
      vim.notify = original_notify
    end
    original_create_popup = nil
    original_notify = nil

    -- Clean up any test buffers if needed
    pcall(vim.cmd, "bw! test_buffer.txt")
    pcall(vim.cmd, "bw!") -- For unnamed buffer test
  end)

  it("should call create_popup with cursor context when peek('cursor') is called", function()
    -- Setup: Create a dummy buffer and set content
    vim.cmd("edit! test_buffer.txt")
    local expected_bufnr = vim.api.nvim_get_current_buf() -- Get the buffer number
    vim.api.nvim_buf_set_lines(expected_bufnr, 0, -1, false, {
      "line 1",
      "line 2",
      "line 3 is the cursor line",
      "line 4",
      "line 5",
    })
    vim.api.nvim_win_set_cursor(0, { 3, 5 }) -- Set cursor to line 3, column 5

    -- Action
    peek_mod.peek("cursor")

    -- Assert
    assert.are.equal(1, #mock_calls.create_popup)
    local call_args = mock_calls.create_popup[1]
    assert.is_table(call_args)
    assert.matches("test_buffer.txt", call_args.title) -- Expect filename again
    assert.are.equal(0, call_args.target_bufnr) -- Check target_bufnr should be 0
    assert.are.equal(3, call_args.lnum)
    assert.are.equal(6, call_args.col) -- Keep expected column as 6
    assert.matches("test_buffer.txt", call_args.file_path) -- Check file_path
    assert.is_nil(call_args.content) -- Should not have content
    assert.is_nil(call_args.highlight_line) -- Should not have highlight_line

    -- Teardown (moved to after_each)
    -- vim.cmd("bw! test_buffer.txt")
  end)

  it("should handle unnamed buffers gracefully", function()
    -- Setup: Create an unnamed buffer
    vim.cmd("enew")
    assert.equal("", vim.api.nvim_buf_get_name(0))

    -- Action
    peek_mod.peek("cursor")

    -- Assert
    assert.are.equal(0, #mock_calls.create_popup) -- Should not be called
    assert.are.equal(1, #mock_calls.notify)
    local notify_call = mock_calls.notify[1]
    assert.are.equal("Overlook: Cannot peek in unnamed buffer.", notify_call.msg)
    assert.are.equal(vim.log.levels.WARN, notify_call.level)

    -- Teardown (moved to after_each)
    -- vim.cmd("bw!")
  end)
end)
