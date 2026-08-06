# Makefile for mail2md

PREFIX ?= /usr/local
INSTALL_PATH = $(PREFIX)/bin
BINARY_NAME = mail2md
BUILD_PATH = .build/release/$(BINARY_NAME)

.PHONY: build install uninstall clean

build:
	@echo "Building mail2md..."
	swift build -c release

install: build
	@echo "Installing mail2md to $(INSTALL_PATH)..."
	@install -d $(INSTALL_PATH)
	@install -m 755 $(BUILD_PATH) $(INSTALL_PATH)/$(BINARY_NAME)
	@echo "✓ mail2md installed to $(INSTALL_PATH)/$(BINARY_NAME)"

uninstall:
	@echo "Uninstalling mail2md from $(INSTALL_PATH)..."
	@rm -f $(INSTALL_PATH)/$(BINARY_NAME)
	@echo "✓ mail2md uninstalled"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf .build
	@echo "✓ Build artifacts removed"
