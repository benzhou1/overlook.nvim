local stack = require('overlook.stack')

describe('overlook.stack', function()

  before_each(function()
    -- Manually reset stack state before each test
    stack.stack = {}
    stack.original_win_id = nil
  end)

  it('should initialize with an empty stack', function()
    -- stack.stack = {} -- No longer needed here
    -- stack.original_win_id = nil
    assert.are.equal(0, stack.size())
    assert.is_nil(stack.top())
  end)

  it('should push items onto the stack', function()
    -- stack.stack = {} -- No longer needed here
    -- stack.original_win_id = nil
    local item1 = { win_id = 1, buf_id = 10 }
    local item2 = { win_id = 2, buf_id = 20 }

    stack.push(item1)
    assert.are.equal(1, stack.size())
    assert.are.same(item1, stack.top())

    stack.push(item2)
    assert.are.equal(2, stack.size())
    assert.are.same(item2, stack.top())
  end)

  -- Pop tests removed as M.pop is not used

  -- Reset test removed as M.reset is not used

  it('should find items by win_id', function()
    -- stack.stack = {} -- No longer needed here
    -- stack.original_win_id = nil
    local item1 = { win_id = 1, buf_id = 10 }
    local item2 = { win_id = 2, buf_id = 20 }
    local item3 = { win_id = 3, buf_id = 30 }
    stack.push(item1)
    stack.push(item2)
    stack.push(item3)

    assert.are.same(item2, stack.find_by_win(2))
    assert.is_nil(stack.find_by_win(99))
  end)

  -- Remove tests removed as M.remove_by_win_id is not used

  -- Note: Testing handle_win_close requires mocking vim.api functions
  -- This will be added in a future step.
end)
