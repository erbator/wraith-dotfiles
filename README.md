# dotfiles

Personal config files for a CachyOS / Hyprland desktop, kept so a fresh install
can be reproduced by copying these files back into place.

## Layout

Paths mirror where each file lives relative to `$HOME`. For example
`.config/hypr/hyprland.lua` here belongs at `~/.config/hypr/hyprland.lua`.

- Shell: `.config/fish/`
- Window manager: `.config/hypr/`
- Terminal: `.config/kitty/`
- Prompt: `.config/starship.toml`
- GTK/Qt theming: `.config/gtk-3.0/settings.ini`, `.config/kdeglobals`,
  `.config/xsettingsd/`
- Apps: `.config/btop/`, `.config/micro/`, `.config/dolphinrc`,
  `.config/qylock/`, `.config/satty/`, `.config/shelly/`,
  `.config/VSCodium/User/settings.json`, `.vim/colors/`
- Themes: `.config/hypr/themes/themes.json` is the list the Theme panel
  (Super+I) shows; `apply-theme.sh` recolours Hyprland, Kitty, Alacritty,
  Starship, btop, micro, the GTK accent and Satty from it, and switches
  Obsidian, VSCodium and vim to that scheme's own port.
  `.config/hypr/themes/assets/` holds the ported schemes that have to be
  copied somewhere (currently the Srcery CSS snippet for Obsidian — Obsidian
  is themed with snippets here, so the vault's own theme is never changed)
- Quickshell: `quickshell/dynamic-glacier/` is the dynamic island shell
  (bar, panels, notifications), deployed to `~/.config/quickshell/dynamic-glacier`
  and run as `quickshell -c dynamic-glacier` — self-contained, it no longer
  needs the `dynamic-glacier-git` package it started from;
  `quickshell/lockscreen/` is the qylock lockscreen setup, deployed to
  `~/.local/share/quickshell-lockscreen` (themes live in the separate
  `qylock` project)
- System/session bits: `.config/mimeapps.list`, `.config/uwsm/env`,
  `.config/wireplumber/`, `.config/xsettingsd/`, `.config/user-dirs.dirs`,
  `.config/user-dirs.locale`, `.config/paru/paru.conf`
- `patches/` — third-party patches applied on top of installed packages
  (e.g. `dynamic-glacier-git`)

## Restoring on a new machine

```sh
git clone git@github.com:<your-user>/dotfiles.git
cd dotfiles
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
./install.sh --no-apps       skip kitty/dolphin/firefox/micro/btop/fish/…
./install.sh --no-backup     overwrite without keeping copies
./install.sh --yes           don't ask anything (passes --noconfirm)
```

Two trees do not live at their repo path and the installer handles the mapping:
`quickshell/dynamic-glacier/` goes to `~/.config/quickshell/dynamic-glacier/`
and `quickshell/lockscreen/` to `~/.local/share/quickshell-lockscreen/`.
`patches/` is not deployed — it is applied by root against a
`/usr/share/dynamic-glacier` install, which this setup no longer uses.

Left to do by hand afterwards: the hyprglass blur plugin (`hyprpm`), the
lockscreen themes (the separate `qylock` project, symlinked as `themes_link`),
wallpapers in `~/Pictures/Wallpapers`, and `chsh -s "$(command -v fish)"`.

## Extras

`extras/impasto-desktop/install.sh` adds only the desktop widgets from
[impasto](https://github.com/andreumassanet/impasto) (clock, weather,
calendar, media, stats… on the wallpaper, under the windows) as their own
Quickshell config next to dynamic-glacier. Nothing else from impasto runs,
and nothing of yours is touched. See `extras/impasto-desktop/README.md`.

## What's intentionally excluded

App caches, browser profiles, session/state files (anything a program
rewrites by itself — `fish_variables`, VSCodium's extension list, the trash
and welcome-screen state), and anything holding credentials or personal data (e.g. Obsidian vault, Firefox profile, Spotify/
Spicetify auth, VSCodium workspace storage, `.ssh`, shell history) are left
out on purpose since this repo is public.

## License

Copyright (C) 2026 Legfena. This repository is free software under the
**GNU General Public License v3.0** — see [`LICENSE`](LICENSE). You may use,
change and share it; if you share a modified version, it has to stay under
the GPL too.

Parts that come from other projects keep their own terms:
`quickshell/dynamic-glacier/` is built on [DynamicGlacier](https://github.com/mavxa/DynamicGlacier)
(MIT, © mavxa — its notice is kept in `quickshell/dynamic-glacier/LICENSE`),
and the widgets `extras/impasto-desktop/` installs are
[impasto](https://github.com/andreumassanet/impasto)'s own code (GPL-3.0,
fetched from upstream, not included here).

## Credits

This setup stands on two projects, and a huge thank-you goes to both of them.

**[DynamicGlacier](https://github.com/mavxa/DynamicGlacier) by mavxa**, the
dynamic-island shell for Hyprland that `quickshell/dynamic-glacier/` grew out
of. The island itself, its morphing surface and the idea of every panel living
inside it all come from there; everything in this repo is built on that base.
Thank you, mavxa, for making it and sharing it. MIT-licensed; its licence is
kept in `quickshell/dynamic-glacier/LICENSE`.

**[impasto](https://github.com/andreumassanet/impasto) by Andreu Massanet**, a
whole Hyprland shell whose palette comes from a painting. The desktop widgets
that `extras/impasto-desktop/` installs (the clock, weather, calendar, media,
stats and the rest, in both their Modern and Analogue looks) are entirely its
work; the installer only runs them next to the island without touching
anything else. Thank you, Andreu, for such a beautifully made project.
GPL-3.0; its code is fetched from upstream at install time, not copied here,
and its licence goes with the installed copy.

If you like what you see here, go star them.
