.PHONY: test deps

test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua -l tests/run_tests.lua

deps: plenary.nvim

plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .deps/plenary.nvim || true