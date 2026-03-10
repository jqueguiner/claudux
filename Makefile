PREFIX ?= /usr/local
SHARE_DIR = $(PREFIX)/share/claudux
BIN_DIR = $(PREFIX)/bin
MAN_DIR = $(PREFIX)/share/man/man1

.PHONY: install uninstall

install:
	@echo "Installing claudux to $(SHARE_DIR)..."
	mkdir -p $(SHARE_DIR)/scripts $(SHARE_DIR)/config $(BIN_DIR) $(MAN_DIR)
	cp claudux.tmux $(SHARE_DIR)/
	cp scripts/* $(SHARE_DIR)/scripts/
	cp config/* $(SHARE_DIR)/config/
	cp bin/claudux-setup $(BIN_DIR)/
	cp man/claudux.1 $(MAN_DIR)/
	chmod +x $(SHARE_DIR)/claudux.tmux $(SHARE_DIR)/scripts/*.sh $(BIN_DIR)/claudux-setup
	@echo ""
	@echo "Installed. Run: claudux-setup install"

uninstall:
	@echo "Removing claudux..."
	rm -rf $(SHARE_DIR)
	rm -f $(BIN_DIR)/claudux-setup
	rm -f $(MAN_DIR)/claudux.1
	@echo "Done. Run: claudux-setup uninstall (if not already done)"
