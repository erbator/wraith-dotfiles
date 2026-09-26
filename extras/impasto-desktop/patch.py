#!/usr/bin/env python3
"""Turn a copy of impasto's Quickshell tree into impasto-desktop.

    patch.py <staged config dir> <extras dir>

Only the desktop widgets run, and nothing they load may change the rest of
the system. Every edit asserts that the text it replaces is there, so an
upstream change fails the install loudly instead of half-applying.

What is neutralised, and how:
  - shell.qml            replaced: the desktop layer and nothing else
  - hyprctl              impasto's own calls go through guard/hyprctl (queries
                         and dispatch only: no eval/keyword/reload)
  - hyprsunset,          impasto's night light and sleep hold → guard/noop
    systemd-inhibit
  - scripts              the ones that write outside impasto's files run only
                         their read-only verbs (see GUARDED)
  - NotificationServer   removed — dynamic-glacier is your notification daemon
  - IdleMonitor          disabled — no locking or suspending on idle
  - clipboard watcher    not started — cliphist already keeps your history
  - state                ~/.local/state/impasto-desktop, not impasto's paths
"""
import os
import re
import shutil
import stat
import sys

dest, extras = sys.argv[1], sys.argv[2]


def path(*parts):
    return os.path.join(dest, *parts)


def edit(rel, old, new, count=1, regex=False):
    file = path(rel)
    with open(file, encoding="utf-8") as handle:
        text = handle.read()
    if regex:
        text, n = re.subn(old, new, text)
        ok = n >= count
    else:
        ok = old in text
        text = text.replace(old, new) if count == "all" else text.replace(old, new, count)
    if not ok:
        sys.exit(f"patch.py: upstream changed, can't find expected text in {rel}:\n  {old[:90]}")
    with open(file, "w", encoding="utf-8") as handle:
        handle.write(text)


