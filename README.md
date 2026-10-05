# dotfiles

Personal config files for a CachyOS / Hyprland desktop, kept so a fresh install
can be reproduced by copying these files back into place.

## Layout

Paths mirror where each file lives relative to `$HOME`. For example
`.config/hypr/hyprland.lua` here belongs at `~/.config/hypr/hyprland.lua`.

- Shell: `.config/fish/` (plus `.config/fastfetch/` for the `ff` fetch)
- Window manager: `.config/hypr/`, lock screen included (`hyprlock.conf`,
  dressed up as a plain console login)
- Terminal: `.config/kitty/`
- Prompt: `.config/starship.toml`
- GTK/Qt theming: `.config/gtk-3.0/settings.ini`, `.config/kdeglobals`,
  `.config/xsettingsd/`
- Apps: `.config/btop/`, `.config/micro/`, `.config/dolphinrc`,
  `.config/satty/`, `.config/shelly/`,
  `.config/VSCodium/User/settings.json`, `.vim/colors/`
- Themes: `.config/hypr/themes/themes.json` is the list the Theme panel
  (Super+I) shows; `apply-theme.sh` recolours Hyprland, hyprlock, Kitty,
  Starship, btop, micro, the GTK accent and Satty from it, and switches
  Obsidian, VSCodium and vim to that scheme's own port.
  `.config/hypr/themes/assets/` holds the ported schemes that have to be
  copied somewhere (currently the Srcery CSS snippet for Obsidian — Obsidian
  is themed with snippets here, so the vault's own theme is never changed)
- Quickshell: `quickshell/dynamic-glacier/` is the dynamic island shell
  (bar, panels, notifications), deployed to `~/.config/quickshell/dynamic-glacier`
  and run as `quickshell -c dynamic-glacier` — self-contained, it no longer
  needs the `dynamic-glacier-git` package it started from
- System/session bits: `.config/mimeapps.list`, `.config/uwsm/env`,
  `.config/wireplumber/`, `.config/xsettingsd/`, `.config/user-dirs.dirs`,
  `.config/paru/paru.conf`

## The island

Everything lives in the island at the top of the screen. Tap Super on its own
to open it, or go straight to a panel:

- Super+D apps, Super+V clipboard, Super+C calculator, Super+W wallpapers
- Super+R reminders and to-dos, one list: no time means a task you tick off,
  a time means it rings ("szerda nyelvtan", "szerda 10:10 dolgozat").
  Super+B opens the same list
- Super+O órarend (timetable), with each lesson's homework and reminders on it
- Super+T timer, Super+M weather, Super+I themes, Super+S settings
- Super+Escape power menu

Wi-Fi and Bluetooth open from the island itself. The timetable is
`~/.local/share/dynamic-glacier/timetable.json`; press E in the panel to edit it.

## Restoring on a new machine

```sh
git clone https://github.com/Legfena/QS-DFMID26.git
cd QS-DFMID26
./install.sh
```

`install.sh` installs the packages everything here expects and then copies the
configs into place. It uses `paru` or `yay`, whichever is installed (preferring
paru), and offers to build paru when neither is — two of the fonts are AUR-only.
Anything it replaces is copied to `~/.dotfiles-backup/<timestamp>/` first, and
files that already match are left alone, so re-running it is cheap.

```
./install.sh --dry-run       print what would happen, change nothing
./install.sh --no-packages   just deploy the configs
./install.sh --no-apps       skip kitty/dolphin/micro/btop/fish/…
./install.sh --no-backup     overwrite without keeping copies
./install.sh --yes           don't ask anything (passes --noconfirm)
```

One tree does not live at its repo path and the installer handles that:
`quickshell/dynamic-glacier/` goes to `~/.config/quickshell/dynamic-glacier/`.

Left to do by hand afterwards: wallpapers in `~/Pictures/Wallpapers`, a picture of your choice at
`~/.config/fastfetch/fetchimage.png` for `ff`, and
`chsh -s "$(command -v fish)"`.

## What's intentionally excluded

App caches, browser profiles, session/state files (anything a program
rewrites by itself — `fish_variables`, VSCodium's extension list, the trash
and welcome-screen state), and anything holding credentials or personal data
(e.g. Obsidian vault, browser profile, Spotify/Spicetify auth, VSCodium
workspace storage, `.ssh`, shell history, the island's own reminders and
timetable) are left out on purpose since this repo is public. Files the
setup generates for itself, like `hyprlock-colors.conf`, the theme colour
files and `compositor.lua`, aren't tracked either.

## License

Copyright (C) 2026 Legfena. This repository is free software under the
**GNU General Public License v3.0** — see [`LICENSE`](LICENSE). You may use,
change and share it; if you share a modified version, it has to stay under
the GPL too.

Parts that come from other projects keep their own terms:
`quickshell/dynamic-glacier/` is built on [DynamicGlacier](https://github.com/mavxa/DynamicGlacier)
(MIT, © mavxa — its notice is kept in `quickshell/dynamic-glacier/LICENSE`).

## Credits

Big thanks to [mavxa](https://github.com/mavxa) for
[DynamicGlacier](https://github.com/mavxa/DynamicGlacier). The island started
out as that project and I've been modding it ever since, so none of this
would exist without it.
