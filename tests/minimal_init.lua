vim.opt.runtimepath:prepend(".deps/plenary.nvim")
vim.opt.runtimepath:prepend(".")

vim.opt.compatible = false
vim.opt.termguicolors = true

-- Plenary runs spec files as parallel headless Nvim processes. Two failures
-- come from that: E325 (swapfile ATTENTION) hangs a run when peek tests
-- bufload a shared path, and on nightly the first edit races to mkdir
-- stdpath("state") .. "/swap" and the loser raises E303. Tests do not use
-- swap files.
vim.opt.swapfile = false

vim.cmd.runtime { "plugin/plenary.vim", bang = true }

require("overlook").setup()
