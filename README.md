# dotfiles

Personal config files for a CachyOS / Hyprland desktop, kept so a fresh install
can be reproduced by copying these files back into place.

## Layout

Paths mirror where each file lives relative to `$HOME`. For example
`.config/hypr/hyprland.lua` here belongs at `~/.config/hypr/hyprland.lua`.

- Shell: `.config/fish/`
- Window manager: `.config/hypr/`
- Terminal: `.config/kitty/`
- Prompt/theme: `.config/starship.toml`, `.config/gruvbox-rainbow.toml`,
  `.config/pastel-powerline.toml`, `.config/nerd-font-symbols.toml`
- GTK/Qt theming: `.config/gtk-3.0/`, `.config/gtk-4.0/`, `.config/qt5ct/`,
  `.config/qt6ct/`, `.config/kdeglobals`
- Apps: `.config/btop/`, `.config/micro/`, `.config/mako/`, `.config/dolphinrc`,
  `.config/qylock/`, `.config/satty/`, `.config/shelly/`,
  `.config/VSCodium/User/`, `.vscode-oss/`
- Quickshell: `quickshell/dynamic-glacier/` is a snapshot of the live, patched
  `/usr/share/dynamic-glacier` shell (the bar/panel system driven by the
  `dynamic-glacier-git` AUR package, customized via `patches/dynamic-glacier-git/`);
  `quickshell/lockscreen/` is the deployed qylock lockscreen quickshell setup
  from `~/.local/share/quickshell-lockscreen` (themes live in the separate
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

## What's intentionally excluded

App caches, browser profiles, session/state files, and anything holding
credentials or personal data (e.g. Obsidian vault, Firefox profile, Spotify/
Spicetify auth, VSCodium workspace storage, `.ssh`, shell history) are left
out on purpose since this repo is public.
