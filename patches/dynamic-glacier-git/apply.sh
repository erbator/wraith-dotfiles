#!/bin/sh
# Reapplies the DynamicGlacier customizations (FiraCode Nerd Font, Super-tap
# toggle IPC, arrow-key navigation in Apps and Wallpaper, the Wallpaper
# switcher panel, and real DBus notification handling) after a fresh
# `paru -S dynamic-glacier-git` install or reinstall.
#
# dynamic-glacier-git is pinned in /etc/pacman.conf (IgnorePkg) and
# ~/.config/paru/paru.conf (IgnoreDevel) specifically so a routine update
# never silently overwrites these patches — this script is only needed
# after a deliberate reinstall/unpin, or on a new machine.
#
# Usage: sudo ./apply.sh
set -eu

TARGET_ROOT="/usr/share/dynamic-glacier"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (sudo ./apply.sh) — patches files under $TARGET_ROOT" >&2
    exit 1
fi

if [ ! -d "$TARGET_ROOT/quickshell" ]; then
    echo "dynamic-glacier-git doesn't look installed (no $TARGET_ROOT/quickshell)." >&2
    echo "Install it first: paru -S dynamic-glacier-git" >&2
    exit 1
fi

echo "Applying dynamic-glacier.patch to $TARGET_ROOT ..."
patch -d "$TARGET_ROOT" -p1 --forward < "$PATCH_DIR/dynamic-glacier.patch"

echo "Restarting dynamic-glacier for the current user..."
pkill -f "quickshell --path $TARGET_ROOT/quickshell" 2>/dev/null || true
sudo -u "${SUDO_USER:-$USER}" setsid nohup dynamic-glacier >/dev/null 2>&1 < /dev/null &

echo "Done. Verify with: quickshell ipc -p $TARGET_ROOT/quickshell call dynamicGlacier apps"
