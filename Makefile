PREFIX ?= /usr/local
SHARE_DIR = $(PREFIX)/share/claudux
BIN_DIR = $(PREFIX)/bin

.PHONY: install uninstall

install:
	@echo "Installing claudux to $(SHARE_DIR)..."
	mkdir -p $(SHARE_DIR)/scripts $(SHARE_DIR)/config $(BIN_DIR)
	cp claudux.tmux $(SHARE_DIR)/
	cp scripts/* $(SHARE_DIR)/scripts/
	cp config/* $(SHARE_DIR)/config/
	cp bin/claudux-setup $(BIN_DIR)/
	chmod +x $(SHARE_DIR)/claudux.tmux $(SHARE_DIR)/scripts/*.sh $(BIN_DIR)/claudux-setup
	@echo ""
	@echo "Installed. Run: claudux-setup install"

uninstall:
	@echo "Removing claudux..."
	rm -rf $(SHARE_DIR)
	rm -f $(BIN_DIR)/claudux-setup
	@echo "Done. Run: claudux-setup uninstall (if not already done)"
