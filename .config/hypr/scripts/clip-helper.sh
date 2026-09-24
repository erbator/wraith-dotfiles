#!/usr/bin/env bash
# Backend for the island's clipboard panel (cliphist underneath).
#
# Clipboard content can contain anything, including shell metacharacters, so
# it never appears in a command line: entries arrive through environment
# variables and are only ever expanded as "$VAR", never re-parsed.
#
#   CLIP_LINE=<cliphist list line> clip-helper.sh copy     decode it onto the clipboard
#   CLIP_LINE=...                  clip-helper.sh paste    …then paste into the focused window
#   CLIP_LINE=...                  clip-helper.sh full     print the decoded text (first 20 KB)
#   CLIP_LINE=...                  clip-helper.sh delete   remove it from history
#   CLIP_TEXT=<text>               clip-helper.sh copy-text / paste-text
#   clip-helper.sh copy-file <path> / paste-file <path>    (pinned images)
#   CLIP_LINES=<lines>             clip-helper.sh thumbs   cache image entries for previews
#   CLIP_LINE=... clip-helper.sh save-image <dest>         keep an image for a pin
#   clip-helper.sh wipe                                    clear the history
set -uo pipefail

cache_dir="$HOME/.cache/dynamic-glacier/clipboard"

# Terminals paste with Ctrl+Shift+V, everything else with Ctrl+V.
#
# The shortcut is addressed to the window the user was in, captured before
# waiting: the island is still animating closed and holding the keyboard for
# a moment after the panel is dismissed, and an unaddressed shortcut sent in
# that window lands on the island instead of the app.
send_paste() {
    local window class mods
    window=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // ""')
    class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // ""')

    case "$class" in
        kitty|Alacritty|foot|org.wezfurlong.wezterm|com.mitchellh.ghostty|konsole|org.kde.konsole)
            mods="CTRL SHIFT" ;;
        *)
            mods="CTRL" ;;
    esac

    sleep 0.35

    if [ -n "$window" ]; then
        hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$mods\", key = \"V\", window = \"address:$window\" })" >/dev/null
    else
        hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$mods\", key = \"V\" })" >/dev/null
    fi
}

case "${1:-}" in
    copy)
        printf '%s' "$CLIP_LINE" | cliphist decode | wl-copy
        ;;
    paste)
        printf '%s' "$CLIP_LINE" | cliphist decode | wl-copy
        send_paste
        ;;
    full)
        printf '%s' "$CLIP_LINE" | cliphist decode | head -c 20000
        ;;
    delete)
        printf '%s' "$CLIP_LINE" | cliphist delete
        ;;
    copy-text)
        printf '%s' "$CLIP_TEXT" | wl-copy
        ;;
    paste-text)
        printf '%s' "$CLIP_TEXT" | wl-copy
        send_paste
        ;;
    copy-file)
        wl-copy < "$2"
        ;;
    paste-file)
        wl-copy < "$2"
        send_paste
        ;;
    save-image)
        mkdir -p "$(dirname "$2")"
        printf '%s' "$CLIP_LINE" | cliphist decode > "$2"
        ;;
    thumbs)
        # Decodes image entries once; later opens reuse the cached file.
        mkdir -p "$cache_dir"
        printf '%s\n' "$CLIP_LINES" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            id="${line%%$'\t'*}"
            case "$id" in *[!0-9]*|'') continue ;; esac
            file="$cache_dir/$id.img"
            [ -s "$file" ] || printf '%s' "$line" | cliphist decode > "$file" 2>/dev/null
        done
        echo done
        ;;
    wipe)
        cliphist wipe
        rm -rf "$cache_dir"
        ;;
    *)
        echo "usage: see the header of $0" >&2
        exit 1
        ;;
esac
