CXX ?= g++
PKG_CONFIG ?= pkg-config

# Check if gtkmm-4.0 is available
GTKMM_EXISTS := $(shell $(PKG_CONFIG) --exists gtkmm-4.0 && echo "yes" || echo "no")

ifeq ($(GTKMM_EXISTS),yes)
    CXXFLAGS += $(shell $(PKG_CONFIG) --cflags gtkmm-4.0)
    LDFLAGS += $(shell $(PKG_CONFIG) --libs gtkmm-4.0)
else
    $(warning gtkmm-4.0 not found. Build may fail. Run 'make install-deps' in root.)
endif

CXXFLAGS += -std=c++17 -Wall -Wextra

TARGET = hello-world
SRCS = main.cpp

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
