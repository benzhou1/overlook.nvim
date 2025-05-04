local Peek = require("overlook.peek")
local Stack = require("overlook.stack")

local M = {}

M.peek = {}

M.peek.definition = function()
  Peek.definition()
end

M.peek.cursor = function()
  Peek.cursor()
end

M.peek.mark = function()
  Peek.marks()
  vim.ui.input({ prompt = "Overlook Mark:" }, function(input)
    if input == nil or input == "" then
      return
    end

    if #input == 1 then
      Peek.marks(input)
    else
      vim.notify("Overlook Error: Invalid mark. Please enter a single character.", vim.log.levels.ERROR)
    end
  end)
end

M.close_all = function()
  Stack.close_all()
end

return M
