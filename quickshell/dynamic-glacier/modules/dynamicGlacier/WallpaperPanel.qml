import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Wallpaper picker for ~/Pictures/Wallpapers (folders one level deep).
//
//   - sidebar: All · Favourites · Recent · every folder, with counts
//   - search across everything as you type
//   - thumbnails from a cache (wall-thumbs.sh), so 1000+ images scroll fast
//   - Enter sets it (awww), with your pick of transition; Ctrl+Z goes back
//   - favourites, random, and a slideshow that keeps running when closed
//
// State: ~/.local/share/dynamic-glacier/wallpaper.json
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color favColor: "#f472b6"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int toolbarHeight: 32
    readonly property int bodyHeight: 372
    readonly property int footerHeight: 26
    readonly property int sectionSpacing: 10
    readonly property int sidebarWidth: 160
    readonly property int columns: 4

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.toolbarHeight + root.bodyHeight + root.footerHeight + root.sectionSpacing * 3
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property string home: Quickshell.env("HOME")
    readonly property string wallDir: root.home + "/Pictures/Wallpapers"
    readonly property string thumbDir: root.home + "/.cache/dynamic-glacier/wall-thumbs"
    readonly property string statePath: root.home + "/.local/share/dynamic-glacier/wallpaper.json"
    readonly property string thumbScript: root.home + "/.config/hypr/scripts/wall-thumbs.sh"

    // ── Library ───────────────────────────────────────────────────────────
    property var files: [] // { path, folder, file, name, key }
    property var folders: [] // { name, count }
    property bool scanned: false

    // ── State ─────────────────────────────────────────────────────────────
    property string current: ""
    property var history: [] // newest first, includes current
    property var favourites: []
    property string transition: "grow"
    property int slideshowMinutes: 0
    property string slideshowSource: "all"
    property bool loaded: false

    // ── View ──────────────────────────────────────────────────────────────
    property string source: "all" // all | fav | recent | folder:<name>
    property string query: ""
    property int cursor: 0
    property bool applying: false
    property string applyingPath: ""
    property string toast: ""
    property string thumbProgress: ""

    readonly property var transitionStyles: [
        { id: "grow", label: "Grow" },
        { id: "wipe", label: "Wipe" },
        { id: "wave", label: "Wave" },
        { id: "fade", label: "Fade" },
        { id: "outer", label: "Outer" }
    ]
    readonly property var slideshowOptions: [0, 15, 30, 60, 180]

    // ── Helpers ───────────────────────────────────────────────────────────
    function pretty(file) {
        const base = file.replace(/\.[^.]+$/, "").replace(/[_\-]+/g, " ").replace(/\s+/g, " ").trim();
        return base.charAt(0).toUpperCase() + base.slice(1);
    }

    function fold(text) {
        const map = { "á": "a", "é": "e", "í": "i", "ó": "o", "ö": "o", "ő": "o", "ú": "u", "ü": "u", "ű": "u" };
        return String(text).toLowerCase().replace(/[áéíóöőúüű]/g, c => map[c]);
    }

    function thumbFor(path) {
        return root.thumbDir + "/" + Qt.md5(path) + ".jpg";
    }

    function isFav(path) {
        return root.favourites.indexOf(path) !== -1;
    }

    function fileFor(path) {
        return root.files.find(f => f.path === path) || null;
    }

    function sourceLabel(id) {
        if (id === "all")
            return "All";
        if (id === "fav")
            return "Favourites";
        if (id === "recent")
            return "Recent";
        const name = id.slice(7);
        return name === "" ? "Unsorted" : root.pretty(name);
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    function listFor(sourceId) {
        if (sourceId === "fav")
            return root.favourites.map(root.fileFor).filter(f => f !== null);
        if (sourceId === "recent")
            return root.history.map(root.fileFor).filter(f => f !== null);
        if (sourceId.startsWith("folder:")) {
            const name = sourceId.slice(7);
            return root.files.filter(f => f.folder === name);
        }
        return root.files;
    }

    // What the grid shows: the source, narrowed by the search (every word
    // must match the name or folder). Searching looks through everything.
    readonly property var visibleFiles: {
        const terms = root.fold(root.query).split(/\s+/).filter(t => t !== "");
        const base = terms.length > 0 && root.source !== "fav" && root.source !== "recent" ? root.files : root.listFor(root.source);
        if (terms.length === 0)
            return base;
        return base.filter(f => terms.every(t => f.key.indexOf(t) !== -1));
    }

    readonly property var sources: {
        const list = [
            { id: "all", label: "All", icon: "photo_library", count: root.files.length },
            { id: "fav", label: "Favourites", icon: "favorite", count: root.favourites.filter(p => root.fileFor(p) !== null).length },
            { id: "recent", label: "Recent", icon: "history", count: root.history.filter(p => root.fileFor(p) !== null).length }
        ];
        for (const folder of root.folders)
            list.push({ id: "folder:" + folder.name, label: folder.name === "" ? "Unsorted" : root.pretty(folder.name), icon: "folder", count: folder.count, folder: folder.name });
        return list;
    }

    readonly property int sourceIndex: root.sources.findIndex(s => s.id === root.source)
    readonly property var currentFile: root.fileFor(root.current)

    // ── Scanning ──────────────────────────────────────────────────────────
    function scan() {
        if (!scanProc.running)
            scanProc.running = true;
        if (!thumbProc.running)
            thumbProc.running = true;
    }

    function parseScan(text) {
        const files = [];
        const counts = {};
        for (const line of text.split("\n")) {
            if (line === "")
                continue;
            const slash = line.indexOf("/");
            const folder = slash === -1 ? "" : line.slice(0, slash);
            const file = slash === -1 ? line : line.slice(slash + 1);
            const name = root.pretty(file);
            files.push({ path: root.wallDir + "/" + line, folder: folder, file: file, name: name, key: root.fold(folder + " " + name + " " + file) });
            counts[folder] = (counts[folder] || 0) + 1;
        }
        files.sort((a, b) => a.folder === b.folder ? a.name.localeCompare(b.name) : a.folder.localeCompare(b.folder));
        root.files = files;
        root.folders = Object.keys(counts).sort((a, b) => (a === "") - (b === "") || a.localeCompare(b)).map(name => ({ name: name, count: counts[name] }));
        root.scanned = true;
        if (root.source.startsWith("folder:") && counts[root.source.slice(7)] === undefined)
            root.source = "all";
        root.revealCurrent();
    }

    // ── Navigation ────────────────────────────────────────────────────────
    function setCursor(index) {
        const count = root.visibleFiles.length;
        root.cursor = count === 0 ? 0 : Math.max(0, Math.min(count - 1, index));
        Qt.callLater(() => grid.currentIndex = root.visibleFiles.length > 0 ? root.cursor : -1);
    }

    function move(dx, dy) {
        const count = root.visibleFiles.length;
        if (count === 0)
            return;
        let next = root.cursor + dx + dy * root.columns;
        if (dy !== 0 && (next < 0 || next >= count))
            next = dy < 0 ? root.cursor % root.columns : Math.min(count - 1, root.cursor);
        root.setCursor(next);
    }

    function selectSource(id) {
        if (id === root.source)
            return;
        root.source = id;
        root.query = "";
        search.text = "";
        grid.currentIndex = -1;
        swap.restart();
        root.setCursor(0);
        if (id.startsWith("folder:") || id === "all")
            Qt.callLater(root.revealCurrent);
    }

    function cycleSource(delta) {
        const count = root.sources.length;
        root.selectSource(root.sources[(root.sourceIndex + delta + count) % count].id);
        sidebar.positionViewAtIndex(root.sourceIndex, ListView.Contain);
    }

    // Opening on "All" or a folder puts the cursor on the wallpaper in use.
    function revealCurrent() {
        const index = root.visibleFiles.findIndex(f => f.path === root.current);
        root.setCursor(index >= 0 ? index : 0);
        // Jump (not glide) there, centred, once the grid has its rows.
        Qt.callLater(() => {
            if (root.visibleFiles.length > 0)
                grid.positionViewAtIndex(root.cursor, GridView.Center);
        });
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function apply(path, silent) {
        if (!path || root.applying)
            return;
        root.applying = true;
        root.applyingPath = path;
        applyProc.command = ["awww", "img", path, "--resize", "crop", "--transition-type", root.transition, "--transition-duration", "0.8", "--transition-fps", "60", "--transition-pos", "center"];
        applyProc.silent = silent === true;
        applyProc.running = true;
    }

    function applied(success) {
        const path = root.applyingPath;
        root.applying = false;
        root.applyingPath = "";
        if (!success) {
            root.showToast("Couldn't set it — is awww-daemon running?");
            return;
        }
        root.current = path;
        root.history = [path].concat(root.history.filter(p => p !== path)).slice(0, 30);
        if (!applyProc.silent)
            root.showToast("Set  ·  " + (root.fileFor(path) ? root.fileFor(path).name : path.split("/").pop()));
        root.save();
    }

    function applyCursor() {
        const file = root.visibleFiles[root.cursor];
        if (file)
            root.apply(file.path);
    }

    function undo() {
        const previous = root.history.find(p => p !== root.current && root.fileFor(p) !== null);
        if (!previous) {
            root.showToast("No earlier wallpaper");
            return;
        }
        root.apply(previous);
    }

    function random(sourceId, silent) {
        const pool = root.listFor(sourceId || root.source).filter(f => f.path !== root.current);
        if (pool.length === 0)
            return;
        const pick = pool[Math.floor(Math.random() * pool.length)];
        root.apply(pick.path, silent);
        if (!silent) {
            const index = root.visibleFiles.findIndex(f => f.path === pick.path);
            if (index >= 0)
                root.setCursor(index);
        }
    }

    function toggleFav(path) {
        if (!path)
            return;
        if (root.isFav(path)) {
            root.favourites = root.favourites.filter(p => p !== path);
            root.showToast("Removed from favourites");
        } else {
            root.favourites = [path].concat(root.favourites);
            root.showToast("Added to favourites");
        }
        root.save();
    }

    function setSlideshow(minutes) {
        root.slideshowMinutes = minutes;
        if (minutes > 0) {
            root.slideshowSource = root.source;
            root.showToast("Slideshow: " + root.sourceLabel(root.source) + " every " + (minutes >= 60 ? minutes / 60 + " h" : minutes + " min"));
        } else {
            root.showToast("Slideshow off");
        }
        root.save();
    }

    function openInViewer(path) {
        if (path)
            Quickshell.execDetached(["xdg-open", path]);
    }

    function showInFiles(path) {
        if (path)
            Quickshell.execDetached(["dolphin", "--select", path]);
    }

    // ── Persistence ───────────────────────────────────────────────────────
    function save() {
        if (root.loaded)
            saveTimer.restart();
    }

    function applyState(text) {
        try {
            const data = JSON.parse(text);
            if (typeof data.path === "string")
                root.current = data.path; // old format
            if (typeof data.current === "string")
                root.current = data.current;
            if (Array.isArray(data.history))
                root.history = data.history.filter(p => typeof p === "string");
            if (Array.isArray(data.favourites))
                root.favourites = data.favourites.filter(p => typeof p === "string");
            if (typeof data.transition === "string")
                root.transition = data.transition;
            if (typeof data.slideshowMinutes === "number")
                root.slideshowMinutes = data.slideshowMinutes;
            if (typeof data.slideshowSource === "string")
                root.slideshowSource = data.slideshowSource;
        } catch (error) {
            // Missing or broken: defaults.
        }
        if (root.current !== "" && root.history.indexOf(root.current) === -1)
            root.history = [root.current].concat(root.history);
        root.loaded = true;
    }

    FileView {
        id: stateFile

        path: root.statePath
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyState(stateFile.text())
        onLoadFailed: legacyState.reload()
    }

    FileView {
        id: legacyState

        path: Quickshell.statePath("wallpaper.json")
        printErrors: false
        onLoaded: {
            root.applyState(legacyState.text());
            root.save();
        }
        onLoadFailed: root.applyState("{}")
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: stateFile.setText(JSON.stringify({
            current: root.current,
            history: root.history,
            favourites: root.favourites,
            transition: root.transition,
            slideshowMinutes: root.slideshowMinutes,
            slideshowSource: root.slideshowSource
        }, null, 2) + "\n")
    }

    Process {
        id: scanProc

        command: ["find", root.wallDir, "-mindepth", "1", "-maxdepth", "2", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", "-o", "-iname", "*.bmp", ")", "-printf", "%P\\n"]
        stdout: StdioCollector {
            onStreamFinished: root.parseScan(text)
        }
    }

    Process {
        id: thumbProc

        command: [root.thumbScript, root.wallDir, root.thumbDir]
        stdout: SplitParser {
            onRead: line => {
                const match = /^(\d+)\/(\d+)$/.exec(line.trim());
                if (match)
                    root.thumbProgress = match[1] === match[2] ? "" : "Preparing previews  " + match[1] + " / " + match[2];
            }
        }
        onExited: {
            root.thumbProgress = "";
            thumbEpoch.bump();
        }
    }

    // Tiles whose thumbnail didn't exist yet retry once the cache is built.
    QtObject {
        id: thumbEpoch

        property int value: 0

        function bump() {
            thumbEpoch.value += 1;
        }
    }

    Process {
        id: applyProc

        property bool silent: false

        onExited: exitCode => root.applied(exitCode === 0)
    }

    // Slideshow: keeps going while the panel is closed.
    Timer {
        interval: Math.max(1, root.slideshowMinutes) * 60000
        repeat: true
        running: root.slideshowMinutes > 0 && root.loaded
        onTriggered: {
            if (!root.scanned) {
                root.scan();
                return;
            }
            root.random(root.slideshowSource, true);
        }
    }

    Timer {
        id: toastTimer

        interval: 2400
        onTriggered: root.toast = ""
    }

    // Library scan at startup too, so the slideshow has something to pick.
    Component.onCompleted: Qt.callLater(() => scanProc.running = true)

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    // Keyboard focus goes to the text field once the island has finished
    // opening. Taken mid-morph, Hyprland held back the surface's frame
    // callbacks for ~300 ms and the opening animation froze halfway.
    Timer {
        id: focusAfterOpen

        interval: 360
        onTriggered: {
            if (!root.visible)
                return;
            search.forceActiveFocus();
            if (root.typedEarly !== "") {
                search.insert(search.cursorPosition, root.typedEarly);
                root.typedEarly = "";
                search.textEdited();
            }
        }
    }

    // Until then the panel itself holds the keyboard: what's typed in the
    // first moments is kept and handed to the field, and Esc still closes.
    property string typedEarly: ""

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            root.typedEarly += event.text;
            event.accepted = true;
        }
    }

    onVisibleChanged: {
        if (root.visible) {
            root.query = "";
            search.text = "";
            root.scan();
            root.revealCurrent();
            root.typedEarly = "";
            root.forceActiveFocus();
            focusAfterOpen.restart();
        }
    }

    onVisibleFilesChanged: {
        if (root.cursor >= root.visibleFiles.length)
            root.setCursor(root.visibleFiles.length - 1);
        else
            Qt.callLater(() => grid.currentIndex = root.visibleFiles.length > 0 ? root.cursor : -1);
    }

    // ── Components ────────────────────────────────────────────────────────

    component IconButton: Rectangle {
        id: iconButton

        required property string icon
        property bool active: false
        property color tint: "#a8a8a8"

        signal clicked

        width: 26
        height: 26
        radius: 9
        color: iconButton.active ? "#1f2a22" : (iconHover.hovered ? "#1a1a1a" : "#0a0a0a")
        border.width: 1
        border.color: iconButton.active ? "#2f4f3a" : "#232323"
        scale: iconMouse.pressed ? 0.88 : (iconHover.hovered ? 1.08 : 1)

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
        Behavior on color { ColorAnimation { duration: 140 } }

        HoverHandler {
            id: iconHover

            cursorShape: Qt.PointingHandCursor
        }

        MIcon {
            anchors.centerIn: parent
            name: iconButton.icon
            size: 14
            color: iconButton.active ? root.accentColor : iconButton.tint
        }

        MouseArea {
            id: iconMouse

            anchors.fill: parent
            onClicked: iconButton.clicked()
        }
    }

    component Chip: Rectangle {
        id: chip

        required property string text
        property bool active: false

        signal clicked

        implicitWidth: chipText.implicitWidth + 16
        implicitHeight: 22
        radius: 7
        color: chip.active ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : (chipHover.hovered ? "#171717" : "#0d0d0d")
        border.width: 1
        border.color: chip.active ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5) : "#1c1c1c"
        scale: chipMouse.pressed ? 0.92 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }

        HoverHandler {
            id: chipHover

            cursorShape: Qt.PointingHandCursor
        }

        Text {
            id: chipText

            anchors.centerIn: parent
            text: chip.text
            color: chip.active ? root.accentColor : (chipHover.hovered ? root.primaryText : "#8a8a8a")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            onClicked: chip.clicked()
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panelPadding
        spacing: root.sectionSpacing

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 10

            // The wallpaper in use, as the header tile.
            Item {
                Layout.preferredWidth: 54
                Layout.preferredHeight: root.headerHeight

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 9
                    color: "transparent"

                    Image {
                        id: currentThumb

                        anchors.fill: parent
                        source: root.current !== "" ? root.thumbFor(root.current) : ""
                        sourceSize.width: 108
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: currentThumb.status === Image.Ready ? "transparent" : "#0a0a0a"
                    border.width: 1
                    border.color: "#2a2a2a"

                    MIcon {
                        anchors.centerIn: parent
                        visible: currentThumb.status !== Image.Ready
                        name: "wallpaper"
                        size: 16
                        color: root.primaryText
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "Wallpapers"
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: root.currentFile ? root.currentFile.name + (root.currentFile.folder !== "" ? "  ·  " + root.pretty(root.currentFile.folder) : "") : (root.scanned ? root.files.length + " wallpapers" : "Scanning…")
                    color: root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            IconButton {
                icon: "shuffle"
                onClicked: root.random()
            }

            IconButton {
                icon: "undo"
                onClicked: root.undo()
            }

            IconButton {
                icon: root.isFav(root.current) ? "favorite" : "favorite_border"
                tint: root.isFav(root.current) ? root.favColor : "#a8a8a8"
                onClicked: root.toggleFav(root.current)
            }

            IconButton {
                icon: "folder_open"
                onClicked: root.showInFiles(root.current !== "" ? root.current : root.wallDir)
            }

            IconButton {
                icon: "close"
                onClicked: root.closeRequested()
            }
        }

        // Search + transition
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.toolbarHeight
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: "#0a0a0a"
                border.width: 1
                border.color: search.activeFocus && search.text !== "" ? "#2f4f3a" : "#1f1f1f"

                MIcon {
                    id: searchIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 15
                    color: search.text !== "" ? root.accentColor : "#555555"
                }

                TextInput {
                    id: search

                    anchors.left: searchIcon.right
                    anchors.right: resultCount.left
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.primaryText
                    selectionColor: "#2f4f3a"
                    clip: true
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    onTextEdited: {
                        root.query = text;
                        root.setCursor(0);
                    }

                    // The grid owns the arrow keys; the box just takes text.
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        const key = event.key;
                        if (key === Qt.Key_Left)
                            root.move(-1, 0);
                        else if (key === Qt.Key_Right)
                            root.move(1, 0);
                        else if (key === Qt.Key_Up)
                            root.move(0, -1);
                        else if (key === Qt.Key_Down)
                            root.move(0, 1);
                        else if (key === Qt.Key_PageUp)
                            root.move(0, -3);
                        else if (key === Qt.Key_PageDown)
                            root.move(0, 3);
                        else if (key === Qt.Key_Home && ctrl)
                            root.setCursor(0);
                        else if (key === Qt.Key_End && ctrl)
                            root.setCursor(root.visibleFiles.length - 1);
                        else if (key === Qt.Key_Tab)
                            root.cycleSource(1);
                        else if (key === Qt.Key_Backtab)
                            root.cycleSource(-1);
                        else if (key === Qt.Key_Return || key === Qt.Key_Enter)
                            root.applyCursor();
                        else if (ctrl && key === Qt.Key_S)
                            root.toggleFav(root.visibleFiles[root.cursor] ? root.visibleFiles[root.cursor].path : "");
                        else if (ctrl && key === Qt.Key_R)
                            root.random();
                        else if (ctrl && key === Qt.Key_Z)
                            root.undo();
                        else if (ctrl && key === Qt.Key_O)
                            root.openInViewer(root.visibleFiles[root.cursor] ? root.visibleFiles[root.cursor].path : "");
                        else if (ctrl && key === Qt.Key_E)
                            root.showInFiles(root.visibleFiles[root.cursor] ? root.visibleFiles[root.cursor].path : "");
                        else if (key === Qt.Key_Escape) {
                            if (search.text !== "") {
                                search.text = "";
                                root.query = "";
                                root.revealCurrent();
                            } else {
                                root.closeRequested();
                            }
                        } else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        text: "Search " + root.files.length + " wallpapers…"
                        color: "#555555"
                        font: search.font
                    }
                }

                Text {
                    id: resultCount

                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.visibleFiles.length > 0 ? (root.cursor + 1) + " / " + root.visibleFiles.length : "0"
                    color: root.faintText
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
            }

            Text {
                text: "TRANSITION"
                color: root.faintText
                font.family: root.fontFamily
                font.pixelSize: 8
                font.weight: Font.Black
                font.letterSpacing: 1.2
            }

            Row {
                spacing: 4

                Repeater {
                    model: root.transitionStyles

                    Chip {
                        required property var modelData

                        text: modelData.label
                        active: root.transition === modelData.id
                        onClicked: {
                            root.transition = modelData.id;
                            root.save();
                            search.forceActiveFocus();
                        }
                    }
                }
            }
        }

        // Body
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.bodyHeight
            spacing: 10

            // Sidebar
            Rectangle {
                Layout.preferredWidth: root.sidebarWidth
                Layout.fillHeight: true
                radius: 14
                color: root.cardColor
                border.width: 1
                border.color: root.cardBorder
                clip: true

                ListView {
                    id: sidebar

                    anchors.fill: parent
                    anchors.margins: 5
                    model: root.sources
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 1
                    currentIndex: root.sourceIndex
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 200
                    highlightMoveVelocity: -1
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: 40
                    preferredHighlightEnd: height - 40
                    highlight: Rectangle {
                        radius: 9
                        color: "#161616"
                        border.width: 1
                        border.color: "#2a2a2a"

                        Rectangle {
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 14
                            radius: 1.5
                            color: root.accentColor
                        }
                    }

                    delegate: Item {
                        id: sourceRow

                        required property var modelData
                        required property int index

                        readonly property bool active: root.source === modelData.id
                        readonly property bool holdsCurrent: modelData.folder !== undefined && root.currentFile !== null && root.currentFile.folder === modelData.folder

                        width: sidebar.width
                        height: index === 2 ? 38 : 28

                        HoverHandler {
                            id: sourceHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.bottomMargin: sourceRow.index === 2 ? 10 : 0
                            radius: 9
                            color: sourceHover.hovered && !sourceRow.active ? "#0f0f0f" : "transparent"
                        }

                        // Divider under Recent
                        Rectangle {
                            visible: sourceRow.index === 2
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            x: 8
                            width: parent.width - 16
                            height: 1
                            color: "#1a1a1a"
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 28
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 7

                            MIcon {
                                name: sourceRow.modelData.icon
                                size: 13
                                filled: sourceRow.modelData.id === "fav"
                                color: sourceRow.modelData.id === "fav" ? root.favColor : (sourceRow.active ? root.primaryText : "#6a6a6a")
                            }

                            Text {
                                Layout.fillWidth: true
                                text: sourceRow.modelData.label
                                color: sourceRow.active ? root.primaryText : "#a0a0a0"
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: sourceRow.active ? Font.Bold : Font.DemiBold
                            }

                            Rectangle {
                                visible: sourceRow.holdsCurrent
                                Layout.preferredWidth: 5
                                Layout.preferredHeight: 5
                                radius: 2.5
                                color: root.accentColor
                            }

                            Text {
                                text: sourceRow.modelData.count
                                color: root.faintText
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectSource(sourceRow.modelData.id);
                                search.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // Grid
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: root.cardColor
                border.width: 1
                border.color: root.cardBorder
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: root.visibleFiles.length === 0

                    MIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: root.query !== "" ? "search_off" : (root.source === "fav" ? "favorite_border" : "image_not_supported")
                        size: 28
                        color: "#333333"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !root.scanned ? "Scanning…" : (root.query !== "" ? "Nothing matches “" + root.query + "”" : (root.source === "fav" ? "No favourites yet — Ctrl+S or ♥ on a wallpaper" : "Nothing here"))
                        color: "#6a6a6a"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                GridView {
                    id: grid

                    anchors.fill: parent
                    anchors.margins: 6
                    model: root.visibleFiles
                    cellWidth: width / root.columns
                    cellHeight: Math.round(cellWidth * 0.62)
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 160
                    currentIndex: -1
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 180
                    highlightRangeMode: GridView.ApplyRange
                    preferredHighlightBegin: 30
                    preferredHighlightEnd: height - 30
                    highlight: Item {
                        z: 3

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 11
                            color: "transparent"
                            border.width: 2
                            border.color: "#f5f5f5"
                        }
                    }

                    transform: Translate {
                        id: gridShift
                    }

                    SequentialAnimation {
                        id: swap

                        PropertyAction { target: grid; property: "opacity"; value: 0 }
                        PropertyAction { target: gridShift; property: "y"; value: 14 }
                        ParallelAnimation {
                            NumberAnimation { target: grid; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                            NumberAnimation { target: gridShift; property: "y"; to: 0; duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    delegate: Item {
                        id: tile

                        required property var modelData
                        required property int index

                        readonly property bool isCurrent: modelData.path === root.current
                        readonly property bool isCursor: index === root.cursor
                        readonly property bool fav: root.isFav(modelData.path)
                        readonly property bool busy: root.applying && root.applyingPath === modelData.path

                        width: grid.cellWidth
                        height: grid.cellHeight

                        HoverHandler {
                            id: tileHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        Item {
                            id: frame

                            anchors.fill: parent
                            anchors.margins: 5
                            scale: tileMouse.pressed ? 0.95 : (tile.isCursor || tileHover.hovered ? 1.03 : 1)

                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            // Rounded by ClippingRectangle rather than OpacityMask:
                            // the mask rendered every tile through two extra
                            // offscreen textures, all created in the same frames
                            // the island was opening, which is what stuttered.
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 9
                                color: "#111111"

                                Image {
                                    id: thumb

                                    // Cached thumb first; the original (downscaled) if
                                    // the cache doesn't have it yet.
                                    property bool fallback: false

                                    anchors.fill: parent
                                    source: thumb.fallback ? tile.modelData.path : root.thumbFor(tile.modelData.path)
                                    // Tiles are ~150px wide; decoding the 480px thumbs
                                    // at full size tripled the texture uploads.
                                    sourceSize.width: 320
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    onStatusChanged: if (status === Image.Error && !thumb.fallback) thumb.fallback = true

                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                }
                            }

                            Connections {
                                target: thumbEpoch

                                function onValueChanged() {
                                    thumb.fallback = false;
                                }
                            }

                            // Name
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 26
                                radius: 9
                                opacity: tileHover.hovered || tile.isCursor ? 1 : 0
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "#00000000" }
                                    GradientStop { position: 1; color: "#d0000000" }
                                }

                                Behavior on opacity { NumberAnimation { duration: 160 } }

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 6
                                    text: tile.modelData.name
                                    color: "#f5f5f5"
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }

                            // In use
                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: "transparent"
                                border.width: tile.isCurrent ? 2 : 0
                                border.color: root.accentColor
                            }

                            Rectangle {
                                visible: tile.isCurrent
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 5
                                width: 18
                                height: 18
                                radius: 9
                                color: root.accentColor

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "check"
                                    size: 13
                                    color: "#0b0b0b"
                                }
                            }

                            // Favourite heart
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 5
                                width: 20
                                height: 20
                                radius: 10
                                color: heartHover.hovered ? "#000000" : "#a0000000"
                                opacity: tile.fav || tileHover.hovered ? 1 : 0
                                scale: heartMouse.pressed ? 0.8 : 1

                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 3 } }

                                HoverHandler {
                                    id: heartHover
                                }

                                MIcon {
                                    anchors.centerIn: parent
                                    name: tile.fav ? "favorite" : "favorite_border"
                                    filled: tile.fav
                                    size: 12
                                    color: tile.fav ? root.favColor : "#e0e0e0"
                                }

                                MouseArea {
                                    id: heartMouse

                                    anchors.fill: parent
                                    anchors.margins: -3
                                    onClicked: root.toggleFav(tile.modelData.path)
                                }
                            }

                            // Applying
                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: "#90000000"
                                visible: tile.busy

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "progress_activity"
                                    size: 22
                                    color: root.accentColor

                                    RotationAnimation on rotation {
                                        running: tile.busy
                                        from: 0
                                        to: 360
                                        duration: 800
                                        loops: Animation.Infinite
                                    }
                                }
                            }

                            MouseArea {
                                id: tileMouse

                                z: -1
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                onClicked: mouse => {
                                    root.setCursor(tile.index);
                                    if (mouse.button === Qt.MiddleButton)
                                        root.openInViewer(tile.modelData.path);
                                    else if (mouse.button === Qt.RightButton)
                                        root.toggleFav(tile.modelData.path);
                                    else
                                        root.apply(tile.modelData.path);
                                    search.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }
        }

        // Footer: slideshow + status
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.footerHeight
            spacing: 8

            MIcon {
                name: "slideshow"
                size: 14
                color: root.slideshowMinutes > 0 ? root.accentColor : "#5a5a5a"
            }

            Text {
                text: root.slideshowMinutes > 0 ? "Slideshow · " + root.sourceLabel(root.slideshowSource) : "Slideshow"
                color: root.slideshowMinutes > 0 ? root.accentColor : root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            Row {
                spacing: 4

                Repeater {
                    model: root.slideshowOptions

                    Chip {
                        required property int modelData

                        text: modelData === 0 ? "Off" : (modelData >= 60 ? modelData / 60 + " h" : modelData + " min")
                        active: root.slideshowMinutes === modelData
                        onClicked: {
                            root.setSlideshow(modelData);
                            search.forceActiveFocus();
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.toast !== "" ? root.toast : (root.thumbProgress !== "" ? root.thumbProgress : "Enter set  ·  Tab folder  ·  Ctrl+S ♥  ·  Ctrl+R random  ·  Ctrl+Z back  ·  right-click ♥")
                color: root.toast !== "" ? root.accentColor : root.faintText
                elide: Text.ElideLeft
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }
}
