import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Theme browser. Left: a searchable list of themes. Right: a live preview of
// the highlighted theme — a mock terminal, its full palette and the apps it
// reaches — which tweens between themes as the highlight moves, so browsing
// never touches the desktop until a theme is actually applied.
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color errorColor: "#f87171"
    readonly property color surface: "#0a0a0a"
    readonly property color surfaceRaised: "#111111"
    readonly property color hairline: "#1f1f1f"
    readonly property string monoFamily: "CaskaydiaCove Nerd Font Mono"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 36
    readonly property int bodyHeight: 292
    readonly property int footerHeight: 32
    readonly property int sectionSpacing: 12
    readonly property int listWidth: 188
    readonly property int rowHeight: 46
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.bodyHeight + root.footerHeight + root.sectionSpacing * 2
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property int tweenMs: 320

    signal closeRequested
    signal settingsRequested

    readonly property string themesPath: Quickshell.env("HOME") + "/.config/hypr/themes/themes.json"
    readonly property string currentThemePath: Quickshell.env("HOME") + "/.config/hypr/themes/current"
    readonly property string applyScriptPath: Quickshell.env("HOME") + "/.config/hypr/scripts/apply-theme.sh"

    property var themes: []
    property string currentThemeId: ""
    property string previousThemeId: ""
    property string searchText: ""
    property int highlightIndex: 0

    // idle | applying | done | error
    property string applyState: "idle"
    property string applyingId: ""
    property string applyMessage: ""
    property real applyStartedAt: 0

    property string hoveredAppText: ""
    property string copiedHex: ""
    property int openTick: 0

    readonly property var filteredThemes: root.themes.filter(theme => {
        if (root.searchText === "")
            return true;

        const needle = root.searchText.toLowerCase();
        return theme.name.toLowerCase().indexOf(needle) !== -1 || (theme.mode || "").toLowerCase().indexOf(needle) !== -1;
    })

    readonly property var shownTheme: root.filteredThemes[root.highlightIndex] || null
    readonly property bool shownIsActive: root.shownTheme !== null && root.shownTheme.id === root.currentThemeId

    // Every colour the preview draws, animated as a property so the whole
    // mock repaints as one smooth tween instead of snapping per element.
    property color pvBackground: root.pick("background", "#101010")
    property color pvDark: root.pick("darkBackground", "#080808")
    property color pvForeground: root.pick("foreground", "#d0d0d0")
    property color pvMuted: root.pick("muted", "#555555")
    property color pvAccent: root.pick("accent", "#888888")
    property color pvBorder: root.shownTheme ? (root.shownTheme.border || root.shownTheme.accent) : "#333333"
    property color pvRed: root.pickColor("red")
    property color pvGreen: root.pickColor("green")
    property color pvYellow: root.pickColor("yellow")
    property color pvBlue: root.pickColor("blue")
    property color pvMagenta: root.pickColor("magenta")
    property color pvCyan: root.pickColor("cyan")

    Behavior on pvBackground { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvDark { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvForeground { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvMuted { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvAccent { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvBorder { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvRed { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvGreen { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvYellow { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvBlue { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvMagenta { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }
    Behavior on pvCyan { ColorAnimation { duration: root.tweenMs; easing.type: Easing.OutCubic } }

    // The apps a theme reaches. `port` entries switch to that app's own
    // version of the scheme and are only lit when the theme names one.
    readonly property var appTargets: [
        { key: "hyprland", label: "Hyprland borders", icon: "desktop_windows" },
        { key: "kitty", label: "Kitty & Alacritty", icon: "terminal" },
        { key: "starship", label: "Starship prompt", icon: "rocket_launch" },
        { key: "btop", label: "btop", icon: "monitoring" },
        { key: "micro", label: "micro", icon: "edit_note" },
        { key: "gtk", label: "GTK accent", icon: "widgets" },
        { key: "satty", label: "Satty palette", icon: "draw" },
        { key: "obsidian", label: "Obsidian", icon: "diamond", port: true },
        { key: "vscode", label: "VSCodium", icon: "code", port: true },
        { key: "vim", label: "Vim & Neovim", icon: "keyboard", port: true }
    ]

    function pick(key, fallback) {
        return root.shownTheme && root.shownTheme[key] ? root.shownTheme[key] : fallback;
    }

    function pickColor(key) {
        return root.shownTheme && root.shownTheme.colors ? root.shownTheme.colors[key] : "#666666";
    }

    function themeById(id) {
        return root.themes.find(theme => theme.id === id) || null;
    }

    // The same 16-slot layout the terminals get: normals on top, brights
    // below (themes without a bright row reuse the normals).
    function paletteAt(index) {
        const theme = root.shownTheme;

        if (!theme)
            return "#000000";

        const c = theme.colors;
        const b = theme.bright || theme.colors;
        const slots = [theme.darkBackground, c.red, c.green, c.yellow, c.blue, c.magenta, c.cyan, theme.foreground, theme.muted, b.red, b.green, b.yellow, b.blue, b.magenta, b.cyan, theme.foreground];

        return slots[index];
    }

    function appDetail(target) {
        const theme = root.shownTheme;

        if (!target.port)
            return target.label + " · recoloured from the palette";

        const port = theme && theme.apps ? theme.apps[target.key] : "";

        if (!port)
            return target.label + " · left as it is";

        if (target.key === "obsidian")
            return "Obsidian · " + port + ".css snippet";

        return target.label + " · " + port;
    }

    function appLit(target) {
        if (!target.port)
            return true;

        return !!(root.shownTheme && root.shownTheme.apps && root.shownTheme.apps[target.key]);
    }

    function summaryText() {
        const theme = root.shownTheme;

        if (!theme)
            return "";

        const ports = root.appTargets.filter(target => target.port && root.appLit(target)).map(target => target.label.split(" ")[0]);
        return "Recolours 7 apps" + (ports.length ? " · switches " + ports.join(", ") : "");
    }

    function applyThemeJson(text) {
        try {
            const parsed = JSON.parse(text);

            if (Array.isArray(parsed))
                root.themes = parsed;
        } catch (error) {
            // themes.json missing or mid-edit — keep whatever was loaded last.
        }
    }

    function moveHighlight(delta) {
        if (root.filteredThemes.length === 0)
            return;

        root.highlightIndex = Math.max(0, Math.min(root.filteredThemes.length - 1, root.highlightIndex + delta));
    }

    function applyTheme(id) {
        const theme = root.themeById(id);

        if (!theme || root.applyState === "applying")
            return;

        if (id !== root.currentThemeId)
            root.previousThemeId = root.currentThemeId;

        root.applyingId = id;
        root.applyState = "applying";
        root.applyMessage = "Applying " + theme.name + "…";
        root.applyStartedAt = Date.now();
        rippleAnim.restart();

        // Stop first: a bare running = true is a no-op while a previous run
        // is still in flight.
        applyThemeProcess.running = false;
        applyThemeProcess.command = [root.applyScriptPath, id];
        applyThemeProcess.running = true;
    }

    function applyHighlighted() {
        if (root.shownTheme)
            root.applyTheme(root.shownTheme.id);
    }

    function revert() {
        if (root.previousThemeId !== "" && root.previousThemeId !== root.currentThemeId)
            root.applyTheme(root.previousThemeId);
    }

    function finishApply(exitCode) {
        const theme = root.themeById(root.applyingId);
        const name = theme ? theme.name : root.applyingId;

        if (exitCode === 0) {
            root.currentThemeId = root.applyingId;
            root.applyState = "done";
            root.applyMessage = "Applied " + name + " · " + ((Date.now() - root.applyStartedAt) / 1000).toFixed(1) + "s";
        } else {
            root.applyState = "error";
            root.applyMessage = "apply-theme.sh failed (exit " + exitCode + ")";
        }

        statusResetTimer.restart();
    }

    function copyHex(hex) {
        Quickshell.execDetached(["wl-copy", hex]);
        root.copiedHex = hex;
        copyToastAnim.restart();
    }

    function editThemes() {
        Quickshell.execDetached(["kitty", "-e", "nvim", root.themesPath]);
        root.closeRequested();
    }

    function jumpToCurrent() {
        const index = root.filteredThemes.findIndex(theme => theme.id === root.currentThemeId);

        if (index !== -1)
            root.highlightIndex = index;
    }

    onSearchTextChanged: root.highlightIndex = 0

    Process {
        id: applyThemeProcess

        onExited: (exitCode, exitStatus) => root.finishApply(exitCode)
    }

    Process {
        id: readCurrentThemeProcess

        command: ["cat", root.currentThemePath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.currentThemeId = text.trim();
                root.jumpToCurrent();
            }
        }
    }

    Timer {
        id: statusResetTimer

        interval: 2800
        onTriggered: root.applyState = "idle"
    }

    // Picks up hand edits to themes.json (the Edit button) without a restart.
    FileView {
        id: themesFile

        path: root.themesPath
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: root.applyThemeJson(themesFile.text())
        onFileChanged: themesFile.reload()
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            themeSearchInput.text = "";
            root.applyState = "idle";
            root.openTick++;
            readCurrentThemeProcess.running = false;
            readCurrentThemeProcess.running = true;
            themeSearchInput.forceActiveFocus();
            previewEnter.restart();
        }
    }

    component IconButton: Rectangle {
        id: iconButton

        required property string icon
        property bool active: true
        property string tip: ""

        signal clicked

        width: 26
        height: 26
        radius: 9
        color: buttonMouse.containsMouse && iconButton.active ? "#1a1a1a" : root.surface
        border.width: 1
        border.color: "#232323"
        opacity: iconButton.active ? 1 : 0.35
        scale: buttonMouse.pressed && iconButton.active ? 0.88 : (buttonMouse.containsMouse && iconButton.active ? 1.08 : 1)

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        MIcon {
            anchors.centerIn: parent
            name: iconButton.icon
            size: 13
            color: "#a8a8a8"
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: iconButton.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: if (iconButton.tip !== "") root.hoveredAppText = iconButton.tip
            onExited: if (iconButton.tip !== "") root.hoveredAppText = ""
            onClicked: if (iconButton.active) iconButton.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panelPadding
        spacing: root.sectionSpacing

        // ── Header ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 10

            Rectangle {
                Layout.preferredWidth: root.headerHeight
                Layout.preferredHeight: root.headerHeight
                radius: 12
                color: "#090909"
                border.width: 1
                border.color: "#232323"

                // The header badge wears the applied theme's accent ring.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -1
                    radius: 13
                    color: "transparent"
                    border.width: 1
                    border.color: root.themeById(root.currentThemeId) ? root.themeById(root.currentThemeId).accent : "transparent"
                    opacity: 0.7

                    Behavior on border.color { ColorAnimation { duration: 400 } }
                }

                MIcon {
                    anchors.centerIn: parent
                    name: "palette"
                    size: 16
                    color: root.primaryText
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: "Themes"
                    color: root.primaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const current = root.themeById(root.currentThemeId);
                        return current ? "Using " + current.name + " · " + root.themes.length + " installed" : root.themes.length + " installed";
                    }
                    color: root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 11
                }
            }

            IconButton {
                icon: "edit"
                tip: "Edit themes.json in Neovim"
                onClicked: root.editThemes()
            }

            IconButton {
                icon: "settings"
                tip: "Glacier settings"
                onClicked: root.settingsRequested()
            }

            IconButton {
                icon: "close"
                onClicked: root.closeRequested()
            }
        }

        // ── Body ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.bodyHeight
            spacing: 12

            // Left: search + theme list
            ColumnLayout {
                Layout.preferredWidth: root.listWidth
                Layout.fillHeight: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 10
                    color: root.surface
                    border.width: 1
                    border.color: themeSearchInput.activeFocus ? root.accentColor : "#232323"

                    Behavior on border.color { ColorAnimation { duration: 160 } }

                    MIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: 14
                        color: "#5f5f5f"
                    }

                    TextInput {
                        id: themeSearchInput

                        anchors.fill: parent
                        anchors.leftMargin: 32
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        color: root.primaryText
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true

                        onTextChanged: root.searchText = text

                        Keys.onUpPressed: root.moveHighlight(-1)
                        Keys.onDownPressed: root.moveHighlight(1)
                        Keys.onReturnPressed: root.applyHighlighted()
                        Keys.onEnterPressed: root.applyHighlighted()
                        Keys.onEscapePressed: {
                            if (themeSearchInput.text !== "")
                                themeSearchInput.text = "";
                            else
                                root.closeRequested();
                        }
                        Keys.onPressed: event => {
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
                                root.revert();
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
                                root.editThemes();
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: themeSearchInput.text === ""
                            text: "Search themes…"
                            color: "#5f5f5f"
                            font.family: root.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.centerIn: parent
                        visible: root.filteredThemes.length === 0
                        text: "No themes match"
                        color: root.secondaryText
                        font.family: root.fontFamily
                        font.pixelSize: 11
                    }

                    ListView {
                        id: themeList

                        anchors.fill: parent
                        spacing: 4
                        clip: true
                        model: root.filteredThemes
                        currentIndex: root.highlightIndex
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: 260
                        highlightMoveVelocity: -1

                        onCurrentIndexChanged: themeList.positionViewAtIndex(themeList.currentIndex, ListView.Contain)

                        // One highlight that glides between rows rather than
                        // each row lighting up on its own.
                        highlight: Rectangle {
                            width: themeList.width
                            height: root.rowHeight
                            radius: 12
                            color: root.surfaceRaised
                            border.width: 1
                            border.color: "#2c2c2c"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 1
                                width: 3
                                height: parent.height - 18
                                radius: 1.5
                                color: root.pvAccent
                            }
                        }

                        delegate: Item {
                            id: row

                            required property var modelData
                            required property int index

                            readonly property bool selected: index === root.highlightIndex
                            readonly property bool active: modelData.id === root.currentThemeId
                            readonly property bool applying: root.applyState === "applying" && root.applyingId === modelData.id
                            property real enter: 1

                            width: themeList.width
                            height: root.rowHeight
                            opacity: row.enter
                            transform: Translate { x: (1 - row.enter) * -14 }

                            // Rows cascade in each time the panel opens.
                            Connections {
                                target: root
                                function onOpenTickChanged() {
                                    rowEnter.restart();
                                }
                            }

                            SequentialAnimation {
                                id: rowEnter

                                PropertyAction { target: row; property: "enter"; value: 0 }
                                PauseAnimation { duration: 60 + row.index * 45 }
                                NumberAnimation { target: row; property: "enter"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                // Thumbnail: the theme's background with its
                                // six colours as vertical bars.
                                Rectangle {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 28
                                    radius: 7
                                    color: row.modelData.background
                                    border.width: 1
                                    border.color: row.modelData.border || row.modelData.accent
                                    clip: true

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Repeater {
                                            model: [row.modelData.colors.red, row.modelData.colors.yellow, row.modelData.colors.green, row.modelData.colors.cyan, row.modelData.colors.blue, row.modelData.colors.magenta]

                                            Rectangle {
                                                required property string modelData
                                                required property int index

                                                width: 4
                                                height: row.selected ? 16 : 12
                                                radius: 2
                                                color: modelData
                                                anchors.verticalCenter: parent.verticalCenter

                                                Behavior on height { NumberAnimation { duration: 220 + index * 30; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        color: row.selected ? root.primaryText : "#c4c4c4"
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.Bold

                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (row.modelData.mode === "light" ? "Light" : "Dark") + (row.modelData.bright ? " · 16 colours" : " · 8 colours")
                                        color: root.secondaryText
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                    }
                                }

                                // Applied / applying marker
                                Item {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16

                                    MIcon {
                                        anchors.centerIn: parent
                                        name: "progress_activity"
                                        size: 14
                                        color: root.accentColor
                                        visible: row.applying

                                        RotationAnimation on rotation {
                                            running: row.applying
                                            from: 0
                                            to: 360
                                            duration: 800
                                            loops: Animation.Infinite
                                        }
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: root.accentColor
                                        visible: !row.applying
                                        scale: row.active ? 1 : 0

                                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Hovering previews; a click applies.
                                onEntered: root.highlightIndex = row.index
                                onClicked: {
                                    root.highlightIndex = row.index;
                                    root.applyHighlighted();
                                }
                            }
                        }
                    }
                }
            }

            // Right: live preview
            ColumnLayout {
                id: previewColumn

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                SequentialAnimation {
                    id: previewEnter

                    ParallelAnimation {
                        NumberAnimation { target: previewColumn; property: "opacity"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
                        NumberAnimation { target: mockWindow; property: "scale"; from: 0.94; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                    }
                }

                // Mock terminal in the previewed theme
                Rectangle {
                    id: mockWindow

                    Layout.fillWidth: true
                    Layout.preferredHeight: 146
                    radius: 12
                    color: root.pvBackground
                    border.width: 2
                    border.color: root.pvBorder
                    clip: true

                    // Apply ripple, spreading from the top-left in the
                    // theme's accent.
                    Rectangle {
                        id: ripple

                        x: -width / 2 + 20
                        y: -height / 2 + 14
                        width: 0
                        height: width
                        radius: width / 2
                        color: root.pvAccent
                        opacity: 0
                    }

                    ParallelAnimation {
                        id: rippleAnim

                        NumberAnimation { target: ripple; property: "width"; from: 0; to: mockWindow.width * 2.6; duration: 700; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ripple; property: "opacity"; from: 0.35; to: 0; duration: 700; easing.type: Easing.OutQuad }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Title bar
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Repeater {
                                model: 3

                                Rectangle {
                                    required property int index

                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: index === 0 ? root.pvRed : (index === 1 ? root.pvYellow : root.pvGreen)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                text: "kitty — ~/github"
                                color: root.pvMuted
                                elide: Text.ElideRight
                                font.family: root.monoFamily
                                font.pixelSize: 9
                            }
                        }

                        // Prompt chips, the way Starship draws them
                        Row {
                            spacing: -4

                            Repeater {
                                model: [
                                    { text: "󰣇 bator", key: "accent" },
                                    { text: "…/github", key: "yellow" },
                                    { text: " main", key: "cyan" },
                                    { text: " 22:41", key: "surface" }
                                ]

                                Rectangle {
                                    required property var modelData
                                    required property int index

                                    height: 16
                                    width: chipLabel.implicitWidth + 16
                                    radius: 8
                                    z: 10 - index
                                    color: modelData.key === "accent" ? root.pvAccent : (modelData.key === "yellow" ? root.pvYellow : (modelData.key === "cyan" ? root.pvCyan : Qt.lighter(root.pvBackground, 1.6)))

                                    Text {
                                        id: chipLabel

                                        anchors.centerIn: parent
                                        text: parent.modelData.text
                                        color: parent.modelData.key === "surface" ? root.pvForeground : root.pvDark
                                        font.family: root.monoFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }

                        // A few lines of highlighted code
                        Column {
                            Layout.fillWidth: true
                            spacing: 2

                            Row {
                                Text { text: "fn "; color: root.pvMagenta; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: "apply"; color: root.pvBlue; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: "(theme: "; color: root.pvForeground; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: "&str"; color: root.pvYellow; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: ") {"; color: root.pvForeground; font.family: root.monoFamily; font.pixelSize: 10 }
                            }

                            Row {
                                Text { text: "    let "; color: root.pvMagenta; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: "accent"; color: root.pvForeground; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: " = "; color: root.pvForeground; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: "\"" + (root.shownTheme ? root.shownTheme.accent : "") + "\""; color: root.pvGreen; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: ";"; color: root.pvForeground; font.family: root.monoFamily; font.pixelSize: 10 }
                            }

                            Row {
                                Text { text: "    // repaints the whole desktop"; color: root.pvMuted; font.family: root.monoFamily; font.pixelSize: 10; font.italic: true }
                            }

                            Row {
                                Text { text: "    error"; color: root.pvRed; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: "!(" ; color: root.pvForeground; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: "404"; color: root.pvCyan; font.family: root.monoFamily; font.pixelSize: 10 }
                                Text { text: ")"; color: root.pvForeground; font.family: root.monoFamily; font.pixelSize: 10 }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // btop-style meters in the corner
                    Column {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        spacing: 3

                        Repeater {
                            model: [0.82, 0.55, 0.3]

                            Rectangle {
                                required property real modelData
                                required property int index

                                width: 54
                                height: 4
                                radius: 2
                                color: Qt.lighter(root.pvBackground, 1.8)

                                Rectangle {
                                    width: parent.width * parent.modelData
                                    height: parent.height
                                    radius: 2
                                    color: parent.index === 0 ? root.pvRed : (parent.index === 1 ? root.pvYellow : root.pvGreen)
                                }
                            }
                        }
                    }

                    // "Copied" toast
                    Rectangle {
                        id: copyToast

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height
                        width: toastLabel.implicitWidth + 20
                        height: 22
                        radius: 11
                        color: "#e0000000"
                        border.width: 1
                        border.color: "#333333"

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: root.copiedHex || "transparent"
                            }

                            Text {
                                id: toastLabel

                                text: "Copied " + root.copiedHex
                                color: root.primaryText
                                font.family: root.monoFamily
                                font.pixelSize: 10
                            }
                        }
                    }

                    SequentialAnimation {
                        id: copyToastAnim

                        NumberAnimation { target: copyToast; property: "y"; to: mockWindow.height - 30; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        PauseAnimation { duration: 1100 }
                        NumberAnimation { target: copyToast; property: "y"; to: mockWindow.height; duration: 200; easing.type: Easing.InCubic }
                    }
                }

                // Key colours
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "ACCENT", key: "accent" },
                            { label: "BORDER", key: "border" },
                            { label: "SURFACE", key: "background" }
                        ]

                        Rectangle {
                            id: keySwatch

                            required property var modelData

                            readonly property string hex: root.shownTheme ? (modelData.key === "border" ? (root.shownTheme.border || root.shownTheme.accent) : root.shownTheme[modelData.key]) : "#000000"

                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 8
                            color: root.surface
                            border.width: 1
                            border.color: keyMouse.containsMouse ? "#333333" : root.hairline
                            scale: keyMouse.pressed ? 0.94 : 1

                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Rectangle {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    radius: 5
                                    color: keySwatch.modelData.key === "accent" ? root.pvAccent : (keySwatch.modelData.key === "border" ? root.pvBorder : root.pvBackground)
                                    border.width: 1
                                    border.color: "#2a2a2a"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -1

                                    Text {
                                        text: keySwatch.modelData.label
                                        color: root.faintText
                                        font.family: root.fontFamily
                                        font.pixelSize: 7
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: keySwatch.hex
                                        color: "#bdbdbd"
                                        elide: Text.ElideRight
                                        font.family: root.monoFamily
                                        font.pixelSize: 9
                                    }
                                }
                            }

                            MouseArea {
                                id: keyMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.copyHex(keySwatch.hex)
                            }
                        }
                    }
                }

                // Full 16-colour palette, click to copy
                Grid {
                    id: paletteGrid

                    Layout.fillWidth: true
                    columns: 8
                    spacing: 4

                    readonly property real cell: (width - spacing * 7) / 8

                    Repeater {
                        model: 16

                        Rectangle {
                            id: swatch

                            required property int index

                            readonly property string hex: root.paletteAt(index)

                            width: paletteGrid.cell
                            height: 16
                            radius: 5
                            color: hex
                            border.width: 1
                            border.color: swatchMouse.containsMouse ? "#f0f0f0" : "#262626"
                            scale: swatchMouse.pressed ? 0.85 : (swatchMouse.containsMouse ? 1.1 : 1)
                            z: swatchMouse.containsMouse ? 2 : 1

                            Behavior on color { ColorAnimation { duration: root.tweenMs + swatch.index * 12; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

                            MouseArea {
                                id: swatchMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.hoveredAppText = (swatch.index < 8 ? "Normal " : "Bright ") + ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"][swatch.index % 8] + " · " + swatch.hex + " · click to copy"
                                onExited: root.hoveredAppText = ""
                                onClicked: root.copyHex(swatch.hex)
                            }
                        }
                    }
                }

                // Where the theme reaches
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: root.appTargets

                        Rectangle {
                            id: appChip

                            required property var modelData

                            readonly property bool lit: root.appLit(modelData)

                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            radius: 7
                            color: chipMouse.containsMouse ? root.surfaceRaised : root.surface
                            border.width: 1
                            border.color: appChip.lit ? (appChip.modelData.port ? Qt.darker(root.pvAccent, 1.6) : "#262626") : root.hairline
                            opacity: appChip.lit ? 1 : 0.35

                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: root.tweenMs } }

                            MIcon {
                                anchors.centerIn: parent
                                name: appChip.modelData.icon
                                size: 12
                                color: appChip.lit ? (appChip.modelData.port ? root.pvAccent : "#bdbdbd") : "#555555"
                            }

                            MouseArea {
                                id: chipMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.hoveredAppText = root.appDetail(appChip.modelData)
                                onExited: root.hoveredAppText = ""
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hoveredAppText !== "" ? root.hoveredAppText : root.summaryText()
                    color: root.hoveredAppText !== "" ? "#c4c4c4" : root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10

                    Behavior on color { ColorAnimation { duration: 140 } }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ── Footer ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.footerHeight
            spacing: 8

            // Status: hint → spinner → check / error
            Item {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16

                MIcon {
                    id: statusIcon

                    anchors.centerIn: parent
                    name: root.applyState === "applying" ? "progress_activity" : (root.applyState === "done" ? "check_circle" : (root.applyState === "error" ? "error" : "keyboard"))
                    size: 15
                    color: root.applyState === "error" ? root.errorColor : (root.applyState === "idle" ? "#555555" : root.accentColor)

                    RotationAnimation on rotation {
                        running: root.applyState === "applying"
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) statusIcon.rotation = 0
                    }
                }

                Connections {
                    target: root
                    function onApplyStateChanged() {
                        if (root.applyState === "done" || root.applyState === "error")
                            statusPop.restart();
                    }
                }

                SequentialAnimation {
                    id: statusPop

                    NumberAnimation { target: statusIcon; property: "scale"; from: 0.4; to: 1.25; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: statusIcon; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.applyState === "idle" ? "↑↓ preview · Enter apply · Ctrl+Z revert · Ctrl+E edit" : root.applyMessage
                color: root.applyState === "error" ? root.errorColor : (root.applyState === "idle" ? root.faintText : "#d6d6d6")
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: root.applyState === "idle" ? Font.Normal : Font.DemiBold
            }

            // Revert
            Rectangle {
                readonly property bool usable: root.previousThemeId !== "" && root.previousThemeId !== root.currentThemeId && root.applyState !== "applying"

                Layout.preferredWidth: revertRow.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: 9
                color: revertMouse.containsMouse && parent.usable ? "#1a1a1a" : root.surface
                border.width: 1
                border.color: "#262626"
                opacity: usable ? 1 : 0.35
                visible: root.previousThemeId !== ""
                scale: revertMouse.pressed && usable ? 0.94 : 1

                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                Row {
                    id: revertRow

                    anchors.centerIn: parent
                    spacing: 5

                    MIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "undo"
                        size: 12
                        color: "#bdbdbd"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.themeById(root.previousThemeId) ? root.themeById(root.previousThemeId).name : "Revert"
                        color: "#bdbdbd"
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: revertMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.revert()
                }
            }

            // Apply
            Rectangle {
                id: applyButton

                readonly property bool usable: root.shownTheme !== null && !root.shownIsActive && root.applyState !== "applying"

                Layout.preferredWidth: 92
                Layout.preferredHeight: 28
                radius: 9
                color: applyButton.usable ? (applyMouse.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor) : root.surface
                border.width: 1
                border.color: applyButton.usable ? root.accentColor : "#262626"
                scale: applyMouse.pressed && applyButton.usable ? 0.93 : 1

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    MIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.shownIsActive ? "check" : "format_paint"
                        size: 12
                        color: applyButton.usable ? "#04140a" : "#8a8a8a"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.applyState === "applying" ? "Applying" : (root.shownIsActive ? "Active" : "Apply")
                        color: applyButton.usable ? "#04140a" : "#8a8a8a"
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    id: applyMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: applyButton.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (applyButton.usable) root.applyHighlighted()
                }
            }
        }
    }
}
