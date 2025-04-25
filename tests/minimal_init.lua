local vim = vim

-- Set runtimepath to include plenary.nvim and the current directory
-- Assumes plenary.nvim is cloned next to overlook.nvim repo
local plenary_path = vim.fn.expand('.deps/plenary.nvim')
local current_dir = vim.fn.expand('.')
vim.opt.runtimepath:prepend(plenary_path)
vim.opt.runtimepath:prepend(current_dir)

-- Minimal configuration
vim.opt.compatible = false
vim.opt.termguicolors = true

-- Load plenary first
require('plenary')

-- Load the plugin under test
local overlook = require('overlook')
overlook.setup({})

print('Minimal init loaded for tests') 