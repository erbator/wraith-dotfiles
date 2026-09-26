# impasto-desktop

Only the **desktop widgets** from [impasto](https://github.com/andreumassanet/impasto),
running as their own Quickshell config next to dynamic-glacier. Nothing else
from impasto is installed or started.

```sh
extras/impasto-desktop/install.sh              # install / update
extras/impasto-desktop/install.sh --uninstall  # remove (keeps your layout)
extras/impasto-desktop/install.sh --purge      # remove, layout too
```

**Using it:** right-click the wallpaper to arrange. A card lists every widget:
drag one out, drag to move, pull a corner for another shape (square, card,
large, band), click one to pick its look (*Modern* or *Analogue*). Escape or
a right-click ends arranging. The widgets sit on the bottom layer, under your
windows.

## What it does and doesn't touch

impasto is a whole shell. `install.sh` takes its `home/.config/quickshell` at a
pinned commit, replaces `shell.qml` with one that starts only the widget layer
(`desktop/`), and `patch.py` makes sure nothing that layer loads acts on the
rest of the system:

| impasto normally… | here |
|---|---|
| runs its bar, island, dock, lock screen, settings window | not started |
| is your notification daemon | server removed (dynamic-glacier stays yours) |
| pushes Hyprland options, monitor layouts, key binds | `hyprctl` goes through `guard/hyprctl`: queries and dispatch only |
| sets the wallpaper, writes palettes into kitty, GTK, Qt, btop, VSCodium… | its scripts run only their read-only verbs |
| locks / suspends on idle, holds sleep, runs a night light | disabled |
| runs its own clipboard watcher | not started (cliphist keeps yours) |

The widgets still read the palette from your current wallpaper (via `awww query`),
so they match it. Layout and settings live in `~/.local/state/impasto-desktop`.

Files: `~/.config/quickshell/impasto-desktop` (code), one marked line in
`~/.config/hypr/config/autostart.lua`, and the handwriting font in
`~/.local/share/fonts/impasto-desktop`.

To move to a newer impasto, change `PIN` in `install.sh` and re-run it; if
upstream changed something `patch.py` expects, the install stops before
touching anything.

impasto is GPL-3.0; its licence is copied into the installed config.