def executable(file):
    os.chmod(file, os.stat(file).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


# ── entry point ────────────────────────────────────────────────────────────
shutil.copy(os.path.join(extras, "shell.qml"), path("shell.qml"))

# ── guards ─────────────────────────────────────────────────────────────────
os.makedirs(path("guard"), exist_ok=True)
for name in ("hyprctl", "noop"):
    shutil.copy(os.path.join(extras, "guard", name), path("guard", name))
    executable(path("guard", name))

# Every Process that starts hyprctl / hyprsunset / systemd-inhibit by name.
GUARD_HYPRCTL = 'Quickshell.shellPath("guard/hyprctl")'
GUARD_NOOP = 'Quickshell.shellPath("guard/noop")'
for folder, _, files in os.walk(dest):
    for name in files:
        if not name.endswith(".qml"):
            continue
        file = os.path.join(folder, name)
        with open(file, encoding="utf-8") as handle:
            text = handle.read()
        new = text.replace('["hyprctl"', "[" + GUARD_HYPRCTL)
        new = new.replace('["hyprsunset"', "[" + GUARD_NOOP)
        new = new.replace('["systemd-inhibit"', "[" + GUARD_NOOP)
        if new != text:
            with open(file, "w", encoding="utf-8") as handle:
                handle.write(new)

# Scripts that write into other programs' configs, Hyprland or the clipboard:
# only the listed verbs reach the real script (kept in scripts/.upstream so
# their imports of each other still resolve); anything else exits 0.
GUARDED = {
    "theme_manager.py": ["list-wallpapers", "get-current", "get-state", "extract-colors"],
    "compositor.py": ["layouts", "available", "rules", "get"],
    "monitors.py": ["get"],
    "clipboard.py": [],
    "greeting.py": [],
}
upstream = path("scripts", ".upstream")
os.makedirs(upstream, exist_ok=True)
for name in os.listdir(path("scripts")):
    source = path("scripts", name)
    if os.path.isfile(source):
        shutil.copy2(source, os.path.join(upstream, name))
state_home = os.path.join(os.path.expanduser("~"), ".local", "state", "impasto-desktop")
for name, verbs in GUARDED.items():
    if not os.path.isfile(path("scripts", name)):
        sys.exit(f"patch.py: upstream changed, scripts/{name} is gone")
    wrapper = f'''#!/usr/bin/env python3
# impasto-desktop guard: only read-only verbs reach the real {name}
# (scripts/.upstream/{name}); the rest would write outside the widgets.
import os
import sys

ALLOWED = {verbs!r}

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ALLOWED:
        env = dict(os.environ, XDG_STATE_HOME={state_home!r})
        real = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".upstream", {name!r})
        os.execve(sys.executable, [sys.executable, real] + sys.argv[1:], env)
    sys.exit(0)
'''
    with open(path("scripts", name), "w", encoding="utf-8") as handle:
        handle.write(wrapper)
    executable(path("scripts", name))

# ── in-process services ────────────────────────────────────────────────────
# Own state directory, so nothing collides with other Quickshell configs.
edit("services/SettingsService.qml",
     '`${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/quickshell`',
     '`${Quickshell.env("HOME")}/.local/state/impasto-desktop`')

# No notification server: dynamic-glacier owns org.freedesktop.Notifications.
file = path("services", "NotificationService.qml")
with open(file, encoding="utf-8") as handle:
    text = handle.read()
start = text.find("readonly property NotificationServer server: NotificationServer {")
if start < 0:
    sys.exit("patch.py: upstream changed, NotificationServer not found")
depth, i = 0, text.index("{", start)
while True:
    if text[i] == "{":
        depth += 1
    elif text[i] == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
text = text[:start] + "readonly property QtObject server: QtObject {\n        readonly property var trackedNotifications: ({ values: [] })\n    }" + text[i + 1:]
with open(file, "w", encoding="utf-8") as handle:
    handle.write(text)

# No idle lock / screen-off / suspend.
edit("services/IdleService.qml", r"enabled: root\.(lockAfter|screenAfter|suspendAfter) > 0", "enabled: false", count=3, regex=True)

# No sleep hold / logind watch.
edit("services/SessionService.qml", "running: true", "running: false", count="all")

# No impasto dock here, so keep no band clear for one (the top band stays, so
# widgets clear the island).
edit("services/DesktopService.qml",
     """        left: DockService.edge === "left" ? DockService.zone : 0,
        right: DockService.edge === "right" ? DockService.zone : 0,
        bottom: DockService.edge === "bottom" ? DockService.zone : 0""",
     """        left: 0,
        right: 0,
        bottom: 0""")

# Album art arrives as https:// URLs (Spotify). Qt fetching those from its
# image threads crashed Quickshell inside OpenSSL's initialisation, so covers
# are downloaded with curl into a cache and shown from disk instead.
edit("services/MediaService.qml",
     "import Quickshell.Services.Mpris\n",
     "import Quickshell.Services.Mpris\nimport Quickshell.Io\n")
edit("services/MediaService.qml",
     'readonly property string artUrl: root.available ? (root.active.trackArtUrl ?? "") : ""',
     """readonly property string remoteArt: root.available ? (root.active.trackArtUrl ?? "") : ""
    property string artUrl: ""
    readonly property string artCache: Quickshell.env("HOME") + "/.cache/impasto-desktop/art"

    onRemoteArtChanged: root.fetchArt()
    Component.onCompleted: root.fetchArt()

    function fetchArt(): void {
        const url = root.remoteArt
        if (!/^https?:\\/\\//.test(url)) {
            root.artUrl = url
            return
        }
        const file = `${root.artCache}/${Qt.md5(url)}.jpg`
        root.artUrl = ""
        root.artFetch.running = false
        root.artFetch.target = file
        root.artFetch.command = ["sh", "-c",
            'mkdir -p "$1" && { [ -s "$2" ] || { curl -sfL --max-time 10 -o "$2.part" "$3" && mv "$2.part" "$2"; }; }',
            "sh", root.artCache, file, url]
        root.artFetch.running = true
    }

    readonly property Process artFetch: Process {
        property string target: ""

        onExited: code => {
            // Only the cover of the track still playing.
            if (code === 0 && root.artFetch.target === `${root.artCache}/${Qt.md5(root.remoteArt)}.jpg`)
                root.artUrl = `file://${root.artFetch.target}`
        }
    }""")

# No clipboard watcher of its own.
edit("services/ClipboardService.qml", "Component.onCompleted: root.tend()", "// impasto-desktop: cliphist already keeps the history")

print("patched")
