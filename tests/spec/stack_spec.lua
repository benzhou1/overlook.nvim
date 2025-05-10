local stack = require("overlook.stack")
local state = require("overlook.state")

-- Store original API functions and mock call arguments
local orig_api = {}
local orig_deepcopy = nil
local orig_fn = {} -- For mocking vim.fn
local mock_call_args = {}

-- Save original keymap APIs
local orig_keymap_set = vim.keymap.set
local orig_keymap_del = vim.keymap.del
local orig_keymap_get = vim.keymap.get

-- Store original schedule and variable to hold scheduled function
local original_schedule = vim.schedule
local scheduled_function = nil
local current_win_override = nil -- Variable for overriding current window

-- Helper to mock vim.api functions
local function mock_api(name, mock_fn)
  if vim.api[name] then
    orig_api[name] = vim.api[name]
  end
  vim.api[name] = mock_fn
end

-- Helper to reset mocks and stack state before each test
local function setup_mocks_and_stack()
  -- Restore original functions before applying mocks
  for k, v in pairs(orig_api) do
    vim.api[k] = v
  end
  for k, v in pairs(orig_fn) do
    vim.fn[k] = v
  end
  if orig_deepcopy then
    vim.deepcopy = orig_deepcopy
  end
  orig_api = {}
  orig_fn = {}
  orig_deepcopy = nil
  scheduled_function = nil -- Ensure reset at start
  current_win_override = nil -- Reset override

  mock_call_args = { -- Reset captured args
    nvim_set_current_win = {},
    nvim_win_close = {},
    close_all_called = false, -- Flag for mocking stack.close_all
    keymap_set = {}, -- Rename for clarity
    keymap_del = {}, -- Rename for clarity
    keymap_get = {}, -- Track get calls
    nvim_win_get_buf = {}, -- Track get_buf calls
  }

  -- Reset stack state
  stack.stack = {}
  stack.original_win_id = nil

  -- Mock nvim_get_current_win using override variable and a default
  local default_current_mocked_win = 1 -- Default start window for tests
  mock_api("nvim_get_current_win", function()
    return current_win_override or default_current_mocked_win
  end)

  -- Mock nvim_set_current_win to update the override or default value
  mock_api("nvim_set_current_win", function(win_id)
    table.insert(mock_call_args.nvim_set_current_win, win_id)
    default_current_mocked_win = win_id
  end)

  mock_api("nvim_win_is_valid", function(win_id)
    return win_id == 1 or win_id == 2 or win_id == 1000
  end)
  mock_api("nvim_list_wins", function()
    return { 1, 2, 1000 }
  end)
  mock_api("nvim_win_close", function(win_id, force)
    table.insert(mock_call_args.nvim_win_close, { id = win_id, force = force or false })
  end)
  -- Mock keymap.set and keymap.del to capture plugin calls
  vim.keymap.set = function(mode, lhs, rhs, opts)
    table.insert(mock_call_args.keymap_set, {
      bufnr = opts.buffer,
      mode = mode,
      lhs = lhs,
      rhs = rhs,
      opts = opts,
    })
  end
  vim.keymap.del = function(mode, lhs, opts)
    table.insert(mock_call_args.keymap_del, {
      bufnr = opts.buffer,
      mode = mode,
      lhs = lhs,
      opts = opts,
    })
  end

  -- Mock win_get_buf to associate windows with buffers used in tests
  mock_api("nvim_win_get_buf", function(win_id)
    table.insert(mock_call_args.nvim_win_get_buf, { win_id = win_id })
    if win_id == 1 then
      return 10 -- popup_win -> popup_buf
    elseif win_id == 2 then
      return 20 -- other_win -> other_buf (for cleanup tests)
    elseif win_id == 1000 then
      return 30 -- original_win_id (fallback) -> some buf
    end
    return 99 -- Default unknown buffer
  end)

  -- Mock buffer validity
  mock_api("nvim_buf_is_valid", function(buf_id)
    -- Revert to simpler validity check if needed, or keep broad one
    -- Make sure all buffers potentially returned by nvim_win_get_buf mock are valid
    return buf_id == 10 or buf_id == 20 or buf_id == 30 or buf_id == 99
  end)

  -- Mock buffer name retrieval
  mock_api("nvim_buf_get_name", function(buf_id)
    if buf_id == 10 then
      return "/path/to/buffer10.txt"
    end
    if buf_id == 20 then
      return "/path/to/buffer20.txt"
    end
    if buf_id == 30 then
      return "/path/to/buffer30.txt"
    end
    if buf_id == 99 then
      return ""
    end -- Unnamed buffer
    -- Trigger error for unexpected buffer IDs during tests
    error("nvim_buf_get_name called with unexpected buffer id: " .. tostring(buf_id))
  end)

  -- Mock vim.deepcopy as close_all uses it
  if vim.deepcopy then
    orig_deepcopy = vim.deepcopy
  end

  -- No need to reset stack state here, before_each handles it

  -- Mock vim.schedule to capture the function
  vim.schedule = function(func)
    scheduled_function = func
  end
