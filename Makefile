.PHONY: test

test:
	@echo "Running Lua unit tests with busted"
	busted test_spec.lua --verbose
