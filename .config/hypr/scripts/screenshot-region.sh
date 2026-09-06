#!/usr/bin/env bash
# Print Screen: crop a region with slurp, then annotate with satty.
# Satty's own config (~/.config/satty/config.toml) already makes Enter copy
# to clipboard by default — this script does not override that behavior.
# Whatever ends up on the clipboard (the normal path) or gets explicitly
# saved (via satty's own save button) becomes the file the shell briefly
# previews afterwards.
set -uo pipefail

screenshot_dir="$HOME/Pictures/Screenshots"
mkdir -p "$screenshot_dir"

geometry=$(slurp -d) || exit 0

timestamp=$(date +%Y-%m-%d_%H-%M-%S)
output_path="$screenshot_dir/screenshot_${timestamp}.png"

# Clear the clipboard first so that, afterwards, an empty clipboard reliably
# means "nothing was copied" (e.g. Escape) rather than a stale old shot.
wl-copy --clear 2>/dev/null || true

grim -g "$geometry" - | satty --filename - -o "$output_path"

if [ ! -s "$output_path" ]; then
    wl-paste --type image/png > "$output_path" 2>/dev/null || true
    [ -s "$output_path" ] || rm -f "$output_path"
fi

if [ -f "$output_path" ]; then
    quickshell ipc -c dynamic-glacier call dynamicGlacier screenshotTaken "$output_path"
fi
