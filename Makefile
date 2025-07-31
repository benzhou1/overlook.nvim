.PHONY: test vimdoc deps

test: plenary.nvim
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec/ { minimal_init = './tests/minimal_init.lua' }"

vimdoc: mini.nvim
	rm -rf doc
	nvim --headless --noplugin -u scripts/docs_init.lua -c "lua require('mini.doc').generate()" -c "qa"

plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .deps/plenary.nvim || true

mini.nvim:
	git clone --depth 1 https://github.com/echasnovski/mini.nvim .deps/mini.nvim || true
