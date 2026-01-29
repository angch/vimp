ZIG_VERSION = 0.15.2
ZIG_ARCH_OS = x86_64-linux
ZIG_URL = https://ziglang.org/download/$(ZIG_VERSION)/zig-$(ZIG_ARCH_OS)-$(ZIG_VERSION).tar.xz
ZIG_DIR_NAME = zig-$(ZIG_ARCH_OS)-$(ZIG_VERSION)
ZIG_DIR = $(TOOLS_DIR)/$(ZIG_DIR_NAME)
TOOLS_DIR = $(CURDIR)/tools

ZIG_BIN = $(TOOLS_DIR)/zig

.PHONY: all clean tools/zig

all: $(ZIG_BIN)

$(ZIG_BIN):
	mkdir -p $(TOOLS_DIR)
	curl -o $(TOOLS_DIR)/zig.tar.xz $(ZIG_URL)
	tar -xf $(TOOLS_DIR)/zig.tar.xz -C $(TOOLS_DIR)
	ln -sf $(ZIG_DIR)/zig $(ZIG_BIN)
	rm $(TOOLS_DIR)/zig.tar.xz
	@echo "Zig $(ZIG_VERSION) installed to $(ZIG_BIN)"

clean:
	rm -rf $(TOOLS_DIR)
