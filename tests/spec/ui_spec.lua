local ui = require('overlook.ui')
local stack = require('overlook.stack')
local config = require('overlook.config')
local helpers = require('tests.helpers') -- We might add mocking helpers here later

-- Mocking Neovim API
local api_spy = require('luassert.spy').new(vim.api)
local fn_spy = require('luassert.spy').new(vim.fn)

-- Helper to reset mocks and stack before each test
local function setup_mocks()
  api_spy:reset()
  fn_spy:reset()
  stack.reset()

  -- Mock essential API calls needed for basic UI function execution
  -- Mock nvim_get_current_win to return a dummy window ID
  api_spy.nvim_get_current_win:returns(1000)

  -- Mock nvim_win_is_valid to always return true for relevant IDs
  api_spy.nvim_win_is_valid:calls(function(win_id)
    return win_id == 1000 or win_id == 1001 -- Add more IDs as needed
  end)

  -- Mock nvim_buf_is_valid to always return true
  api_spy.nvim_buf_is_valid:returns(true)

  -- Mock config loading to return default-like values
  -- Need to bypass the internal caching in ui.lua for config
  local mock_ui_config = {
    border = "single",
    z_index_base = 50,
    col_offset = 1,
    row_offset = 1,
    size_ratio = 0.8,
    min_width = 10,
    min_height = 5,
    width_decrement = 2,
    height_decrement = 1,
    stack_row_offset = 1,
    stack_col_offset = 1,
  }
  local config_mod_spy = require('luassert.spy').new(config)
  config_mod_spy.options = { ui = mock_ui_config }
  package.loaded['overlook.config'] = config_mod_spy -- Replace loaded module

  -- Mock stack size
  local stack_spy = require('luassert.spy').new(stack)
  stack_spy.size:returns(0)
  package.loaded['overlook.stack'] = stack_spy -- Replace loaded module
end

describe('overlook.ui', function()
  before_each(setup_mocks)
  -- Restore original vim.api and vim.fn after tests in this block
  -- NOTE: This simple replacement might not be robust enough for all cases.
  -- More sophisticated mocking might be needed.
  local orig_api = vim.api
  local orig_fn = vim.fn
  after_each(function()
    vim.api = orig_api
    vim.fn = orig_fn
    -- Reset replaced modules
    package.loaded['overlook.config'] = config
    package.loaded['overlook.stack'] = stack
    collectgarbage()
  end)

  -- Assign mocked versions
  vim.api = api_spy
  vim.fn = fn_spy

  it('should attempt to create a popup with valid buffer', function()
    -- Arrange: Mock necessary API calls for create_popup
    api_spy.nvim_win_get_cursor:returns({ 5, 10 }) -- {row, col}
    fn_spy.screenpos:returns({ row = 6, col = 11 }) -- {row, col} 1-based
    api_spy.nvim_win_get_position:returns({ 1, 1 }) -- {row, col} 0-based
    api_spy.nvim_win_get_height:returns(20)
    api_spy.nvim_win_get_width:returns(80)
    api_spy.nvim_get_option_value:fake(function(name, _)
      if name == 'lines' then return 40 end
      if name == 'columns' then return 100 end
      if name == 'cmdheight' then return 1 end
      if name == 'laststatus' then return 2 end
      if name == 'winbar' then return nil end -- Assume no winbar
      return nil
    end)
    api_spy.nvim_open_win:returns(1001) -- Return a new dummy window ID
    api_spy.nvim_win_get_config:returns({
      relative = "win",
      width = 60, -- Example final width
      height = 15, -- Example final height
      row = 7, -- Example final row
      col = 12, -- Example final col
      border = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
      title = "default title",
      title_pos = "center",
      zindex = 50,
    })
    api_spy.nvim_win_set_cursor:returns(true)
    api_spy.nvim_win_call:returns(true)
    api_spy.nvim_create_autocmd:returns(true)

    -- Act
    local result = ui.create_popup({ target_bufnr = 1, lnum = 5, col = 10 })

    -- Assert
    assert.is_not_nil(result)
    assert.are.equal(1001, result.win_id)
    assert.are.equal(1, result.buf_id)
    -- Check if key functions were called
    assert.spy(api_spy.nvim_open_win).was_called()
    assert.spy(api_spy.nvim_win_set_cursor).was_called()
    assert.spy(api_spy.nvim_create_autocmd).was_called()
    -- Verify stack push was attempted (using the spy we setup)
    local stack_mod = package.loaded['overlook.stack']
    assert.spy(stack_mod.push).was_called()
  end)

  -- TODO: Add more tests:
  -- - Test placement logic (above/below)
  -- - Test subsequent popup positioning (stacking)
  -- - Test behavior when buffer is invalid
  -- - Test border types
  -- - Test edge cases (small window sizes, hitting min/max dimensions)
  -- - Test error handling for nvim_open_win failure
end) 