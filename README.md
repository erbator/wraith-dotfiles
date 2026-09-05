# dotfiles

Personal config files for a CachyOS / Hyprland desktop, kept so a fresh install
can be reproduced by copying these files back into place.

## Layout

Paths mirror where each file lives relative to `$HOME`. For example
`.config/hypr/hyprland.lua` here belongs at `~/.config/hypr/hyprland.lua`.

- Shell: `.bashrc`, `.bash_profile`, `.bash_logout`, `.zshrc`, `.config/fish/`
- Window manager: `.config/hypr/`
- Terminal: `.config/kitty/`, `.config/alacritty/`
- Prompt/theme: `.config/starship.toml`, `.config/gruvbox-rainbow.toml`,
  `.config/pastel-powerline.toml`, `.config/nerd-font-symbols.toml`
- GTK/Qt theming: `.config/gtk-3.0/`, `.config/gtk-4.0/`, `.config/qt5ct/`,
  `.config/qt6ct/`, `.config/kdeglobals`
- Apps: `.config/btop/`, `.config/micro/`, `.config/mako/`, `.config/dolphinrc`,
  `.config/qylock/`, `.config/satty/`, `.config/shelly/`,
  `.config/VSCodium/User/`, `.vscode-oss/`
- System/session bits: `.config/mimeapps.list`, `.config/uwsm/env`,
  `.config/wireplumber/`, `.config/xsettingsd/`, `.config/user-dirs.dirs`,
  `.config/user-dirs.locale`, `.config/paru/paru.conf`
- `patches/` — third-party patches applied on top of installed packages
  (e.g. `dynamic-glacier-git`)

## Restoring on a new machine

```sh
git clone git@github.com:<your-user>/dotfiles.git
cd dotfiles
cp -a . ~/          # copies dotfiles + .config subtrees into place
```

Review diffs before overwriting an existing `~/.config` on a machine that
already has other configs you care about — this repo is not stow-managed and
will overwrite matching files.

## What's intentionally excluded

App caches, browser profiles, session/state files, and anything holding
credentials or personal data (e.g. Obsidian vault, Firefox profile, Spotify/
Spicetify auth, VSCodium workspace storage, `.ssh`, shell history) are left
out on purpose since this repo is public.
