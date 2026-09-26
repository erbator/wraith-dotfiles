#!/usr/bin/env bash
# Installs these dotfiles on a fresh Arch/CachyOS + Hyprland machine: the
# packages everything here expects, then the config files themselves.
#
#   ./install.sh                 packages + configs (asks before each stage)
#   ./install.sh --no-packages   just deploy the configs
#   ./install.sh --no-apps       skip the optional application packages
#   ./install.sh --dry-run       print what would happen, change nothing
#   ./install.sh --yes           don't ask anything (implies --noconfirm)
#
# Existing files are moved into a timestamped backup directory before they
# are replaced, so a machine that already has configs can be rolled back.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

install_packages=1
install_apps=1
do_backup=1
dry_run=0
assume_yes=0

# ── OUTPUT ──────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
    BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GREEN=$'\e[32m'
    YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$BLUE" "$RESET" "$BOLD" "$1" "$RESET"; }
info() { printf '    %s\n' "$1"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '    %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
ok()   { printf '    %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
# Shortens a path for display; ~ in a substitution replacement is a bash
# version minefield, so it is spelled out.
tilde() {
    case "$1" in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# Yes/no prompt. --yes answers everything with yes; a non-interactive shell
# (piped installer) does the same rather than hanging on read.
confirm() {
    [ "$assume_yes" -eq 1 ] && return 0
    [ -t 0 ] || return 0

    local reply
    printf '    %s?%s %s [Y/n] ' "$YELLOW" "$RESET" "$1"
    read -r reply || reply=""

    case "$reply" in
        [nN]|[nN][oO]) return 1 ;;
        *) return 0 ;;
    esac
}

# ── PACKAGES ────────────────────────────────────────────────────────────────

# The session and everything the shell, keybinds and helper scripts call.
CORE_PACKAGES=(
    # Compositor and session
    hyprland hyprpm uwsm xdg-desktop-portal xdg-desktop-portal-gtk
    qt6-wayland qt6-declarative polkit
    # The Quickshell bar/island itself
    quickshell
    # Hardware and services the panels read and control
    networkmanager bluez bluez-utils
    pipewire pipewire-pulse wireplumber libpulse
    upower power-profiles-daemon brightnessctl playerctl
    # Wallpaper, clipboard, screenshots, colour picker
    awww cliphist wl-clipboard grim slurp satty hyprpicker
    # Wallpaper thumbnails (wall-thumbs.sh; falls back to ImageMagick)
    libvips
    # Used by the scripts in .config/hypr/scripts
    jq curl psmisc
    # Fonts: Material Symbols draws every icon in the shell, the Nerd Fonts
    # are the selectable families in Settings, SF Pro is the UI font.
    ttf-material-symbols-variable
    ttf-firacode-nerd ttf-cascadia-code-nerd ttf-meslo-nerd ttf-hack-nerd
    nerd-fonts-sf-mono otf-apple-sf-pro
    noto-fonts noto-fonts-emoji
)

# The programs whose configs ship in this repo. Nothing breaks without them,
# so --no-apps skips the lot.
APP_PACKAGES=(
    kitty dolphin firefox micro btop fastfetch
    fish starship zoxide fzf vim neovim
)

# ── ARGUMENTS ───────────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        --no-packages) install_packages=0 ;;
        --no-apps) install_apps=0 ;;
        --no-backup) do_backup=0 ;;
        --dry-run) dry_run=1 ;;
        -y|--yes) assume_yes=1 ;;
        -h|--help)
            sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

# ── CHECKS ──────────────────────────────────────────────────────────────────

[ "$(id -u)" -eq 0 ] && die "run as your normal user, not root — it installs into \$HOME (the package step calls sudo itself)"
command -v pacman >/dev/null 2>&1 || die "this installer is for Arch-based systems (no pacman found)"
[ -d "$REPO/.config/hypr" ] || die "run this from inside the dotfiles repo (no .config/hypr next to the script)"

printf '%s%sdotfiles installer%s  %s%s%s\n' "$BOLD" "$BLUE" "$RESET" "$DIM" "$REPO" "$RESET"
[ "$dry_run" -eq 1 ] && warn "dry run — nothing will be installed or written"

# ── AUR HELPER ──────────────────────────────────────────────────────────────

# paru and yay take the same flags, so the rest of the script only needs the
# name. paru wins when both are installed; with neither, offer to build it.
find_aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        echo paru
    elif command -v yay >/dev/null 2>&1; then
        echo yay
    fi
}

