.PHONY: all clean build run test libs setup

all: build

setup:
	bash setup.sh

libs:
	bash scripts/setup_libs.sh

build:
	zig build

run:
	./run_local.sh

test:
	zig build test

clean:
	rm -rf zig-out
	rm -rf .zig-cache
