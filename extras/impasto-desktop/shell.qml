// impasto-desktop · only impasto's desktop widgets, next to dynamic-glacier.
//
// The widgets come from github.com/andreumassanet/impasto (GPL-3.0); this
// entry point replaces impasto's own shell.qml, which also starts its bar,
// island, dock, lock screen, notification server and the rest. Here there
// is nothing but the widget layer under the windows, one per screen.
//
// Right-click the wallpaper to arrange: add widgets from the card, drag to
// move, pull a corner to resize, click one for its look. Escape ends it.

import QtQuick
import Quickshell
import Quickshell.Io

import "./desktop"
import "./services"

ShellRoot {
    id: root

    // The palette follows the wallpaper ("adaptive"): extract-colors reads
    // whatever awww is showing. Nothing is pushed to other programs — see
    // guard/ and patch.py.
    Component.onCompleted: {
        void ThemeService.activeId
        // impasto starts from the colours it cached last time, which belong
        // to whatever wallpaper was up then; read the current one again.
        startupRefresh.start()
    }

    Timer {
        id: startupRefresh

        interval: 2500
        onTriggered: ThemeService.reloadAdaptiveColors()
    }

    // ── Following wallpaper changes ─────────────────────────────────────────
    //
    // impasto only re-reads the palette when its own picker sets a wallpaper;
    // here dynamic-glacier sets them. awww keeps one small file per output
    // naming the image on it (~/.cache/awww/<version>/<output>), rewritten
    // on every change, so that file is watched — and re-read every few
    // seconds too, in case a rewrite by rename slips past the watch.
    property string awwwCacheDir: ""
    property string lastWallpaper: ""

    Process {
        running: true
        command: ["sh", "-c", "ls -d \"$HOME\"/.cache/awww/*/ 2>/dev/null | tail -n 1"]
        stdout: StdioCollector {
            onStreamFinished: root.awwwCacheDir = text.trim()
        }
    }

    FileView {
        id: wallpaperRecord

        path: root.awwwCacheDir !== "" && Quickshell.screens.length > 0
            ? root.awwwCacheDir + Quickshell.screens[0].name : ""
        watchChanges: true
        printErrors: false
        onFileChanged: wallpaperRecord.reload()
        onLoaded: {
            const text = wallpaperRecord.text()
            if (root.lastWallpaper !== "" && text !== root.lastWallpaper)
                refresh.restart()
            root.lastWallpaper = text
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: wallpaperRecord.path !== ""
        onTriggered: wallpaperRecord.reload()
    }

    // awww's grow/wipe transition takes most of a second; the palette follows
    // once the new image is the one on screen.
    Timer {
        id: refresh

        interval: 900
        onTriggered: ThemeService.reloadAdaptiveColors()
    }

    Variants {
        model: Quickshell.screens

        Desktop {
            required property var modelData

            screen: modelData
        }
    }
}