end

-- Helper to run the captured scheduled function
local function run_scheduled()
  if scheduled_function then
    local fn_to_run = scheduled_function
    scheduled_function = nil -- Clear before running to prevent re-entrancy issues
    fn_to_run()
  end
end

describe("overlook.stack", function()
  before_each(setup_mocks_and_stack)

  after_each(function()
    -- Restore original functions after each test
    for k, v in pairs(orig_api) do
      vim.api[k] = v
    end
    for k, v in pairs(orig_fn) do
      vim.fn[k] = v
    end
    if orig_deepcopy then
      vim.deepcopy = orig_deepcopy
    end
    orig_api = {}
    orig_fn = {}
    orig_deepcopy = nil
    -- Restore keymap.set, del, and get
    vim.keymap.set = orig_keymap_set
    vim.keymap.del = orig_keymap_del
    vim.keymap.get = orig_keymap_get
    -- Restore vim.schedule
    vim.schedule = original_schedule
    scheduled_function = nil
    -- No need to reset stack state here, before_each handles it
  end)

  it("should initialize with an empty stack", function()
    assert.are.equal(0, stack.size())
    assert.is_nil(stack.top())
    assert.is_nil(stack.original_win_id)
  end)

  it("should push items onto the stack", function()
    local item1 = { win_id = 1, buf_id = 10 }
    local item2 = { win_id = 2, buf_id = 20 }

    stack.push(item1)
    assert.are.equal(1, stack.size())
    assert.are.same(item1, stack.top())

    stack.push(item2)
    assert.are.equal(2, stack.size())
    assert.are.same(item2, stack.top())
  end)

  it("should store original_win_id only on first push", function()
    local item1 = { win_id = 1, buf_id = 10, original_win_id = 999 }
    local item2 = { win_id = 2, buf_id = 20, original_win_id = 888 }

    -- Push first item
    stack.push(item1)
    assert.are.equal(1, stack.size())
    assert.are.equal(999, stack.original_win_id) -- Should be set

    -- Push second item
    stack.push(item2)
    assert.are.equal(2, stack.size())
    assert.are.equal(999, stack.original_win_id) -- Should NOT be overwritten
  end)

  it("should not store original_win_id if not provided on first push", function()
    local item1 = { win_id = 1, buf_id = 10 } -- No original_win_id
    stack.push(item1)
    assert.are.equal(1, stack.size())
    assert.is_nil(stack.original_win_id)
  end)

  it("should find items by win_id", function()
    local item1 = { win_id = 1, buf_id = 10 }
    local item2 = { win_id = 2, buf_id = 20 }
    local item3 = { win_id = 3, buf_id = 30 }
    stack.push(item1)
    stack.push(item2)
    stack.push(item3)

    local found_item, found_index = stack.find_by_win(2)
    assert.are.same(item2, found_item)
    assert.are.equal(2, found_index) -- Check index

    local not_found_item, not_found_index = stack.find_by_win(99)
    assert.is_nil(not_found_item)
    assert.is_nil(not_found_index) -- Check index
  end)

  describe("handle_win_close", function()
    it("should remove closed window from stack", function()
      local item1 = { win_id = 1 }
      local item2 = { win_id = 2 }
      stack.push(item1)
      stack.push(item2)
      assert.are.equal(2, stack.size())
      stack.handle_win_close(2) -- Close top window
      run_scheduled() -- Run the potential keymap update
      assert.are.equal(1, stack.size())
      assert.are.same(item1, stack.top())
    end)

    it("should focus new top window if stack is not empty", function()
      local item1 = { win_id = 1 }
      local item2 = { win_id = 2 }
      stack.push(item1)
      stack.push(item2)
      stack.handle_win_close(2)
      run_scheduled() -- Run the potential keymap update
      assert.are.same({ 1 }, mock_call_args.nvim_set_current_win)
    end)

    it("should focus original window if stack becomes empty", function()
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      stack.handle_win_close(1)
      run_scheduled() -- Run the potential keymap update
      assert.are.equal(0, stack.size())
      assert.is_nil(stack.original_win_id) -- Should be cleared
      -- Expect ONLY ONE call now (no initial HACK)
      assert.are.same({ 1000 }, mock_call_args.nvim_set_current_win)
    end)

    it("should do nothing if closed window not found", function()
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      stack.handle_win_close(99)
      run_scheduled() -- Run the potential keymap update (should be nil)
      assert.are.equal(1, stack.size())
      assert.are.equal(1000, stack.original_win_id)
      -- Expect ZERO calls now (no initial HACK)
      assert.are.same({}, mock_call_args.nvim_set_current_win)
    end)

    it("should focus fallback window if stack empty and original invalid", function()
      local item1 = { win_id = 1, original_win_id = 999 } -- 999 is invalid by default mock
      mock_api("nvim_win_is_valid", function(win_id)
        return win_id == 1
      end) -- Make only win 1 valid
      stack.push(item1)
      stack.handle_win_close(1)
      run_scheduled() -- Run the potential keymap update
      assert.are.equal(0, stack.size())
      assert.is_nil(stack.original_win_id)
      -- Expect focus on first window from nvim_list_wins mock
      assert.are.same({ 1 }, mock_call_args.nvim_set_current_win)
    end)

    it("should call close_all if the next top window is invalid", function()
      -- Arrange
      local item1 = { win_id = 1 } -- This will be the next top, but invalid
      local item2 = { win_id = 2 } -- This will be closed
      stack.push(item1)
      stack.push(item2)

      -- Mock nvim_win_is_valid: win 2 is valid (so it can be found), win 1 is invalid
      mock_api("nvim_win_is_valid", function(win_id)
        return win_id == 2
      end)

      -- Mock stack.close_all to track if it was called
      local original_clear = stack.clear
      stack.clear = function(force)
        mock_call_args.close_all_called = true
        assert.is_true(force) -- Check that force=true is passed
        -- Optionally call original or a simplified mock if needed for other assertions
      end

      -- Act
      stack.handle_win_close(2)
      -- Don't run scheduled here, as close_all should be called instead of setting focus
      -- The schedule call inside close_all will be handled if we test close_all directly

      -- Assert
      assert.are.equal(1, stack.size()) -- item2 should still be removed
      assert.are.same({}, mock_call_args.nvim_set_current_win) -- Should not focus invalid win 1
      assert.is_true(mock_call_args.close_all_called) -- Should have called close_all

      -- Restore
      stack.clear = original_clear
    end)

    describe("on_stack_empty hook", function()
      local hook_called
      local config_mod
      local notify_calls
      local original_notify = vim.notify -- Store original globally

      before_each(function()
        hook_called = false
        config_mod = require("overlook.config")
        config_mod.options.on_stack_empty = function()
          hook_called = true
        end
        setup_mocks_and_stack() -- Resets other mocks

        -- Mock vim.notify globally for this block
        notify_calls = {}
        vim.notify = function(msg, level, opts)
          table.insert(notify_calls, { msg = msg, level = level, opts = opts })
        end
      end)

      after_each(function()
        config_mod.options.on_stack_empty = nil
        vim.notify = original_notify -- Restore original globally
        -- No need to handle orig_api["vim.notify"] anymore
      end)

      it("should call on_stack_empty when stack becomes empty", function()
        local item1 = { win_id = 1, original_win_id = 1000 }
        stack.push(item1)
        stack.handle_win_close(1)
        run_scheduled() -- Run the potential keymap update
        assert.is_true(hook_called)
      end)

      it("should NOT call on_stack_empty if stack does not become empty", function()
        local item1 = { win_id = 1, original_win_id = 1000 }
        local item2 = { win_id = 2 }
        stack.push(item1)
        stack.push(item2)
        stack.handle_win_close(2) -- Only close the top one
        run_scheduled() -- Run the potential keymap update
        assert.are.equal(1, stack.size())
        assert.is_false(hook_called)
      end)

      it("should NOT call on_stack_empty if hook is not defined", function()
        config_mod.options.on_stack_empty = nil -- Undefine the hook
        local item1 = { win_id = 1, original_win_id = 1000 }
        stack.push(item1)
        stack.handle_win_close(1)
        run_scheduled() -- Run the potential keymap update
        assert.is_false(hook_called) -- hook_called flag remains false
      end)

      it("should catch errors in user hook and notify", function()
        config_mod.options.on_stack_empty = function()
          error("User hook error!") -- Simulate error
        end

        local item1 = { win_id = 1, original_win_id = 1000 }
        stack.push(item1)
        stack.handle_win_close(1)
        run_scheduled() -- Run the potential keymap update

        assert.is_false(hook_called)
        assert.are.equal(1, #notify_calls)
        assert.matches("on_stack_empty callback failed: .*User hook error!", notify_calls[1].msg)
        assert.are.equal(vim.log.levels.ERROR, notify_calls[1].level)
      end)
    end)

    it("should trigger keymap cleanup via update_overlook_keymap_state", function()
      -- Arrange: Setup stack
      local item1 = { win_id = 1, buf_id = 10, original_win_id = 1000 }
      local item2 = { win_id = 2, buf_id = 20 } -- Top window
      stack.push(item1)
      stack.push(item2)

      -- Simulate state where popup (win 2) is focused and keymap was set
      current_win_override = 2 -- Use override variable
      state.update_keymap()
      -- Reset mocks potentially affected by the setup run, except for the keymap state
      mock_call_args.nvim_buf_get_name = {}
      assert.are.equal(1, #mock_call_args.keymap_set) -- Verify setup call worked
      assert.are.equal(20, mock_call_args.keymap_set[1].bufnr)
      current_win_override = nil -- Make sure override is off before next step

      -- Mock the state AFTER close: focus moves to win 1 (via default mock update)

      -- Act: Close the top window (win 2)
      stack.handle_win_close(2)

      -- Simulate running the scheduled function
      run_scheduled()

      -- Assert: Check that keymap was deleted
      assert.are.equal(1, #mock_call_args.keymap_del) -- Should be exactly one deletion
      assert.are.equal(20, mock_call_args.keymap_del[1].bufnr) -- Deleted from buf 20
      assert.are.equal("q", mock_call_args.keymap_del[1].lhs) -- Assuming default key
    end)
  end)

  describe("close_all", function()
    it("should attempt to close all valid windows in the stack", function()
      local item1 = { win_id = 1 }
      local item2 = { win_id = 2 }
      stack.push(item1)
      stack.push(item2)
      stack.clear()
      run_scheduled() -- Run the potential keymap update after close_all
      assert.are.same({ { id = 2, force = false }, { id = 1, force = false } }, mock_call_args.nvim_win_close)
    end)

    it("should pass force_close flag to nvim_win_close", function()
      local item1 = { win_id = 1 }
      stack.push(item1)
      stack.clear(true)
      run_scheduled() -- Run the potential keymap update after close_all
      assert.are.same({ { id = 1, force = true } }, mock_call_args.nvim_win_close)
    end)

    it("should clear the stack (safeguard)", function()
      local item1 = { win_id = 1 }
      stack.push(item1)
      -- Mock close to not actually trigger handle_win_close
      mock_api("nvim_win_close", function(_, _) end)
      stack.clear()
      run_scheduled() -- Run the potential keymap update after close_all
      assert.are.equal(0, stack.size())
    end)

    it("should restore focus if stack empty and original exists (safeguard)", function()
      -- Setup with original window ID
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      stack.clear()
      run_scheduled() -- Run the potential keymap update after close_all
      assert.are.equal(0, stack.size()) -- Stack should be empty
      assert.are.same({ 1000 }, mock_call_args.nvim_set_current_win) -- Check focus call
    end)

    it("should NOT restore focus if stack empty and original missing", function()
      -- Setup without original window ID
      local item1 = { win_id = 1 }
      stack.push(item1)
      stack.clear()
      run_scheduled() -- Run the potential keymap update after close_all
      assert.are.equal(0, stack.size())
      assert.are.same({}, mock_call_args.nvim_set_current_win) -- No focus call expected
    end)

    it("should trigger keymap cleanup via update_overlook_keymap_state", function()
      -- Arrange: Setup stack
      local item1 = { win_id = 1, buf_id = 10, original_win_id = 1000 }
      stack.push(item1)

      -- Simulate state where popup (win 1) is focused and keymap was set
      current_win_override = 1 -- Use override variable
      state.update_keymap()
      -- Reset mocks potentially affected by the setup run
      mock_call_args.nvim_buf_get_name = {}
      assert.are.equal(1, #mock_call_args.keymap_set) -- Verify setup call worked
      assert.are.equal(10, mock_call_args.keymap_set[1].bufnr)
      current_win_override = nil -- Make sure override is off for next step

      -- Mock the state AFTER close: focus moves to original window (1000) (via default mock update)

      -- Act: Close all windows
      stack.clear()

      -- Simulate running the scheduled function
      run_scheduled()

      -- Assert: Check that keymap was deleted
      assert.are.equal(1, #mock_call_args.keymap_del) -- Should be exactly one deletion
      assert.are.equal(10, mock_call_args.keymap_del[1].bufnr) -- Deleted from buf 10
      assert.are.equal("q", mock_call_args.keymap_del[1].lhs) -- Assuming default key
    end)
  end)
end)
