.PHONY: check 

check:
	luacheck --no-color --no-redefined --read-globals vim --std luajit lua/norns/*.lua plugin/*.lua tests/*.lua

