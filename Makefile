ZIG_VERSION = 0.15.2
ZIG_ARCH_OS = x86_64-linux
ZIG_URL = https://ziglang.org/download/$(ZIG_VERSION)/zig-$(ZIG_ARCH_OS)-$(ZIG_VERSION).tar.xz
ZIG_DIR_NAME = zig-$(ZIG_ARCH_OS)-$(ZIG_VERSION)
ZIG_DIR = $(TOOLS_DIR)/$(ZIG_DIR_NAME)
TOOLS_DIR = $(CURDIR)/tools

ZIG_BIN = $(TOOLS_DIR)/zig

.PHONY: all clean tools/zig build run test

all: build

build:
	zig build

run:
	./run_local.sh

test:
	zig build test

clean:
	rm -rf $(TOOLS_DIR)
	rm -rf zig-out
	rm -rf .zig-cache

