#!/usr/bin/env bash
set -euo pipefail

REPO="jqueguiner/claudux"
INSTALL_DIR="${HOME}/.tmux/plugins/claudux"

info()  { printf '\033[1;34m=>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m=>\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m=>\033[0m %s\n' "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

install_deps_brew() {
    if ! command_exists brew; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    for dep in bash jq curl tmux; do
        if ! command_exists "$dep" || { [[ "$dep" == "bash" ]] && [[ "$(bash --version | head -1)" == *"version 3."* ]]; }; then
            info "Installing $dep..."
            brew install "$dep"
        fi
    done
}

install_deps_apt() {
    local missing=()
    for dep in bash jq curl tmux; do
        command_exists "$dep" || missing+=("$dep")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing ${missing[*]}..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${missing[@]}"
    fi
}

install_deps() {
    case "$(uname -s)" in
        Darwin) install_deps_brew ;;
        Linux)
            if command_exists apt-get; then
                install_deps_apt
            else
                err "Unsupported package manager. Install manually: bash 4.0+, jq, curl, tmux"
                exit 1
            fi
            ;;
        *)
            err "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
}

install_claudux() {
    if [[ -d "$INSTALL_DIR" ]]; then
        info "Updating existing installation..."
        git -C "$INSTALL_DIR" pull --ff-only
    else
        info "Cloning claudux..."
        git clone "https://github.com/${REPO}.git" "$INSTALL_DIR"
    fi
    chmod +x "$INSTALL_DIR/claudux.tmux" "$INSTALL_DIR/scripts/"*.sh "$INSTALL_DIR/bin/claudux-setup"
}

configure_tmux() {
    local tmux_conf="${HOME}/.tmux.conf"
    touch "$tmux_conf"

    if grep -q "claudux" "$tmux_conf" 2>/dev/null; then
        info "claudux already in ${tmux_conf}, skipping"
        return
    fi

    cat >> "$tmux_conf" << EOF

# claudux — Claude API usage monitor
run-shell ${INSTALL_DIR}/claudux.tmux
EOF

    ok "Added claudux to ${tmux_conf}"
}

reload_tmux() {
    if command_exists tmux && tmux list-sessions >/dev/null 2>&1; then
        tmux source-file "${HOME}/.tmux.conf" 2>/dev/null && ok "tmux config reloaded" || true
    else
        info "Start tmux to see claudux in action"
    fi
}

symlink_bin() {
    local bin_dir="${HOME}/.local/bin"
    mkdir -p "$bin_dir"
    ln -sf "$INSTALL_DIR/bin/claudux-setup" "$bin_dir/claudux-setup"
    if [[ ":$PATH:" != *":${bin_dir}:"* ]]; then
        info "Add to your shell profile: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

main() {
    printf '\n\033[1m  claudux installer\033[0m\n\n'

    info "Checking dependencies..."
    install_deps

    info "Installing claudux..."
    install_claudux

    info "Configuring tmux..."
    configure_tmux

    symlink_bin
    reload_tmux

    printf '\n'
    ok "claudux installed successfully!"
    printf '\n'
    printf '  Run \033[1mclaudux-setup status\033[0m to verify.\n'
    printf '  Run \033[1mclaudux-setup profile add <name>\033[0m to set up a profile.\n\n'
}

main
