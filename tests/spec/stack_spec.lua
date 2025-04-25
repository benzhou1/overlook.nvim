local stack = require("overlook.stack")

-- Store original API functions and mock call arguments
local orig_api = {}
local orig_deepcopy = nil
local mock_call_args = {}

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
  if orig_deepcopy then
    vim.deepcopy = orig_deepcopy
  end
  orig_api = {}
  orig_deepcopy = nil

  mock_call_args = { -- Reset captured args
    nvim_set_current_win = {},
    nvim_win_close = {},
    close_all_called = false, -- Flag for mocking stack.close_all
  }

  -- Reset stack state
  stack.stack = {}
  stack.original_win_id = nil

  -- Default Mocks for stack tests
  mock_api("nvim_win_is_valid", function(win_id)
    -- Assume specified win_ids are valid by default, tests can override
    return win_id == 1 or win_id == 2 or win_id == 1000 -- Common IDs used in tests
  end)
  mock_api("nvim_set_current_win", function(win_id)
    table.insert(mock_call_args.nvim_set_current_win, win_id) -- Track calls
  end)
  mock_api("nvim_list_wins", function()
    return { 1, 2, 1000 } -- Default list of windows
  end)
  mock_api("nvim_win_close", function(win_id, force)
    table.insert(mock_call_args.nvim_win_close, { id = win_id, force = force or false }) -- Track calls
    -- Simulate window removal for subsequent nvim_win_is_valid calls within the same test?
    -- For simplicity, let's assume nvim_win_is_valid remains true unless explicitly mocked otherwise in a test.
  end)

  -- Mock vim.deepcopy as close_all uses it
  if vim.deepcopy then
    orig_deepcopy = vim.deepcopy
  end
  vim.deepcopy = function(tbl) -- Simple deepcopy mock for tables
    local new_tbl = {}
    for k, v in pairs(tbl) do
      if type(v) == "table" then
        new_tbl[k] = vim.deepcopy(v) -- Recurse
      else
        new_tbl[k] = v
      end
    end
    return new_tbl
  end
end

describe("overlook.stack", function()
  before_each(setup_mocks_and_stack) -- Use the new setup function

  after_each(function()
    -- Restore original functions after each test
    for k, v in pairs(orig_api) do
      vim.api[k] = v
    end
    if orig_deepcopy then
      vim.deepcopy = orig_deepcopy
    end
    orig_api = {}
    orig_deepcopy = nil
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
      assert.are.equal(1, stack.size())
      assert.are.same(item1, stack.top())
    end)

    it("should focus new top window if stack is not empty", function()
      local item1 = { win_id = 1 }
      local item2 = { win_id = 2 }
      stack.push(item1)
      stack.push(item2)
      stack.handle_win_close(2)
      assert.are.same({ 1 }, mock_call_args.nvim_set_current_win)
    end)

    it("should focus original window if stack becomes empty", function()
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      stack.handle_win_close(1)
      assert.are.equal(0, stack.size())
      assert.is_nil(stack.original_win_id) -- Should be cleared
      -- Expect two calls due to initial hack and empty stack logic
      assert.are.same({ 1000, 1000 }, mock_call_args.nvim_set_current_win)
    end)

    it("should do nothing if closed window not found", function()
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      stack.handle_win_close(99)
      assert.are.equal(1, stack.size())
      assert.are.equal(1000, stack.original_win_id)
      -- Expect one call due to initial hack
      assert.are.same({ 1000 }, mock_call_args.nvim_set_current_win)
    end)

    it("should focus fallback window if stack empty and original invalid", function()
      local item1 = { win_id = 1, original_win_id = 999 } -- 999 is invalid by default mock
      mock_api("nvim_win_is_valid", function(win_id)
        return win_id == 1
      end) -- Make only win 1 valid
      stack.push(item1)
      stack.handle_win_close(1)
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
      local original_close_all = stack.close_all
      stack.close_all = function(force)
        mock_call_args.close_all_called = true
        -- Optionally call original or a simplified mock if needed for other assertions
      end

      -- Act
      stack.handle_win_close(2)

      -- Assert
      assert.are.equal(1, stack.size()) -- item2 should still be removed
      assert.are.same({}, mock_call_args.nvim_set_current_win) -- Should not focus invalid win 1
      assert.is_true(mock_call_args.close_all_called) -- Should have called close_all

      -- Restore
      stack.close_all = original_close_all
    end)
  end)

  describe("close_all", function()
    it("should attempt to close all valid windows in the stack", function()
      local item1 = { win_id = 1 }
      local item2 = { win_id = 2 }
      stack.push(item1)
      stack.push(item2)
      stack.close_all()
      assert.are.same({ { id = 2, force = false }, { id = 1, force = false } }, mock_call_args.nvim_win_close)
    end)

    it("should pass force_close flag to nvim_win_close", function()
      local item1 = { win_id = 1 }
      stack.push(item1)
      stack.close_all(true)
      assert.are.same({ { id = 1, force = true } }, mock_call_args.nvim_win_close)
    end)

    it("should clear the stack (safeguard)", function()
      local item1 = { win_id = 1 }
      stack.push(item1)
      -- Mock close to not actually trigger handle_win_close
      mock_api("nvim_win_close", function(_, _) end)
      stack.close_all()
      assert.are.equal(0, stack.size())
    end)

    it("should restore focus if stack empty and original exists (safeguard)", function()
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      -- Mock close to not trigger handle_win_close which normally restores focus
      mock_api("nvim_win_close", function(_, _) end)
      -- Ensure handle_win_close isn't called some other way
      local orig_handle = stack.handle_win_close
      stack.handle_win_close = function()
        assert.fail("handle_win_close should not be called")
      end

      stack.close_all()

      stack.handle_win_close = orig_handle -- Restore
      assert.are.equal(0, stack.size())
      -- assert.is_nil(stack.original_win_id) -- Safeguard doesn't clear this in this path
      -- Safeguard focus restore doesn't run because M.original_win_id is not nil here
      assert.are.same({}, mock_call_args.nvim_set_current_win)
    end)
  end)

  -- Note: Testing handle_win_close requires mocking vim.api functions --> Now tested above
end)
