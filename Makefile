.PHONY: all install-deps build-cpp-gtk4 clean

all: build-cpp-gtk4

install-deps:
	sudo apt-get update
	sudo apt-get install -y build-essential pkg-config libgtk-4-dev libgtkmm-4.0-dev

build-cpp-gtk4:
	$(MAKE) -C prototypes/cpp-gtk4

clean:
	$(MAKE) -C prototypes/cpp-gtk4 clean
