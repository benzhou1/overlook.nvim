-- Minimal init for documentation generation
-- Similar to tests/minimal_init.lua but for mini.doc

-- Add dependencies to runtime path
vim.opt.rtp:prepend(".deps/mini.nvim")

-- Setup mini.doc
require("mini.doc").setup()

-- Add current directory to runtime path so overlook modules can be required
vim.opt.rtp:prepend(".")