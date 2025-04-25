local Path = require("plenary.path")

-- Get the absolute path to the specific spec file
local spec_file_path = Path:new(vim.fn.getcwd(), "tests", "spec", "stack_spec.lua"):absolute()

require("plenary.busted").run(spec_file_path)
