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

# Fingerprint the clipboard instead of clearing it: clearing meant that
# cancelling satty with Escape left the user with an empty clipboard.
clipboard_fingerprint() {
    wl-paste --type image/png 2>/dev/null | md5sum | cut -d' ' -f1
}

before=$(clipboard_fingerprint)

grim -g "$geometry" - | satty --filename - -o "$output_path"

# Nothing saved explicitly — see whether satty put a *new* image on the
# clipboard (the default Enter action). Same fingerprint as before means the
# user backed out, so leave both the clipboard and the disk alone.
if [ ! -s "$output_path" ]; then
    after=$(clipboard_fingerprint)

    if [ "$after" != "$before" ]; then
        wl-paste --type image/png > "$output_path" 2>/dev/null || true
    fi

    [ -s "$output_path" ] || rm -f "$output_path"
fi

if [ -f "$output_path" ]; then
    quickshell ipc -c dynamic-glacier call dynamicGlacier screenshotTaken "$output_path"
fi
