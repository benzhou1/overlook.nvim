vim.opt.runtimepath:prepend(".deps/plenary.nvim")
vim.opt.runtimepath:prepend(".")

vim.opt.compatible = false
vim.opt.termguicolors = true

-- E325 (swapfile ATTENTION) blocks `nvim --headless` until a key is pressed.
-- Plenary runs spec files in parallel child processes, and peek tests bufload
-- real paths; a shared swapfile makes that race hang the run.
vim.opt.swapfile = false

vim.cmd.runtime { "plugin/plenary.vim", bang = true }

require("overlook").setup()
