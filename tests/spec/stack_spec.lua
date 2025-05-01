local stack = require("overlook.stack")

-- Store original API functions and mock call arguments
local orig_api = {}
local orig_deepcopy = nil
local mock_call_args = {}

-- Save original keymap APIs
local orig_keymap_set = vim.keymap.set
local orig_keymap_del = vim.keymap.del

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
    nvim_buf_set_keymap = {},
    nvim_buf_del_keymap = {},
    nvim_buf_get_keymap_calls = 0,
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
  -- Mock keymap.set and keymap.del to capture plugin calls
  vim.keymap.set = function(mode, lhs, rhs, opts)
    table.insert(mock_call_args.nvim_buf_set_keymap, {
      bufnr = opts.buffer,
      mode = mode,
      lhs = lhs,
      rhs = rhs,
      opts = opts,
    })
  end
  vim.keymap.del = function(mode, lhs, opts)
    table.insert(mock_call_args.nvim_buf_del_keymap, {
      bufnr = opts.buffer,
      mode = mode,
      lhs = lhs,
      opts = opts,
    })
  end

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
    -- Restore keymap.set and keymap.del
    vim.keymap.set = orig_keymap_set
    vim.keymap.del = orig_keymap_del
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
      -- Expect ONLY ONE call now (no initial HACK)
      assert.are.same({ 1000 }, mock_call_args.nvim_set_current_win)
    end)

    it("should do nothing if closed window not found", function()
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      stack.handle_win_close(99)
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
        assert.is_true(force) -- Check that force=true is passed
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
        assert.is_true(hook_called)
      end)

      it("should NOT call on_stack_empty if stack does not become empty", function()
        local item1 = { win_id = 1, original_win_id = 1000 }
        local item2 = { win_id = 2 }
        stack.push(item1)
        stack.push(item2)
        stack.handle_win_close(2) -- Only close the top one
        assert.are.equal(1, stack.size())
        assert.is_false(hook_called)
      end)

      it("should NOT call on_stack_empty if hook is not defined", function()
        config_mod.options.on_stack_empty = nil -- Undefine the hook
        local item1 = { win_id = 1, original_win_id = 1000 }
        stack.push(item1)
        stack.handle_win_close(1)
        assert.is_false(hook_called) -- hook_called flag remains false
      end)

      it("should catch errors in user hook and notify", function()
        config_mod.options.on_stack_empty = function()
          error("User hook error!") -- Simulate error
        end

        local item1 = { win_id = 1, original_win_id = 1000 }
        stack.push(item1)
        stack.handle_win_close(1)

        assert.is_false(hook_called)
        assert.are.equal(1, #notify_calls)
        assert.matches("on_stack_empty callback failed: .*User hook error!", notify_calls[1].msg)
        assert.are.equal(vim.log.levels.ERROR, notify_calls[1].level)
      end)
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
      -- Setup with original window ID
      local item1 = { win_id = 1, original_win_id = 1000 }
      stack.push(item1)
      stack.close_all()
      assert.are.equal(0, stack.size()) -- Stack should be empty
      assert.are.same({ 1000 }, mock_call_args.nvim_set_current_win) -- Check focus call
    end)

    it("should NOT restore focus if stack empty and original missing", function()
      -- Setup without original window ID
      local item1 = { win_id = 1 }
      stack.push(item1)
      stack.close_all()
      assert.are.equal(0, stack.size())
      assert.are.same({}, mock_call_args.nvim_set_current_win) -- No focus call expected
    end)
  end)

  describe("Keymap Tracking", function()
    local buf1 = 10
    local buf2 = 20
    local close_key = "q" -- Assuming default
    local original_map_buf1 = {
      key = close_key,
      mode = "n",
      map = {
        rhs = ":echo 'original q'<CR>",
        noremap = true,
        silent = false,
        script = false,
        expr = false,
        desc = "Original Q",
      },
    }
    local temp_map_rhs = "<Cmd>close<CR>"

    -- Ensure clean tracker state for these tests
    before_each(function()
      stack.reset_keymap_tracker()
    end)

    it("should create tracker entry correctly", function()
      stack.create_tracker_entry(buf1, original_map_buf1)
      local entry = stack.get_tracker_entry(buf1)
      assert.is_not_nil(entry)
      assert.are.equal(1, entry.ref_count)
      assert.are.same(original_map_buf1, entry.original_map_details)
    end)

    it("should increment ref count correctly", function()
      stack.create_tracker_entry(buf1, nil) -- Start with ref 1
      stack.increment_tracker_refcount(buf1)
      local entry = stack.get_tracker_entry(buf1)
      assert.are.equal(2, entry.ref_count)
    end)

    it("should handle incrementing non-existent entry gracefully", function()
      -- This test was flawed. Incrementing a non-existent entry should do nothing.
      -- Ensure tracker is empty first (handled by before_each now)
      -- stack.buffer_keymap_tracker = {}
      stack.increment_tracker_refcount(buf1)
      local entry = stack.get_tracker_entry(buf1)
      assert.is_nil(entry) -- Should still be nil
    end)

    describe("handle_win_close with keymaps", function()
      before_each(function()
        -- Mock config for close_key
        local config_mod = require("overlook.config")
        config_mod.options.ui.keys = { close = close_key }
        -- Setup initial state for keymap tests
        stack.create_tracker_entry(buf1, original_map_buf1) -- Buffer 1 has original map, ref 1
        stack.increment_tracker_refcount(buf1) -- Increment to ref 2 (simulating two popups)
        stack.create_tracker_entry(buf2, nil) -- Buffer 2 has no original map, ref 1
        -- Simulate the temporary map being set on both buffers
        vim.keymap.set(
          "n",
          close_key,
          temp_map_rhs,
          { buffer = buf1, noremap = true, silent = true, nowait = true, desc = "Overlook: Close popup" }
        )
        vim.keymap.set(
          "n",
          close_key,
          temp_map_rhs,
          { buffer = buf2, noremap = true, silent = true, nowait = true, desc = "Overlook: Close popup" }
        )
        -- Reset API call args specifically for these tests
        mock_call_args.nvim_buf_del_keymap = {}
        mock_call_args.nvim_buf_set_keymap = {}
      end)

      it("should decrement ref count but not restore map if count > 0", function()
        local item_buf1_win1 = { win_id = 1, buf_id = buf1 }
        local item_buf1_win2 = { win_id = 2, buf_id = buf1 }
        stack.push(item_buf1_win1)
        stack.push(item_buf1_win2)

        -- Before close, ref count is 2
        assert.are.equal(2, stack.get_tracker_entry(buf1).ref_count)

        stack.handle_win_close(2) -- Close one window for buffer 1

        -- After close, ref count should be 1
        local entry = stack.get_tracker_entry(buf1)
        assert.is_not_nil(entry)
        assert.are.equal(1, entry.ref_count)

        -- Should NOT delete temp map or restore original map yet
        assert.are.same({}, mock_call_args.nvim_buf_del_keymap)
        assert.are.same({}, mock_call_args.nvim_buf_set_keymap)
      end)

      it("should delete temp map and restore original map when count hits 0", function()
        local item_buf1_win1 = { win_id = 1, buf_id = buf1 }
        stack.create_tracker_entry(buf1, original_map_buf1) -- Override setup to start count at 1
        stack.push(item_buf1_win1) -- Only one item for buf1, ref count will go 1 -> 0

        -- Before close, ref count is 1
        assert.are.equal(1, stack.get_tracker_entry(buf1).ref_count)

        stack.handle_win_close(1) -- Close the only window for buffer 1

        -- After close, entry should be removed
        local entry = stack.get_tracker_entry(buf1)
        assert.is_nil(entry) -- Tracker entry should be removed

        -- Check API calls
        assert.are.equal(1, #mock_call_args.nvim_buf_del_keymap)
        assert.are.equal(1, #mock_call_args.nvim_buf_set_keymap)
        local deleted_call = mock_call_args.nvim_buf_del_keymap[1]
        assert.are.equal(buf1, deleted_call.bufnr)
        assert.are.equal("n", deleted_call.mode)
        assert.are.equal(close_key, deleted_call.lhs)
        assert.are.equal(original_map_buf1.map.rhs, mock_call_args.nvim_buf_set_keymap[1].rhs)
        assert.are.equal(original_map_buf1.map.noremap, mock_call_args.nvim_buf_set_keymap[1].opts.noremap)
        assert.are.equal(original_map_buf1.map.desc, mock_call_args.nvim_buf_set_keymap[1].opts.desc)
      end)

      it("should delete temp map and NOT restore when count hits 0 and no original map existed", function()
        local item_buf2_win3 = { win_id = 3, buf_id = buf2 }
        stack.create_tracker_entry(buf2, nil) -- Override setup to start count at 1
        stack.push(item_buf2_win3) -- Only one item for buf2, ref count will go 1 -> 0

        assert.are.equal(1, stack.get_tracker_entry(buf2).ref_count)
        stack.handle_win_close(3) -- Close the only window for buffer 2
        local entry = stack.get_tracker_entry(buf2)
        assert.is_nil(entry)
        assert.are.equal(1, #mock_call_args.nvim_buf_del_keymap)
        -- Check that set_keymap was NOT called (since no original map)
        assert.are.same({}, mock_call_args.nvim_buf_set_keymap)
      end)
    end)

    describe("close_all with keymaps", function()
      before_each(function()
        -- Mock config for close_key
        local config_mod = require("overlook.config")
        config_mod.options.ui.keys = { close = close_key }
        -- Setup initial state for keymap tests
        stack.create_tracker_entry(buf1, original_map_buf1) -- Buffer 1 has original map, ref 1
        stack.create_tracker_entry(buf2, nil) -- Buffer 2 has no original map, ref 1
        -- Simulate the temporary map being set on both buffers
        vim.keymap.set(
          "n",
          close_key,
          temp_map_rhs,
          { buffer = buf1, noremap = true, silent = true, nowait = true, desc = "Overlook: Close popup" }
        )
        vim.keymap.set(
          "n",
          close_key,
          temp_map_rhs,
          { buffer = buf2, noremap = true, silent = true, nowait = true, desc = "Overlook: Close popup" }
        )
        -- Reset API call args specifically for these tests
        mock_call_args.nvim_buf_del_keymap = {}
        mock_call_args.nvim_buf_set_keymap = {}
        -- Push items to stack (needed for close_all window closing part)
        stack.push { win_id = 1, buf_id = buf1 }
        stack.push { win_id = 2, buf_id = buf2 }
      end)

      it("should delete temp maps and restore original maps for all tracked buffers", function()
        stack.close_all()

        -- Check deletions (order might vary due to pairs iteration)
        assert.are.equal(2, #mock_call_args.nvim_buf_del_keymap)
        local deleted_bufs = {}
        for _, del_call in ipairs(mock_call_args.nvim_buf_del_keymap) do
          deleted_bufs[del_call.bufnr] = true
        end
        assert.is_true(deleted_bufs[buf1])
        assert.is_true(deleted_bufs[buf2])
        assert.are.equal(close_key, mock_call_args.nvim_buf_del_keymap[1].lhs)

        -- Check restorations
        assert.are.equal(1, #mock_call_args.nvim_buf_set_keymap) -- Only buf1 had original map
        local restore_call = mock_call_args.nvim_buf_set_keymap[1]
        assert.are.equal(buf1, restore_call.bufnr)
        assert.are.equal("n", restore_call.mode)
        assert.are.equal(close_key, restore_call.lhs)
        assert.are.equal(original_map_buf1.map.rhs, restore_call.rhs)

        -- Check tracker is cleared
        assert.is_nil(stack.get_tracker_entry(buf1)) -- Check specific entries are gone
        assert.is_nil(stack.get_tracker_entry(buf2))
        -- local any_left = false
        -- for _ in pairs(stack.buffer_keymap_tracker) do any_left = true break end -- Cannot access internal variable
        -- assert.is_false(any_left)
      end)
    end)
  end)
end)
