-- NOTE: run this script with `nvim -u repro.lua {filename}`

-- setup XDG directories
local root = vim.fn.fnamemodify("./.repro", ":p")
for _, name in ipairs { "config", "data", "state", "cache" } do
  vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. name
end

-- setup lazy.nvim
local lazypath = root .. "/plugins/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.print("Installing lazy.nvim to " .. lazypath)
  vim.fn.system { "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", lazypath }
end
vim.opt.runtimepath:prepend(lazypath)

-- neovim options
vim.o.swapfile = false

-- plugins
local plugins = {
  {
    "williamhsieh/overlook.nvim",
    opts = {},
    keys = {
      {
        "<space>po",
        function()
          require("overlook.api").peek_cursor()
        end,
        desc = "Overlook peek cursor",
      },
    },
  },
}

require("lazy").setup(plugins, { root = root .. "/plugins" })
