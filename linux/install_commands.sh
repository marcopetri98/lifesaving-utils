#!/bin/bash
set -e

# Install for the calling user, also when the script is run through sudo
if [[ $EUID -eq 0 && -n "$SUDO_USER" ]]; then
  TARGET_USER="$SUDO_USER"
else
  TARGET_USER="$(id -un)"
fi

USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
USER_GROUP="$(id -gn "$TARGET_USER")"
BASHRC="$USER_HOME/.bashrc"

# Create the update_system command for the user simplicity
install -d -o "$TARGET_USER" -g "$USER_GROUP" "$USER_HOME/.local" "$USER_HOME/.local/bin"
install -m 755 -o "$TARGET_USER" -g "$USER_GROUP" ./linux/commands/* "$USER_HOME/.local/bin/"

# Make sure that .local/bin is in the PATH
if grep -qF '.local/bin' "$BASHRC"; then
  echo "Skipping: .local/bin already in $BASHRC"
else
  echo "Adding .local/bin to PATH in $BASHRC"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASHRC"
  sudo chown "$TARGET_USER:$USER_GROUP" "$BASHRC"
fi
