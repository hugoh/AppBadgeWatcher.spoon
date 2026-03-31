.PHONY: test test-plain clean install install-luarocks install-busted

test:
	eval $$(luarocks path) && busted test_spec.lua --verbose

test-plain:
	lua test_init.lua

install: install-luarocks install-busted

install-luarocks:
	@if [ -z "$$(which luarocks 2>/dev/null)" ]; then \
		if [ "$$(uname)" = "Darwin" ]; then \
			brew install luarocks; \
		elif [ "$$(uname)" = "Linux" ]; then \
			sudo apt-get update && sudo apt-get install -y luarocks; \
		fi \
	fi

install-busted:
	luarocks install busted

clean:
	rm -f luac.out