bootstrap_paru() {
    local build
    build="$(mktemp -d)"

    info "building paru from the AUR in $build"
    sudo pacman -S --needed --noconfirm base-devel git
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$build/paru-bin"
    (cd "$build/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$build"
}

install_package_set() {
    local label="$1"
    shift
    local wanted=("$@")
    local missing=()
    local package

    for package in "${wanted[@]}"; do
        pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        ok "$label: all ${#wanted[@]} packages already installed"
        return 0
    fi

    info "$label: ${#missing[@]} of ${#wanted[@]} missing"
    note "${missing[*]}"

    if [ "$dry_run" -eq 1 ]; then
        note "would run: ${INSTALL_CMD[*]} -S --needed ${missing[*]}"
        return 0
    fi

    local flags=(-S --needed)
    [ "$assume_yes" -eq 1 ] && flags+=(--noconfirm)

    # Not fatal: a single unavailable package should not stop the config
    # deployment, which is the part that is hard to redo by hand.
    if ! "${INSTALL_CMD[@]}" "${flags[@]}" "${missing[@]}"; then
        warn "${INSTALL_CMD[*]} could not install everything — check the output above"
        return 1
    fi

    ok "$label installed"
}

if [ "$install_packages" -eq 1 ]; then
    step "Package manager"

    AUR_HELPER="$(find_aur_helper)"

    if [ -n "$AUR_HELPER" ]; then
        INSTALL_CMD=("$AUR_HELPER")
        ok "using $AUR_HELPER ($("$AUR_HELPER" --version 2>/dev/null | head -1))"
    else
        warn "neither paru nor yay is installed"
        note "two of the fonts (nerd-fonts-sf-mono, otf-apple-sf-pro) are AUR-only"

        if [ "$dry_run" -eq 1 ]; then
            note "would offer to build paru from the AUR"
            INSTALL_CMD=(paru)
        elif confirm "build paru from the AUR now?"; then
            bootstrap_paru
            INSTALL_CMD=(paru)
            ok "paru installed"
        else
            warn "carrying on with pacman — the AUR-only packages will be skipped"
            INSTALL_CMD=(sudo pacman)
        fi
    fi

    # Without a helper the AUR entries would abort the whole transaction, so
    # drop anything pacman cannot see and say which ones were left out.
    if [ "${INSTALL_CMD[0]}" = "sudo" ]; then
        aur_only=()
        repo_only=()

        for package in "${CORE_PACKAGES[@]}"; do
            if pacman -Si "$package" >/dev/null 2>&1 || pacman -Qq "$package" >/dev/null 2>&1; then
                repo_only+=("$package")
            else
                aur_only+=("$package")
            fi
        done

        CORE_PACKAGES=("${repo_only[@]}")
        [ ${#aur_only[@]} -gt 0 ] && warn "not in any repo, install later with an AUR helper: ${aur_only[*]}"
    fi

    step "Core packages"
    install_package_set "core" "${CORE_PACKAGES[@]}" || true

    if [ "$install_apps" -eq 1 ]; then
        step "Application packages"
        install_package_set "apps" "${APP_PACKAGES[@]}" || true
    fi
fi

# ── DEPLOY ──────────────────────────────────────────────────────────────────

backed_up=0
deployed=0

# Copies one file into place, stashing whatever was there first. Identical
# files are left alone so a re-run is quiet and fast.
deploy_file() {
    local src="$1" dest="$2"

    if [ -e "$dest" ] && cmp -s "$src" "$dest"; then
        return 0
    fi

    deployed=$((deployed + 1))

    if [ "$dry_run" -eq 1 ]; then
        note "$(tilde "$dest")"
        return 0
    fi

    if [ -e "$dest" ] && [ "$do_backup" -eq 1 ]; then
        local relative="${dest#"$HOME"/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
        cp -a "$dest" "$BACKUP_DIR/$relative"
        backed_up=$((backed_up + 1))
    fi

    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
}

# Every file this repo owns, as paths relative to its root. A git checkout
# is asked directly, so untracked scratch files lying around in a working
# copy are never deployed; a plain download (no .git) falls back to walking
# the tree, which holds only repo content anyway.
repo_files() {
    if [ -d "$REPO/.git" ] && command -v git >/dev/null 2>&1; then
        git -C "$REPO" ls-files -z
    else
        (cd "$REPO" && find . -type f -not -path "./.git/*" -printf '%P\0' | sort -z)
    fi
}

step "Configuration files"
note "backups: $(tilde "$BACKUP_DIR")"

while IFS= read -r -d '' relative; do
    case "$relative" in
        # The two trees that do not live at their repo path.
        quickshell/dynamic-glacier/*)
            deploy_file "$REPO/$relative" "$HOME/.config/$relative"
            ;;
        quickshell/lockscreen/*)
            deploy_file "$REPO/$relative" "$HOME/.local/share/quickshell-lockscreen/${relative#quickshell/lockscreen/}"
            ;;
        # Repo furniture: the patch set is applied by hand, by root.
        patches/*|.github/*|*/.gitkeep) ;;
        # Anything at the top level (README, this script, .gitignore).
        */*) deploy_file "$REPO/$relative" "$HOME/$relative" ;;
        *) ;;
    esac
done < <(repo_files)

if [ "$dry_run" -eq 1 ]; then
    ok "$deployed files would be written"
else
    ok "$deployed files written, $backed_up backed up"
    # An empty backup directory is just noise (nothing was replaced).
    [ "$backed_up" -eq 0 ] && rmdir "$BACKUP_DIR" 2>/dev/null || true
fi

# ── FINISHING TOUCHES ───────────────────────────────────────────────────────

step "Permissions and directories"

if [ "$dry_run" -eq 0 ]; then
    chmod +x "$HOME"/.config/hypr/scripts/*.sh 2>/dev/null || true
    chmod +x "$HOME"/.local/share/quickshell-lockscreen/lock.sh 2>/dev/null || true
    ok "helper scripts made executable"

    # Screenshots and the wallpaper picker both expect their folder to exist;
    # the shell writes its caches and state under the other two.
    mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers" \
             "$HOME/.cache/dynamic-glacier" "$HOME/.local/state/quickshell"
    ok "Pictures/Screenshots, Pictures/Wallpapers, caches and state ready"

    # Warm the exchange-rate cache so the calculator can convert offline.
    if [ -x "$HOME/.config/hypr/scripts/currency-rates.sh" ]; then
        if "$HOME/.config/hypr/scripts/currency-rates.sh" 2>/dev/null; then
            ok "exchange rates fetched"
        else
            note "exchange rates not fetched (no network?) — retried whenever the calculator opens"
        fi
    fi

    # Several files are generated by the theme rather than shipped: the GTK
    # accent, btop's theme, micro's colorscheme. Applying the saved theme
    # (or the default) writes them all, so a fresh machine is not left
    # pointing at colour files that do not exist yet.
    if [ -x "$HOME/.config/hypr/scripts/apply-theme.sh" ]; then
        theme="srcery"
        [ -s "$HOME/.config/hypr/themes/current" ] && theme="$(cat "$HOME/.config/hypr/themes/current")"

        # The Srcery VSCodium theme is an extension, not a colour file, so
        # the editor keeps its old theme until it is installed.
        if command -v codium >/dev/null 2>&1 && ! codium --list-extensions 2>/dev/null | grep -qi "^srcery-colors"; then
            codium --install-extension srcery-colors.srcery-colors >/dev/null 2>&1 \
                && ok "VSCodium Srcery theme installed" \
                || note "could not install the VSCodium Srcery theme (offline?)"
        fi

        # The compositor overrides are generated too, and Hyprland fails to
        # find the file the config requires until they exist.
        if [ -x "$HOME/.config/hypr/scripts/set-compositor.sh" ] && [ ! -f "$HOME/.config/hypr/config/compositor.lua" ]; then
            "$HOME/.config/hypr/scripts/set-compositor.sh" >/dev/null 2>&1 \
                && ok "compositor defaults written" \
                || note "could not write the compositor defaults"
        fi

        if "$HOME/.config/hypr/scripts/apply-theme.sh" "$theme" >/dev/null 2>&1; then
            ok "theme applied: $theme"
        else
            warn "could not apply the $theme theme — run apply-theme.sh by hand"
        fi
    fi
else
    note "would chmod +x the hypr scripts and the lockscreen launcher"
    note "would create Pictures/Screenshots, Pictures/Wallpapers, caches and state"
    note "would apply the saved theme (or srcery) to generate the colour files"
fi

step "Services"

for service in NetworkManager bluetooth; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        ok "$service already enabled"
    elif [ "$dry_run" -eq 1 ]; then
        note "would offer to enable $service"
    elif confirm "enable and start $service?"; then
        sudo systemctl enable --now "$service"
        ok "$service enabled"
    fi
done

# ── WHAT IS LEFT TO DO BY HAND ──────────────────────────────────────────────

step "Done"

[ -f /usr/share/hypr/hyprland.lua ] || warn "this Hyprland does not look like the CachyOS build with Lua config support — ~/.config/hypr/hyprland.lua will be ignored by a stock Hyprland"

if [ "$SHELL" != "$(command -v fish 2>/dev/null)" ] && command -v fish >/dev/null 2>&1; then
    note "fish is installed but is not your login shell: chsh -s \"\$(command -v fish)\""
fi

if [ ! -e "$HOME/.local/share/quickshell-lockscreen/themes_link" ]; then
    note "lockscreen themes are a separate project — symlink them once you have it:"
    note "  ln -s ~/Projects/qylock/themes ~/.local/share/quickshell-lockscreen/themes_link"
fi

note "the hyprglass blur plugin is managed by hyprpm, not pacman:"
note "  hyprpm add <hyprglass repo> && hyprpm enable hyprglass"
note "drop some wallpapers into ~/Pictures/Wallpapers, then log into Hyprland"
note "the island starts itself from .config/hypr/config/autostart.lua; to start it now:"
note "  quickshell -c dynamic-glacier &"
