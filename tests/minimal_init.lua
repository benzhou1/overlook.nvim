vim.opt.runtimepath:prepend(".deps/plenary.nvim")
vim.opt.runtimepath:prepend(".")

vim.opt.compatible = false
vim.opt.termguicolors = true

vim.cmd.runtime { "plugin/plenary.vim", bang = true }

require("overlook").setup()
