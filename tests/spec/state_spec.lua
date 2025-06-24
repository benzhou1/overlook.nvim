local stack = require("overlook.stack")
local state = require("overlook.state")

-- Store original API functions and mock call arguments
local orig_api = {}
local mock_call_args = {}
local original_stack_top = nil

-- Helper to mock vim.api functions
local function mock_api(name, mock_fn)
  if vim.api[name] then
    orig_api[name] = vim.api[name]
  end
  vim.api[name] = mock_fn
end

-- Helper to reset mocks before each test
local function setup_mocks()
  -- Restore original functions before applying mocks
  for k, v in pairs(orig_api) do
    vim.api[k] = v
  end
  if original_stack_top then
    stack.top = original_stack_top -- Restore original stack.top
  end
  orig_api = {}
  original_stack_top = nil

  mock_call_args = { -- Reset captured args
    nvim_win_set_config = {},
    nvim_win_get_config = {},
    nvim_buf_get_name = {},
    nvim_win_get_buf = {},
    nvim_get_current_win = {},
    notify = {}, -- Capture vim.notify calls if needed
  }

  -- Default Mocks needed for update_title
  mock_api("nvim_get_current_win", function()
    table.insert(mock_call_args.nvim_get_current_win, {})
    return 1 -- Default: assume tests run in window 1
  end)
  mock_api("nvim_win_get_buf", function(winid)
    table.insert(mock_call_args.nvim_win_get_buf, { winid = winid })
    if winid == 1 then
      return 10
    end -- Default: win 1 has buf 10
    if winid == 2 then
      return 20
    end
    return 99
  end)
  mock_api("nvim_buf_is_valid", function(buf_id)
    return buf_id == 10 or buf_id == 20 or buf_id == 99 -- Assume test buffers are valid
  end)
  mock_api("nvim_buf_get_name", function(buf_id)
    table.insert(mock_call_args.nvim_buf_get_name, { buf_id = buf_id })
    if buf_id == 10 then
      return "/path/to/buffer10.lua"
    end -- Default name
    if buf_id == 20 then
      return "/path/to/buffer20.txt"
    end
    return "" -- Default: unnamed buffer
  end)
  mock_api("nvim_win_get_config", function(winid)
    table.insert(mock_call_args.nvim_win_get_config, { winid = winid })
    -- Return a basic default config
    return { border = "single", title = "Default Title" }
  end)
  mock_api("nvim_win_set_config", function(winid, config)
    table.insert(mock_call_args.nvim_win_set_config, { winid = winid, config = config })
    -- Simulate success
  end)

  -- Mock stack.top by default returning nil
  if stack.top then
    original_stack_top = stack.top
  end
  stack.top = function()
    return nil
  end
end

describe("overlook.state", function()
  before_each(setup_mocks)

  after_each(function()
    -- Restore original functions after each test
    for k, v in pairs(orig_api) do
      vim.api[k] = v
    end
    if original_stack_top then
      stack.top = original_stack_top
    end
    orig_api = {}
    original_stack_top = nil
  end)

  describe("update_title", function()
    it("should set window title when current window is the top popup", function()
      -- Arrange
      mock_api("nvim_get_current_win", function()
        return 1
      end)
      stack.top = function()
        return { winid = 1, buf_id = 10 }
      end
      mock_api("nvim_buf_get_name", function(buf_id)
        return "/some/path/my_file.py"
      end)

      -- Mock fnamemodify for this test
      local orig_fnamemodify = vim.fn.fnamemodify
      vim.fn.fnamemodify = function(fname, mods)
        if mods == ":~:." then
          return "my_file.py"
        end -- Simulate shortening
        return fname -- Default fallback
      end

      -- Act
      state.update_title() -- Use state module function

      -- Assert
      assert.are.equal(1, #mock_call_args.nvim_win_set_config)
      local args = mock_call_args.nvim_win_set_config[1]
      assert.are.equal(1, args.winid)
      assert.are.equal("my_file.py", args.config.title)

      -- Restore fnamemodify
      vim.fn.fnamemodify = orig_fnamemodify
    end)

    it("should set fallback title for unnamed buffer", function()
      -- Arrange
      mock_api("nvim_get_current_win", function()
        return 1
      end)
      stack.top = function()
        return { winid = 1, buf_id = 10 }
      end
      mock_api("nvim_buf_get_name", function(buf_id)
        return ""
      end)

      -- Act
      state.update_title() -- Use state module function

      -- Assert
      assert.are.equal(1, #mock_call_args.nvim_win_set_config)
      local args = mock_call_args.nvim_win_set_config[1]
      assert.are.equal(1, args.winid)
      assert.are.equal("(No Name)", args.config.title)
    end)

    it("should NOT set title when current window is NOT the top popup", function()
      -- Arrange
      mock_api("nvim_get_current_win", function()
        return 2
      end)
      stack.top = function()
        return { winid = 1, buf_id = 10 }
      end

      -- Act
      state.update_title() -- Use state module function

      -- Assert
      assert.are.equal(0, #mock_call_args.nvim_win_set_config)
    end)

    it("should NOT set title when stack is empty", function()
      -- Arrange
      mock_api("nvim_get_current_win", function()
        return 1
      end)
      stack.top = function()
        return nil
      end

      -- Act
      state.update_title() -- Use state module function

      -- Assert
      assert.are.equal(0, #mock_call_args.nvim_win_set_config)
    end)

    it("should handle error during nvim_win_get_config", function()
      -- Arrange
      mock_api("nvim_get_current_win", function()
        return 1
      end)
      stack.top = function()
        return { winid = 1, buf_id = 10 }
      end
      mock_api("nvim_win_get_config", function(winid)
        error("Config error!")
      end)

      -- Mock notify to capture calls
      orig_api["vim.notify"] = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(mock_call_args.notify, { msg = msg, level = level, opts = opts })
      end

      -- Act
      state.update_title() -- Use state module function

      -- Assert
      assert.are.equal(0, #mock_call_args.nvim_win_set_config)
      assert.are.equal(1, #mock_call_args.notify)
      assert.matches("Failed to get window config", mock_call_args.notify[1].msg)

      -- Restore notify
      vim.notify = orig_api["vim.notify"]
      orig_api["vim.notify"] = nil
    end)
  end)

  -- TODO: Add tests for update_keymap_state if needed (might be covered by stack_spec)
  -- TODO: Add tests for setup function logic if needed
end)
