.PHONY: test deps

test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec/ { minimal_init = './tests/minimal_init.lua' }"

deps: plenary.nvim

plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .deps/plenary.nvim || true