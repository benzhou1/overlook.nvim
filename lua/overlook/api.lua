local Peek = require("overlook.peek")
local Stack = require("overlook.stack")
local Ui = require("overlook.ui")

local M = {}

M.peek_definition = function()
  Peek.definition()
end

M.peek_cursor = function()
  Peek.cursor()
end

M.peek_mark = function()
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

M.restore_all_popups = function()
  local stack = require("overlook.stack").get_current_stack()
  stack:restore_all()
end

M.restore_popup = function()
  local stack = require("overlook.stack").get_current_stack()
  stack:restore()
end

M.close_all = function()
  Stack.clear()
end

--- Promotes the top Overlook popup to a regular window (split, vsplit, or tab).
--- @param open_command 'vsplit'|'split'|'tabnew' Vim command to open the window.
local promote_top_to_window = function(open_command)
  local cmd = string.format("%s | buffer", open_command)
  Ui.promote_popup_to_window(cmd)
end

--- Opens the top Overlook popup in a new split window.
M.open_in_split = function()
  promote_top_to_window("split")
end

--- Opens the top Overlook popup in a new vertical split window.
M.open_in_vsplit = function()
  promote_top_to_window("vsplit")
end

--- Opens the top Overlook popup in a new tab.
M.open_in_tab = function()
  promote_top_to_window("tabnew")
end

--- Promotes the top Overlook popup to the root window.
M.open_in_original_window = function()
  Ui.promote_popup_to_window("buffer")
end

return M
