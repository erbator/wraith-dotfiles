#!/usr/bin/env bash
# impasto-desktop — only the desktop widgets from impasto, nothing else.
#
#   extras/impasto-desktop/install.sh              install / update
#   extras/impasto-desktop/install.sh --uninstall  remove it (keeps your layout)
#   extras/impasto-desktop/install.sh --purge      remove it and its layout
#   extras/impasto-desktop/install.sh --no-start   install without starting it
#
# github.com/andreumassanet/impasto is a whole shell (bar, island, dock, lock,
# theming…). This takes its Quickshell code at a pinned commit and runs only
# the widget layer under the windows, as its own Quickshell config next to
# dynamic-glacier:
#
#   ~/.config/quickshell/impasto-desktop    the code (patched, see patch.py)
#   ~/.local/state/impasto-desktop          your widget layout and settings
#   autostart.lua                           one line, marked "impasto-desktop"
#
# Nothing else from impasto is installed or run: no bar, island, dock, lock,
# notifications, wallpapers, key binds, and no palette pushed into your
# terminal, GTK or other programs. The widgets take their colours from your
# current wallpaper. Code: GPL-3.0, © impasto's authors.
set -euo pipefail

REPO="https://github.com/andreumassanet/impasto"
PIN="9a6af464db8da2f78c700233915125f0a753a1ce"
NAME="impasto-desktop"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DEST="$CONFIG_HOME/quickshell/$NAME"
SRC="${XDG_CACHE_HOME:-$HOME/.cache}/$NAME/impasto"
STATE="$HOME/.local/state/$NAME"
FONTS="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/$NAME"
AUTOSTART="$CONFIG_HOME/hypr/config/autostart.lua"
AUTOSTART_LINE='    hl.exec_cmd(LAUNCH_PREFIX .. "quickshell -c impasto-desktop") -- impasto-desktop'

say()  { printf '\033[1;32m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m::\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m::\033[0m %s\n' "$*" >&2; exit 1; }

stop_running() {
    quickshell kill -c "$NAME" >/dev/null 2>&1 || true
}

remove_autostart() {
    [ -f "$AUTOSTART" ] && sed -i '/-- impasto-desktop$/d' "$AUTOSTART"
}

uninstall() {
    stop_running
    rm -rf "$DEST" "$FONTS" "$(dirname "$SRC")"
    remove_autostart
    command -v fc-cache >/dev/null && fc-cache -f >/dev/null 2>&1 || true
    if [ "${1:-}" = purge ]; then
        rm -rf "$STATE"
        say "Removed impasto-desktop and its layout."
    else
        say "Removed impasto-desktop. Your layout is kept in $STATE (--purge removes it)."
    fi
}

start=1
case "${1:-}" in
    --uninstall) uninstall; exit 0 ;;
    --purge) uninstall purge; exit 0 ;;
    --no-start) start=0 ;;
    "") ;;
    *) die "unknown option: $1 (try --uninstall, --purge or --no-start)" ;;
esac

# ── requirements ────────────────────────────────────────────────────────────
missing=()
for cmd in quickshell python3 git magick awww; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
[ ${#missing[@]} -eq 0 ] || die "missing: ${missing[*]} (pacman -S quickshell python git imagemagick awww)"

# Widgets that switch themselves off without their program.
optional=()
command -v cava >/dev/null || optional+=("cava (music spectrum)")
command -v imv >/dev/null || optional+=("imv (photo widget viewer)")
command -v checkupdates >/dev/null || optional+=("pacman-contrib (updates widget)")
command -v nmcli >/dev/null || optional+=("networkmanager (network widget)")
fc-list 2>/dev/null | grep -qi "Inter" || optional+=("inter-font (impasto's typeface)")

# ── fetch impasto at the pinned commit ──────────────────────────────────────
say "Fetching impasto @ ${PIN:0:7}"
mkdir -p "$SRC"
if [ ! -d "$SRC/.git" ]; then
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$REPO"
fi
git -C "$SRC" fetch -q --depth 1 origin "$PIN"
git -C "$SRC" checkout -q --force FETCH_HEAD

# ── stage, patch, swap in ───────────────────────────────────────────────────
say "Installing the desktop widgets into $DEST"
stage="$DEST.new"
rm -rf "$stage"
mkdir -p "$(dirname "$DEST")"
cp -a "$SRC/home/.config/quickshell" "$stage"
cp "$SRC/LICENSE" "$stage/LICENSE"
printf 'impasto-desktop: impasto %s @ %s, patched by extras/impasto-desktop/patch.py\n' "$REPO" "$PIN" > "$stage/SOURCE"
python3 "$HERE/patch.py" "$stage" "$HERE" >/dev/null

stop_running
rm -rf "$DEST"
mv "$stage" "$DEST"
mkdir -p "$STATE"

# First install only: start from impasto's "moon castle" desk — a column of
# widgets down each edge, clear of the island — instead of an empty one.
if [ ! -e "$STATE/.seeded" ]; then
    python3 - "$SRC/home/.local/share/impasto/profiles/1-moon-castle.json" "$STATE/settings.json" <<'SEED' || warn "couldn't seed the starter layout (right-click the wallpaper to add widgets)"
import json, sys
profile, target = sys.argv[1], sys.argv[2]
starter = json.load(open(profile))["settings"]
try:
    settings = json.load(open(target))
except (OSError, ValueError):
    settings = {}
if not settings.get("desktopWidgets"):
    for key in ("desktopWidgets", "desktopTheme", "desktopStyle"):
        if key in starter:
            settings[key] = starter[key]
    json.dump(settings, open(target, "w"), indent=4)
SEED
    touch "$STATE/.seeded"
fi

# The handwriting face the note widget writes in.
if [ -f "$SRC/home/.local/share/fonts/GrapeNuts-Regular.ttf" ]; then
    mkdir -p "$FONTS"
    cp "$SRC/home/.local/share/fonts/GrapeNuts-Regular.ttf" "$SRC/home/.local/share/fonts/GrapeNuts-OFL.txt" "$FONTS/"
    command -v fc-cache >/dev/null && fc-cache -f "$FONTS" >/dev/null 2>&1 || true
fi

# ── autostart, next to dynamic-glacier ──────────────────────────────────────
if [ -f "$AUTOSTART" ]; then
    if ! grep -q -- '-- impasto-desktop$' "$AUTOSTART"; then
        if grep -q 'quickshell -c dynamic-glacier' "$AUTOSTART"; then
            sed -i "/quickshell -c dynamic-glacier/a\\
$AUTOSTART_LINE" "$AUTOSTART"
        else
            sed -i "/hl.on(\"hyprland.start\", function ()/a\\
$AUTOSTART_LINE" "$AUTOSTART"
        fi
    fi
    grep -q -- '-- impasto-desktop$' "$AUTOSTART" || warn "couldn't add the autostart line; start it with: quickshell -c $NAME"
else
    warn "no $AUTOSTART — start it with: quickshell -c $NAME"
fi

if [ "$start" = 1 ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    setsid -f quickshell -c "$NAME" >/dev/null 2>&1 < /dev/null
    say "Started. Right-click the wallpaper to add and arrange widgets."
else
    say "Installed. It starts with Hyprland (or now: quickshell -c $NAME)."
fi

if [ ${#optional[@]} -gt 0 ]; then
    warn "optional, for some widgets:"
    for item in "${optional[@]}"; do
        printf '     %s\n' "$item"
    done
fi
