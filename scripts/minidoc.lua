-- Script for generating overlook.nvim documentation using mini.doc

local doc = require("mini.doc")

doc.generate({ "lua/overlook/api.lua" }, "doc/overlook-api.txt")

doc.generate({ "lua/overlook/config.lua" }, "doc/overlook-config.txt")

-- -- Generate combined documentation
-- print("Generating combined documentation...")
-- doc.generate(
--   { "lua/overlook/api.lua", "lua/overlook/config.lua" },
--   "doc/overlook.txt"
-- )

print("All documentation generated successfully!")
