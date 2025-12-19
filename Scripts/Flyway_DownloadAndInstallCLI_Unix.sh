#!/bin/bash

# ===========================
# Script Name: Flyway_DownloadAndInstallCLI.sh
# Version: 1.2.0
# Author: Chris Hawkins (Redgate Software Ltd)
# Last Updated: 2025-12-19
# Description: Install Flyway CLI on Linux with cleanup of old versions and PATH handling
#              Supports both manual execution and CI/CD pipelines (GitHub Actions, etc.)
# ===========================

set -e

SCRIPT_VERSION="1.2.0"
echo "Running Flyway Installer Script - Version $SCRIPT_VERSION"

# ---------------------------
# Detect execution context
# ---------------------------
# Check if running in CI/CD environment
if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ] || [ -n "$GITLAB_CI" ] || [ -n "$CIRCLECI" ]; then
    IS_CI=true
    echo "CI/CD environment detected"
else
    IS_CI=false
fi

# Check if we have sudo/root access
if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
    HAS_SUDO=true
else
    HAS_SUDO=false
    echo "No sudo access detected - using user-space installation"
fi

# ---------------------------
# Configurable Variables
# ---------------------------
FLYWAY_VERSION="${FLYWAY_VERSION:-Latest}"          # Default to Latest if not set

# Smart default: use user home if no sudo or in CI, otherwise /opt/flyway
if [ -z "$FLYWAY_INSTALL_DIR" ]; then
    if [ "$HAS_SUDO" = true ] && [ "$IS_CI" = false ]; then
        FLYWAY_INSTALL_DIR="/opt/flyway"
    else
        FLYWAY_INSTALL_DIR="$HOME/.flyway"
    fi
fi

# For CI/CD or non-sudo environments, update user profile instead of system-wide
if [ -z "$GLOBAL_PATH_UPDATE" ]; then
    if [ "$HAS_SUDO" = true ] && [ "$IS_CI" = false ]; then
        GLOBAL_PATH_UPDATE=true
    else
        GLOBAL_PATH_UPDATE=false
    fi
fi

echo "Requested Flyway version: $FLYWAY_VERSION"
echo "Flyway install directory: $FLYWAY_INSTALL_DIR"
echo "Global PATH update: $GLOBAL_PATH_UPDATE"

# ---------------------------
# Helper Functions
# ---------------------------
get_installed_version() {
    if command -v flyway >/dev/null 2>&1; then
        flyway --version | grep -Eo 'Flyway (Community|Pro|Enterprise|Teams) Edition [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $4}'
    else
        echo "none"
    fi
}

get_latest_version_from_website() {
    content=$(curl -s https://documentation.red-gate.com/flyway/reference/usage/command-line)
    echo "$content" | grep -oP 'flyway-commandline-\K\d+\.\d+\.\d+(?=-linux-x64.tar.gz)' | head -n 1
}

cleanup_old_versions() {
    echo "Cleaning up old Flyway versions..."
    for dir in "$FLYWAY_INSTALL_DIR"/flyway-*; do
        # Skip current version and non-existent
        [ -d "$dir" ] || continue
        [[ "$dir" == "$INSTALL_DIR" ]] && continue

        echo "Removing old Flyway version at $dir"
        if [ "$HAS_SUDO" = true ] && [[ "$dir" == /opt/* ]]; then
            sudo rm -rf "$dir"
        else
            rm -rf "$dir"
        fi
    done
}

# ---------------------------
# Determine Flyway version
# ---------------------------
if [[ "$FLYWAY_VERSION" =~ [Ll]atest ]]; then
    LATEST_VERSION=$(get_latest_version_from_website)
    if [ -z "$LATEST_VERSION" ]; then
        echo "Could not detect latest Flyway version. Exiting."
        exit 1
    fi
    echo "Latest Flyway version detected: $LATEST_VERSION"
    FLYWAY_VERSION="$LATEST_VERSION"
fi

# ---------------------------
# Installation directory
# ---------------------------
INSTALL_DIR="$FLYWAY_INSTALL_DIR/flyway-$FLYWAY_VERSION"

# ---------------------------
# Check if already installed
# ---------------------------
if [ -d "$INSTALL_DIR" ]; then
    echo "Flyway $FLYWAY_VERSION already installed at $INSTALL_DIR. Skipping download."
else
    echo "Downloading and installing Flyway $FLYWAY_VERSION..."
    wget -qO- "https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/$FLYWAY_VERSION/flyway-commandline-$FLYWAY_VERSION-linux-x64.tar.gz" \
        | tar -xvz

    # Ensure parent directory exists (with or without sudo)
    if [ "$HAS_SUDO" = true ] && [[ "$FLYWAY_INSTALL_DIR" == /opt/* ]]; then
        sudo mkdir -p "$FLYWAY_INSTALL_DIR"
        sudo mv "flyway-$FLYWAY_VERSION" "$INSTALL_DIR"
    else
        mkdir -p "$FLYWAY_INSTALL_DIR"
        mv "flyway-$FLYWAY_VERSION" "$INSTALL_DIR"
    fi
fi

# ---------------------------
# Update PATH for current session
# ---------------------------
export PATH="$INSTALL_DIR:$PATH"
echo "PATH updated for current session: $PATH"

# ---------------------------
# Persist PATH update
# ---------------------------
if [ "$GLOBAL_PATH_UPDATE" = true ]; then
    # System-wide update (requires sudo)
    if sudo sh -c "echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> /etc/profile"; then
        echo "Global PATH updated in /etc/profile"
    else
        echo "Warning: Could not update global PATH, continuing..."
    fi
else
    # User-space update (no sudo required)
    USER_PROFILE=""
    
    # Detect which profile file to use
    if [ -f "$HOME/.bashrc" ]; then
        USER_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        USER_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.profile" ]; then
        USER_PROFILE="$HOME/.profile"
    else
        USER_PROFILE="$HOME/.profile"
        touch "$USER_PROFILE"
    fi
    
    # Check if PATH entry already exists
    if ! grep -q "$INSTALL_DIR" "$USER_PROFILE" 2>/dev/null; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$USER_PROFILE"
        echo "User PATH updated in $USER_PROFILE"
    else
        echo "PATH entry already exists in $USER_PROFILE"
    fi
    
    # For CI/CD: also add to GITHUB_PATH if it exists
    if [ -n "$GITHUB_PATH" ]; then
        echo "$INSTALL_DIR" >> "$GITHUB_PATH"
        echo "Added to GITHUB_PATH for GitHub Actions"
    fi
fi

# ---------------------------
# Cleanup old Flyway versions
# ---------------------------
cleanup_old_versions

# ---------------------------
# Verify installation
# ---------------------------
if flyway --version >/dev/null 2>&1; then
    echo "Flyway $FLYWAY_VERSION installed successfully and running."
else
    echo "Flyway installation failed!"
    exit 1
fi
