.PHONY: test clean

test:
	lua test_init.lua

clean:
	rm -f luac.out
