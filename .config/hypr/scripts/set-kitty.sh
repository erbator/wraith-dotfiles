#!/usr/bin/env bash
# Changes one kitty setting from the Glacier settings panel's Terminal tab and
# reloads every open kitty window.
#
# Usage: set-kitty.sh <setting> <value>
#
#   font_family            a font family name
#   font_size              points, 6-32
#   background_opacity     0.30-1.00 (only the background fades, text stays
#                          crisp — which is why terminals get this rather than
#                          Hyprland's window opacity)
#   window_padding_width   pixels, 0-40
#   cursor_shape           block | beam | underline
#   cursor_trail           0 (off) or 1 (on)
#
# Edits the matching line in kitty.conf in place (appending it if absent),
# then sends SIGUSR1, which makes kitty re-read its config.
set -euo pipefail

key="${1:-}"
value="${2:-}"
config="$HOME/.config/kitty/kitty.conf"

[ -f "$config" ] || { echo "no kitty.conf at $config" >&2; exit 1; }

case "$key" in
    font_family)
        [ -n "$value" ] || { echo "font_family needs a name" >&2; exit 1; }
        line="font_family      family=\"$value\""
        ;;
    font_size)
        [ "$value" -ge 6 ] 2>/dev/null && [ "$value" -le 32 ] || { echo "font_size must be 6-32" >&2; exit 1; }
        line="font_size        $value"
        ;;
    background_opacity)
        [[ "$value" =~ ^(0\.[0-9]{1,2}|1(\.0+)?)$ ]] || { echo "background_opacity must be 0.00-1.00" >&2; exit 1; }
        line="background_opacity          $value"
        ;;
    window_padding_width)
        [ "$value" -ge 0 ] 2>/dev/null && [ "$value" -le 40 ] || { echo "padding must be 0-40" >&2; exit 1; }
        line="window_padding_width        $value"
        ;;
    cursor_shape)
        case "$value" in block|beam|underline) ;; *) echo "cursor_shape must be block, beam or underline" >&2; exit 1 ;; esac
        line="cursor_shape                $value"
        ;;
    cursor_trail)
        case "$value" in 0|1) ;; *) echo "cursor_trail must be 0 or 1" >&2; exit 1 ;; esac
        line="cursor_trail                $value"
        ;;
    *)
        echo "unsupported setting: $key" >&2
        exit 1
        ;;
esac

# Replace the first active (uncommented) line for this key, else append.
if grep -qE "^${key}([[:space:]]|$)" "$config"; then
    tmp=$(mktemp)
    awk -v key="$key" -v line="$line" '
        !done && $1 == key { print line; done = 1; next }
        { print }
    ' "$config" > "$tmp"
    cat "$tmp" > "$config"
    rm -f "$tmp"
else
    # kitty.conf is often saved without a final newline; without this the
    # new line would be glued onto whatever the last line was.
    [ -n "$(tail -c1 "$config")" ] && printf '\n' >> "$config"
    printf '%s\n' "$line" >> "$config"
fi

pkill -USR1 -x kitty 2>/dev/null || true
