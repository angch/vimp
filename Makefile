ZIG_VERSION = 0.15.2
ZIG_ARCH_OS = x86_64-linux
ZIG_URL = https://ziglang.org/download/$(ZIG_VERSION)/zig-$(ZIG_ARCH_OS)-$(ZIG_VERSION).tar.xz
ZIG_DIR_NAME = zig-$(ZIG_ARCH_OS)-$(ZIG_VERSION)
ZIG_DIR = $(TOOLS_DIR)/$(ZIG_DIR_NAME)
TOOLS_DIR = $(CURDIR)/tools

ZIG_BIN = $(TOOLS_DIR)/zig
LOCAL_DIR = $(TOOLS_DIR)/local
GEGL_PATH_VAR = $(LOCAL_DIR)/lib/x86_64-linux-gnu/gegl-0.4
LD_LIB_PATH_VAR = $(LOCAL_DIR)/lib/x86_64-linux-gnu

.PHONY: all clean tools/zig build run test gegl

all: build

gegl:
	bash tools/build_gegl.sh

build:
	zig build

run:
	GEGL_PATH=$(GEGL_PATH_VAR) LD_LIBRARY_PATH=$(LD_LIB_PATH_VAR) ./run_local.sh

test:
	GEGL_PATH=$(GEGL_PATH_VAR) LD_LIBRARY_PATH=$(LD_LIB_PATH_VAR) zig build test

clean:
	rm -rf $(TOOLS_DIR)
	rm -rf zig-out
	rm -rf .zig-cache

