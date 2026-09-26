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

import "./desktop"
import "./services"

ShellRoot {
    // The palette follows the wallpaper ("adaptive"): extract-colors reads
    // whatever awww is showing. Nothing is pushed to other programs — see
    // guard/ and patch.py.
    Component.onCompleted: {
        void ThemeService.activeId
    }

    Variants {
        model: Quickshell.screens

        Desktop {
            required property var modelData

            screen: modelData
        }
    }
}
