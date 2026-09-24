import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Clipboard history over cliphist, plus pins that survive clearing it.
//
// Left: search, type filters and the list. Right: a preview of the
// highlighted entry — full decoded text, image, colour breakdown, link or
// file details — with its actions. The list follows new copies live while
// the panel is open.
//
// Everything that touches clipboard content goes through clip-helper.sh with
// the content in an environment variable, never in a command line, so no
// copied text can ever be executed.
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color dangerColor: "#f87171"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"
    readonly property string monoFamily: "CaskaydiaCove Nerd Font Mono"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 36
    readonly property int searchHeight: 34
    readonly property int filterHeight: 26
    readonly property int bodyHeight: 304
    readonly property int footerHeight: 18
    readonly property int listWidth: 330
    readonly property int rowHeight: 50
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.searchHeight + root.filterHeight + root.bodyHeight + root.footerHeight + 10 + 8 + 10 + 10
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property string helperPath: Quickshell.env("HOME") + "/.config/hypr/scripts/clip-helper.sh"
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/dynamic-glacier/clipboard"
    readonly property string pinsDir: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/clipboard-pins"
    readonly property string pinsPath: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/clipboard-pins.json"

    readonly property var kinds: ({
        text: { label: "Text", icon: "notes", tint: "#a3a3a3" },
        command: { label: "Command", icon: "terminal", tint: "#4ade80" },
        link: { label: "Link", icon: "link", tint: "#60a5fa" },
        image: { label: "Image", icon: "image", tint: "#c084fc" },
        file: { label: "File", icon: "draft", tint: "#fbbf24" },
        color: { label: "Colour", icon: "palette", tint: "#f472b6" }
    })

    readonly property var filters: [
        { key: "all", label: "All" },
        { key: "pinned", label: "Pinned" },
        { key: "text", label: "Text" },
        { key: "link", label: "Links" },
        { key: "image", label: "Images" },
        { key: "file", label: "Files" },
        { key: "color", label: "Colours" }
    ]

    property string historyOutput: ""
    property var history: []
    property var pins: []
    property var items: []
    property string filterKey: "all"
    property string searchText: ""
    property int highlightIndex: 0
    property var fullTextCache: ({})
    property var removingKeys: ({})
    property bool confirmClear: false
    property string toastText: ""
    property string toastIcon: "check_circle"
    property int openTick: 0
    property var actionQueue: []
    // Copy flash on the highlighted row, driven from here because the
    // highlight lives inside the ListView's own component scope.
    property real flashLevel: 0

    NumberAnimation {
        id: flashAnim

        target: root
        property: "flashLevel"
        from: 0.35
        to: 0
        duration: 420
        easing.type: Easing.OutCubic
    }

    readonly property var filteredItems: root.items.filter(item => {
        if (root.filterKey === "pinned" && !item.pinned)
            return false;

        if (root.filterKey !== "all" && root.filterKey !== "pinned") {
            const kind = item.kind === "command" ? "text" : item.kind;
            if (kind !== root.filterKey)
                return false;
        }

        if (root.searchText === "")
            return true;

        const needle = root.searchText.toLowerCase();
        const full = root.fullTextCache[item.raw] || item.text || "";
        return item.preview.toLowerCase().indexOf(needle) !== -1 || full.toLowerCase().indexOf(needle) !== -1;
    })

    readonly property var current: root.filteredItems[root.highlightIndex] || null
    readonly property string currentFullText: !root.current ? "" : (root.current.source === "pin" ? (root.current.text || "") : (root.fullTextCache[root.current.raw] || root.current.previewClean))

    // ── Classification ────────────────────────────────────────────────────

    function classify(preview) {
        const clean = preview.endsWith("…") ? preview.slice(0, -1) : preview;
        let match;

        if ((match = preview.match(/^\[\[ binary data (.+?) (\w+) (\d+)x(\d+) \]\]$/)))
            return { kind: "image", title: match[3] + " × " + match[4] + " " + match[2].toUpperCase(), meta: match[1], clean: clean };

        if (/^file:\/\//.test(preview)) {
            const paths = preview.split(/\s+(?=file:\/\/)/).map(p => decodeURIComponent(p.replace(/^file:\/\//, "")));
            const name = paths[0].replace(/\/$/, "").split("/").pop();
            return { kind: "file", title: paths.length > 1 ? name + " + " + (paths.length - 1) + " more" : name, meta: paths.length > 1 ? paths.length + " files" : paths[0].replace(/\/[^/]*\/?$/, "") || "/", clean: clean, paths: paths };
        }

        if (/^(\/|~\/)\S*$/.test(preview)) {
            const name = preview.replace(/\/$/, "").split("/").pop() || preview;
            return { kind: "file", title: name, meta: preview.replace(/\/[^/]*\/?$/, "") || "/", clean: clean, paths: [preview] };
        }

        if ((match = preview.match(/^https?:\/\/([^/\s]+)(\S*)$/)))
            return { kind: "link", title: match[1].replace(/^www\./, "") + (match[2] && match[2] !== "/" ? match[2] : ""), meta: match[1].replace(/^www\./, ""), clean: clean };

        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(preview.trim()) || /^rgba?\([\d\s,.%]+\)$/i.test(preview.trim()))
            return { kind: "color", title: preview.trim(), meta: root.colorParts(preview.trim())[1].value, clean: clean };

        if (/^(sudo |paru |yay |pacman |git |cd |ls |cat |echo |systemctl |hyprctl |quickshell |\.\/|kitty |nvim |cp |mv |rm |mkdir |curl |chmod |grep |find |python3? )/.test(preview))
            return { kind: "command", title: clean, meta: "Command", clean: clean };

        return { kind: "text", title: clean, meta: preview.endsWith("…") ? "Long text" : clean.length + " characters", clean: clean };
    }

    function rebuildItems() {
        const pinnedText = {};
        const pinItems = root.pins.map(pin => {
            const info = pin.image ? { kind: "image", title: pin.title || "Pinned image", meta: "Pinned", clean: "" } : root.classify((pin.text || "").slice(0, 100) + ((pin.text || "").length > 100 ? "…" : ""));
            pinnedText[(pin.text || pin.image || "").slice(0, 100)] = true;
            return Object.assign({}, info, { key: pin.id, source: "pin", raw: "", preview: (pin.text || "").slice(0, 200), previewClean: pin.text || "", text: pin.text || "", image: pin.image || "", pinned: true, pinId: pin.id });
        });

        const historyItems = root.history.map(entry => {
            const info = root.classify(entry.preview);
            return Object.assign({}, info, {
                key: "h" + entry.id,
                source: "history",
                raw: entry.raw,
                id: entry.id,
                preview: entry.preview,
                previewClean: info.clean,
                image: info.kind === "image" ? root.cacheDir + "/" + entry.id + ".img" : "",
                pinned: !!pinnedText[info.clean.slice(0, 100)]
            });
        });

        const previousKey = root.current ? root.current.key : "";
        root.items = pinItems.concat(historyItems);

        const index = root.filteredItems.findIndex(item => item.key === previousKey);
        root.highlightIndex = index !== -1 ? index : Math.min(root.highlightIndex, Math.max(0, root.filteredItems.length - 1));
    }

    function parseHistory(text) {
        if (text === root.historyOutput)
            return;

        root.historyOutput = text;
        root.history = text.split("\n").filter(line => line.trim() !== "").map(line => {
            const tab = line.indexOf("\t");
            return { raw: line, id: tab !== -1 ? line.slice(0, tab) : line, preview: tab !== -1 ? line.slice(tab + 1) : line };
        });
        root.rebuildItems();

        // Decode image entries into the cache so they get real previews.
        const images = root.history.filter(entry => /^\[\[ binary data /.test(entry.preview)).slice(0, 40).map(entry => entry.raw).join("\n");
        if (images !== "") {
            thumbProc.environment = { CLIP_LINES: images };
            thumbProc.running = false;
            thumbProc.running = true;
        }
    }

    function applyPinsJson(text) {
        try {
            const parsed = JSON.parse(text);
            root.pins = Array.isArray(parsed) ? parsed : [];
        } catch (error) {
            root.pins = [];
        }
        root.rebuildItems();
    }

    function savePins(pins) {
        root.pins = pins;
        pinsFile.setText(JSON.stringify(pins, null, 2) + "\n");
        root.rebuildItems();
    }

    // ── Actions ───────────────────────────────────────────────────────────

    // One helper call at a time, in order, so a delete never races the
    // rescan it triggers.
    function runHelper(args, env, rescan) {
        root.actionQueue = root.actionQueue.concat([{ args: args, env: env || {}, rescan: !!rescan }]);
        root.pumpQueue();
    }

    function pumpQueue() {
        if (actionProc.running || root.actionQueue.length === 0)
            return;

        const next = root.actionQueue[0];
        root.actionQueue = root.actionQueue.slice(1);
        actionProc.rescan = next.rescan;
        actionProc.environment = next.env;
        actionProc.command = [root.helperPath].concat(next.args);
        actionProc.running = true;
    }

    function showToast(text, icon) {
        root.toastText = text;
        root.toastIcon = icon || "check_circle";
        toastAnim.restart();
    }

    function copyItem(item, paste) {
        if (!item)
            return;

        const verb = paste ? "paste" : "copy";

        if (item.source === "pin" && item.image)
            root.runHelper([verb + "-file", item.image]);
        else if (item.source === "pin")
            root.runHelper([verb + "-text"], { CLIP_TEXT: item.text });
        else
            root.runHelper([verb], { CLIP_LINE: item.raw });

        flashAnim.restart();

        if (paste) {
            // The helper waits for the panel to close and focus to return
            // to the previous window before sending the paste shortcut.
            root.closeRequested();
        } else {
            root.showToast("Copied " + root.kinds[item.kind].label.toLowerCase(), "check_circle");
            closeAfterCopy.restart();
        }
    }

    function togglePin(item) {
        if (!item)
            return;

        if (item.pinned) {
            const key = (item.previewClean || "").slice(0, 100);
            root.savePins(root.pins.filter(pin => pin.id !== item.pinId && (pin.text || "").slice(0, 100) !== key));
            root.showToast("Unpinned", "keep_off");
            return;
        }

        const id = "pin-" + Date.now();

        if (item.kind === "image") {
            const path = root.pinsDir + "/" + id + ".img";
            root.runHelper(["save-image", path], { CLIP_LINE: item.raw });
            root.savePins([{ id: id, image: path, title: item.title, pinnedAt: Date.now() }].concat(root.pins));
            root.showToast("Pinned image", "keep");
            return;
        }

        const full = root.fullTextCache[item.raw];

        if (full !== undefined) {
            root.savePins([{ id: id, text: full, pinnedAt: Date.now() }].concat(root.pins));
            root.showToast("Pinned", "keep");
        } else {
            // Needs the full text first; the decode finishes the pin.
            fullProc.pinAfter = true;
            root.requestFullText(item, true);
        }
    }

    function deleteItem(item) {
        if (!item || root.removingKeys[item.key])
            return;

        const removing = Object.assign({}, root.removingKeys);
        removing[item.key] = true;
        root.removingKeys = removing;
        deleteTimer.pending = deleteTimer.pending.concat([item]);
        deleteTimer.restart();
    }

    function commitDeletes() {
        const items = deleteTimer.pending;
        deleteTimer.pending = [];

        const pinIds = items.filter(item => item.source === "pin").map(item => item.pinId);
        if (pinIds.length)
            root.savePins(root.pins.filter(pin => pinIds.indexOf(pin.id) === -1));

        const historyItems = items.filter(item => item.source === "history");
        for (const item of historyItems)
            root.runHelper(["delete"], { CLIP_LINE: item.raw }, true);

        // Optimistic: drop them now, the rescan confirms.
        const gone = historyItems.map(item => item.raw);
        root.history = root.history.filter(entry => gone.indexOf(entry.raw) === -1);
        root.removingKeys = ({});
        root.rebuildItems();
        root.showToast(items.length === 1 ? "Deleted" : "Deleted " + items.length, "delete");
    }

    function openItem(item) {
        if (!item)
            return;

        if (item.kind === "link") {
            Quickshell.execDetached(["xdg-open", item.previewClean.trim()]);
            root.closeRequested();
        } else if (item.kind === "file" && item.paths && item.paths.length) {
            Quickshell.execDetached(["xdg-open", item.paths[0].replace(/^~/, Quickshell.env("HOME"))]);
            root.closeRequested();
        } else if (item.kind === "image" && item.image) {
            Quickshell.execDetached(["xdg-open", item.image]);
            root.closeRequested();
        }
    }

    function clearHistory() {
        if (!root.confirmClear) {
            root.confirmClear = true;
            confirmResetTimer.restart();
            return;
        }

        root.confirmClear = false;
        root.runHelper(["wipe"], {}, true);
        root.history = [];
        root.historyOutput = "";
        root.rebuildItems();
        root.showToast("History cleared · pins kept", "delete_sweep");
    }

    function requestFullText(item, force) {
        if (!item || item.source !== "history" || item.kind === "image")
            return;

        if (!force && root.fullTextCache[item.raw] !== undefined)
            return;

        fullProc.running = false;
        fullProc.requestRaw = item.raw;
        fullProc.environment = { CLIP_LINE: item.raw };
        fullProc.running = true;
    }

    function moveHighlight(delta) {
        if (root.filteredItems.length === 0)
            return;

        root.highlightIndex = Math.max(0, Math.min(root.filteredItems.length - 1, root.highlightIndex + delta));
    }

    function cycleFilter(delta) {
        const index = root.filters.findIndex(filter => filter.key === root.filterKey);
        root.filterKey = root.filters[(index + delta + root.filters.length) % root.filters.length].key;
    }

    function countFor(key) {
        if (key === "all")
            return root.items.length;
        if (key === "pinned")
            return root.items.filter(item => item.pinned).length;
        return root.items.filter(item => (item.kind === "command" ? "text" : item.kind) === key).length;
    }

    function colorParts(value) {
        const c = Qt.color(value);
        const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b);
        let h = 0, s = 0;
        const l = (max + min) / 2;

        if (max !== min) {
            const d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max === c.r) h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0);
            else if (max === c.g) h = (c.b - c.r) / d + 2;
            else h = (c.r - c.g) / d + 4;
            h *= 60;
        }

        return [
            { label: "HEX", value: "#" + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("") },
            { label: "RGB", value: "rgb(" + [c.r, c.g, c.b].map(v => Math.round(v * 255)).join(", ") + ")" },
            { label: "HSL", value: "hsl(" + Math.round(h) + ", " + Math.round(s * 100) + "%, " + Math.round(l * 100) + "%)" }
        ];
    }

    onSearchTextChanged: root.highlightIndex = 0
    onFilterKeyChanged: root.highlightIndex = 0
    onCurrentChanged: fullTextDebounce.restart()

    // ── Processes & files ─────────────────────────────────────────────────

    Process {
        id: scanProc

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.parseHistory(text)
        }
    }

    Process {
        id: thumbProc

        command: [root.helperPath, "thumbs"]
        stdout: StdioCollector {
            // Re-point image sources now that their files exist.
            onStreamFinished: root.rebuildItems()
        }
    }

    Process {
        id: fullProc

        property string requestRaw: ""
        property bool pinAfter: false

        command: [root.helperPath, "full"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cache = Object.assign({}, root.fullTextCache);
                cache[fullProc.requestRaw] = text;
                root.fullTextCache = cache;

                if (fullProc.pinAfter) {
                    fullProc.pinAfter = false;
                    root.savePins([{ id: "pin-" + Date.now(), text: text, pinnedAt: Date.now() }].concat(root.pins));
                    root.showToast("Pinned", "keep");
                }
            }
        }
    }

    Process {
        id: actionProc

        property bool rescan: false

        onExited: (exitCode, exitStatus) => {
            if (actionProc.rescan) {
                scanProc.running = false;
                scanProc.running = true;
            }
            root.pumpQueue();
        }
    }

    FileView {
        id: pinsFile

        path: root.pinsPath
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyPinsJson(pinsFile.text())
        onLoadFailed: root.applyPinsJson("[]")
    }

    // Follows new copies while the panel is open.
    Timer {
        interval: 1500
        repeat: true
        running: root.visible
        onTriggered: if (!scanProc.running) scanProc.running = true
    }

    Timer {
        id: fullTextDebounce

        interval: 90
        onTriggered: root.requestFullText(root.current, false)
    }

    Timer {
        id: deleteTimer

        property var pending: []

        interval: 200
        onTriggered: root.commitDeletes()
    }

    Timer {
        id: confirmResetTimer

        interval: 2600
        onTriggered: root.confirmClear = false
    }

    Timer {
        id: closeAfterCopy

        interval: 420
        onTriggered: root.closeRequested()
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            searchInput.text = "";
            root.filterKey = "all";
            root.highlightIndex = 0;
            root.confirmClear = false;
            root.openTick++;
            closeAfterCopy.stop();
            Quickshell.execDetached(["mkdir", "-p", root.pinsDir]);
            scanProc.running = false;
            scanProc.running = true;
            searchInput.forceActiveFocus();
        }
    }

    // ── Building blocks ───────────────────────────────────────────────────

    component HeaderButton: Rectangle {
        id: headerButton

        required property string icon
        property string label: ""
        property color tint: "#a8a8a8"
        property bool danger: false

        signal clicked

        implicitWidth: headerButton.label !== "" ? headerRow.implicitWidth + 18 : 26
        implicitHeight: 26
        radius: 9
        color: headerButton.danger ? "#2a1111" : (headerMouse.containsMouse ? "#1a1a1a" : "#0a0a0a")
        border.width: 1
        border.color: headerButton.danger ? root.dangerColor : "#232323"
        scale: headerMouse.pressed ? 0.9 : (headerMouse.containsMouse ? 1.05 : 1)

        Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

        Row {
            id: headerRow

            anchors.centerIn: parent
            spacing: 5

            MIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: headerButton.icon
                size: 13
                color: headerButton.danger ? root.dangerColor : headerButton.tint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: headerButton.label !== ""
                text: headerButton.label
                color: headerButton.danger ? root.dangerColor : "#bdbdbd"
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: headerMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: headerButton.clicked()
        }
    }

    component ActionButton: Rectangle {
        id: actionButton

        required property string icon
        required property string label
        property string keys: ""
        property bool primary: false
        property bool danger: false
        property bool active: true

        signal clicked

        Layout.fillWidth: true
        Layout.preferredHeight: 30
        radius: 9
        color: !actionButton.active ? root.cardColor : (actionButton.primary ? (actionMouse.containsMouse ? Qt.lighter(root.accentColor, 1.1) : root.accentColor) : (actionMouse.containsMouse ? (actionButton.danger ? "#2a1111" : "#161616") : "#0d0d0d"))
        border.width: 1
        border.color: actionButton.primary && actionButton.active ? root.accentColor : (actionMouse.containsMouse && actionButton.danger ? root.dangerColor : "#232323")
        opacity: actionButton.active ? 1 : 0.35
        scale: actionMouse.pressed && actionButton.active ? 0.94 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        Row {
            anchors.centerIn: parent
            spacing: 5

            MIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: actionButton.icon
                size: 13
                color: actionButton.primary ? "#04140a" : (actionButton.danger && actionMouse.containsMouse ? root.dangerColor : "#cfcfcf")
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: actionButton.label
                color: actionButton.primary ? "#04140a" : "#cfcfcf"
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: actionButton.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (actionButton.active) actionButton.clicked()
        }
    }

    // Kind tile: image thumbnail, colour swatch, or a tinted icon.
    component KindTile: Rectangle {
        id: tile

        required property var item
        property int size: 34

        width: tile.size
        height: tile.size
        radius: tile.size * 0.28
        color: tile.item.kind === "color" ? tile.item.previewClean.trim() : Qt.rgba(Qt.color(root.kinds[tile.item.kind].tint).r, Qt.color(root.kinds[tile.item.kind].tint).g, Qt.color(root.kinds[tile.item.kind].tint).b, 0.12)
        border.width: 1
        border.color: tile.item.kind === "color" ? "#2a2a2a" : Qt.rgba(Qt.color(root.kinds[tile.item.kind].tint).r, Qt.color(root.kinds[tile.item.kind].tint).g, Qt.color(root.kinds[tile.item.kind].tint).b, 0.28)
        clip: true

        MIcon {
            anchors.centerIn: parent
            visible: tile.item.kind !== "color" && !(tile.item.kind === "image" && thumb.status === Image.Ready)
            name: root.kinds[tile.item.kind].icon
            size: tile.size * 0.46
            color: root.kinds[tile.item.kind].tint
        }

        Image {
            id: thumb

            anchors.fill: parent
            visible: tile.item.kind === "image" && status === Image.Ready
            source: tile.item.kind === "image" && tile.item.image ? "file://" + tile.item.image : ""
            sourceSize.width: 96
            sourceSize.height: 96
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panelPadding
        spacing: 0

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 8

            Rectangle {
                Layout.preferredWidth: root.headerHeight
                Layout.preferredHeight: root.headerHeight
                radius: 12
                color: "#090909"
                border.width: 1
                border.color: "#232323"

                MIcon {
                    id: headerIcon

                    anchors.centerIn: parent
                    name: "content_paste"
                    size: 16
                    color: root.primaryText
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "Clipboard"
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: root.history.length + " in history · " + root.pins.length + " pinned"
                    color: root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.features: { "tnum": 1 }
                    font.pixelSize: 10
                }
            }

            HeaderButton {
                icon: "delete_sweep"
                label: root.confirmClear ? "Clear history?" : ""
                danger: root.confirmClear
                onClicked: root.clearHistory()
            }

            HeaderButton {
                icon: "close"
                onClicked: root.closeRequested()
            }
        }

        Item { Layout.preferredHeight: 10 }

        // Search
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.searchHeight
            radius: 11
            color: "#0a0a0a"
            border.width: 1
            border.color: searchInput.activeFocus ? root.accentColor : "#232323"

            Behavior on border.color { ColorAnimation { duration: 160 } }

            MIcon {
                anchors.left: parent.left
                anchors.leftMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 15
                color: "#5f5f5f"
            }

            TextInput {
                id: searchInput

                anchors.fill: parent
                anchors.leftMargin: 34
                anchors.rightMargin: 12
                verticalAlignment: Text.AlignVCenter
                color: root.primaryText
                font.family: root.fontFamily
                font.pixelSize: 12
                clip: true
                selectByMouse: true

                onTextChanged: root.searchText = text

                Keys.onUpPressed: root.moveHighlight(-1)
                Keys.onDownPressed: root.moveHighlight(1)
                Keys.onTabPressed: root.cycleFilter(1)
                Keys.onBacktabPressed: root.cycleFilter(-1)
                Keys.onEscapePressed: {
                    if (searchInput.text !== "")
                        searchInput.text = "";
                    else
                        root.closeRequested();
                }
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;

                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.copyItem(root.current, (event.modifiers & Qt.ShiftModifier) !== 0);
                        event.accepted = true;
                    } else if (ctrl && event.key === Qt.Key_P) {
                        root.togglePin(root.current);
                        event.accepted = true;
                    } else if (ctrl && event.key === Qt.Key_O) {
                        root.openItem(root.current);
                        event.accepted = true;
                    } else if ((ctrl && event.key === Qt.Key_D) || (event.key === Qt.Key_Delete && searchInput.text === "")) {
                        root.deleteItem(root.current);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageDown) {
                        root.moveHighlight(6);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        root.moveHighlight(-6);
                        event.accepted = true;
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text === ""
                    text: "Search everything you've copied…"
                    color: "#5f5f5f"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }
            }
        }

        Item { Layout.preferredHeight: 8 }

        // Filters with counts
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: root.filterHeight
            spacing: 5

            Repeater {
                model: root.filters

                Rectangle {
                    id: filterChip

                    required property var modelData

                    readonly property bool selected: root.filterKey === modelData.key
                    readonly property int count: root.countFor(modelData.key)

                    width: filterRow.implicitWidth + 16
                    height: root.filterHeight
                    radius: 9
                    color: filterChip.selected ? "#f0f0f0" : (filterMouse.containsMouse ? "#161616" : "#0c0c0c")
                    border.width: 1
                    border.color: filterChip.selected ? "#f0f0f0" : "#1f1f1f"
                    opacity: filterChip.count === 0 && !filterChip.selected ? 0.4 : 1
                    scale: filterMouse.pressed ? 0.92 : 1

                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    Row {
                        id: filterRow

                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: filterChip.modelData.label
                            color: filterChip.selected ? "#050505" : "#cfcfcf"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: filterChip.count
                            color: filterChip.selected ? "#555555" : "#5f5f5f"
                            font.family: root.fontFamily
                            font.features: { "tnum": 1 }
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: filterMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.filterKey = filterChip.modelData.key
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 10 }

        // Body
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.bodyHeight
            spacing: 10

            // List
            Item {
                Layout.preferredWidth: root.listWidth
                Layout.fillHeight: true

                // Empty state
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.filteredItems.length === 0
                    opacity: visible ? 1 : 0

                    MIcon {
                        id: emptyIcon

                        anchors.horizontalCenter: parent.horizontalCenter
                        name: root.searchText !== "" ? "search_off" : (root.filterKey === "pinned" ? "keep" : "content_paste_off")
                        size: 28
                        color: "#3a3a3a"

                        SequentialAnimation on y {
                            running: root.visible && root.filteredItems.length === 0
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: -4; duration: 1100; easing.type: Easing.InOutSine }
                            NumberAnimation { from: -4; to: 0; duration: 1100; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.searchText !== "" ? "Nothing matches “" + root.searchText + "”" : (root.filterKey === "pinned" ? "Pin things with Ctrl+P to keep them" : "Nothing here yet")
                        color: root.secondaryText
                        font.family: root.fontFamily
                        font.pixelSize: 11
                    }
                }

                ListView {
                    id: list

                    anchors.fill: parent
                    spacing: 2
                    clip: true
                    model: root.filteredItems
                    currentIndex: root.highlightIndex
                    boundsBehavior: Flickable.StopAtBounds
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 220
                    highlightMoveVelocity: -1
                    cacheBuffer: 400

                    onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)

                    highlight: Rectangle {
                        width: list.width
                        height: root.rowHeight
                        radius: 12
                        color: "#131313"
                        border.width: 1
                        border.color: "#262626"

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.accentColor
                            opacity: root.flashLevel
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 1
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: parent.height - 20
                            radius: 1.5
                            color: root.accentColor
                        }
                    }

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index

                        readonly property bool selected: index === root.highlightIndex
                        readonly property bool removing: !!root.removingKeys[modelData.key]
                        property real enter: 1

                        width: list.width
                        height: row.removing ? 0 : root.rowHeight
                        opacity: row.removing ? 0 : row.enter
                        clip: true
                        transform: Translate { x: (1 - row.enter) * -12 }

                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.InCubic } }
                        Behavior on opacity { NumberAnimation { duration: 160 } }

                        Connections {
                            target: root
                            function onOpenTickChanged() {
                                if (row.index < 10)
                                    rowEnter.restart();
                            }
                        }

                        SequentialAnimation {
                            id: rowEnter

                            PropertyAction { target: row; property: "enter"; value: 0 }
                            PauseAnimation { duration: 40 + row.index * 32 }
                            NumberAnimation { target: row; property: "enter"; to: 1; duration: 280; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 10

                            KindTile {
                                item: row.modelData
                                scale: row.selected ? 1.06 : 1

                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.title.replace(/\s+/g, " ")
                                    color: row.selected ? root.primaryText : "#c8c8c8"
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: row.modelData.kind === "command" || row.modelData.kind === "color" ? root.monoFamily : root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.kinds[row.modelData.kind].label + " · " + row.modelData.meta
                                    color: root.secondaryText
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }
                            }

                            // Hover actions, or the pin marker at rest.
                            Item {
                                Layout.preferredWidth: 50
                                Layout.fillHeight: true

                                MIcon {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "keep"
                                    size: 13
                                    color: root.accentColor
                                    opacity: row.modelData.pinned && !rowMouse.containsMouse ? 1 : 0

                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    opacity: rowMouse.containsMouse ? 1 : 0
                                    x: rowMouse.containsMouse ? 0 : 8

                                    Behavior on opacity { NumberAnimation { duration: 140 } }

                                    Repeater {
                                        model: [
                                            { icon: row.modelData.pinned ? "keep_off" : "keep", action: "pin" },
                                            { icon: "delete", action: "delete" }
                                        ]

                                        Rectangle {
                                            required property var modelData

                                            width: 22
                                            height: 22
                                            radius: 7
                                            color: miniMouse.containsMouse ? (modelData.action === "delete" ? "#2a1111" : "#1e1e1e") : "transparent"

                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            MIcon {
                                                anchors.centerIn: parent
                                                name: parent.modelData.icon
                                                size: 13
                                                color: miniMouse.containsMouse && parent.modelData.action === "delete" ? root.dangerColor : "#a8a8a8"
                                            }

                                            MouseArea {
                                                id: miniMouse

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (parent.modelData.action === "pin")
                                                        root.togglePin(row.modelData);
                                                    else
                                                        root.deleteItem(row.modelData);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            z: -1
                            onClicked: mouse => {
                                root.highlightIndex = row.index;
                                if (mouse.button === Qt.MiddleButton)
                                    root.copyItem(row.modelData, true);
                            }
                            onDoubleClicked: root.copyItem(row.modelData, false)
                        }
                    }
                }
            }

            // Preview
            Rectangle {
                id: previewCard

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: root.cardColor
                border.width: 1
                border.color: root.cardBorder
                clip: true

                // Quick settle each time the selection changes.
                Connections {
                    target: root
                    function onCurrentChanged() {
                        previewSettle.restart();
                    }
                }

                ParallelAnimation {
                    id: previewSettle

                    NumberAnimation { target: previewBody; property: "opacity"; from: 0.25; to: 1; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: previewBody; property: "y"; from: 6; to: 0; duration: 240; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !root.current
                    text: "Select something to preview it"
                    color: root.faintText
                    font.family: root.fontFamily
                    font.pixelSize: 11
                }

                Item {
                    id: previewBody

                    width: parent.width
                    height: parent.height
                    visible: root.current !== null

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // Kind header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            KindTile {
                                item: root.current || ({ kind: "text", previewClean: "" })
                                size: 26
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: root.current ? root.kinds[root.current.kind].label + (root.current.pinned ? " · Pinned" : "") : ""
                                    color: root.primaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const item = root.current;
                                        if (!item)
                                            return "";
                                        if (item.kind !== "text" && item.kind !== "command")
                                            return item.meta;
                                        const t = root.currentFullText;
                                        const plural = (n, word) => n + " " + word + (n === 1 ? "" : "s");
                                        return plural(t.length, "char") + " · " + plural(t.split("\n").length, "line") + " · " + plural(t.trim() === "" ? 0 : t.trim().split(/\s+/).length, "word");
                                    }
                                    color: root.secondaryText
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.features: { "tnum": 1 }
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // Content
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Text / command
                            Rectangle {
                                anchors.fill: parent
                                visible: root.current && (root.current.kind === "text" || root.current.kind === "command")
                                radius: 10
                                color: "#050505"
                                border.width: 1
                                border.color: "#151515"
                                clip: true

                                Flickable {
                                    id: textFlick

                                    anchors.fill: parent
                                    anchors.margins: 10
                                    contentWidth: width
                                    contentHeight: fullText.implicitHeight
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true

                                    Text {
                                        id: fullText

                                        width: textFlick.width
                                        text: root.currentFullText
                                        color: "#d8d8d8"
                                        wrapMode: Text.WrapAnywhere
                                        textFormat: Text.PlainText
                                        font.family: root.monoFamily
                                        font.pixelSize: 11
                                        lineHeight: 1.15
                                    }
                                }

                                // Fade hinting there is more below
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 24
                                    radius: 10
                                    visible: textFlick.contentHeight > textFlick.height && !textFlick.atYEnd
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "#00050505" }
                                        GradientStop { position: 1; color: "#050505" }
                                    }
                                }
                            }

                            // Image
                            Rectangle {
                                anchors.fill: parent
                                visible: root.current && root.current.kind === "image"
                                radius: 10
                                color: "#050505"
                                border.width: 1
                                border.color: "#151515"
                                clip: true

                                Image {
                                    id: bigImage

                                    anchors.fill: parent
                                    anchors.margins: 8
                                    source: root.current && root.current.kind === "image" && root.current.image ? "file://" + root.current.image : ""
                                    sourceSize.width: 600
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    smooth: true
                                    opacity: status === Image.Ready ? 1 : 0

                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: bigImage.status !== Image.Ready
                                    text: "Decoding…"
                                    color: root.faintText
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            // Colour
                            ColumnLayout {
                                anchors.fill: parent
                                visible: root.current && root.current.kind === "color"
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 12
                                    color: root.current && root.current.kind === "color" ? root.current.previewClean.trim() : "transparent"
                                    border.width: 1
                                    border.color: "#2a2a2a"

                                    Behavior on color { ColorAnimation { duration: 240 } }
                                }

                                Repeater {
                                    model: root.current && root.current.kind === "color" ? root.colorParts(root.current.previewClean.trim()) : []

                                    Rectangle {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 26
                                        radius: 8
                                        color: partMouse.containsMouse ? "#151515" : "#0c0c0c"
                                        border.width: 1
                                        border.color: "#1c1c1c"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8

                                            Text {
                                                text: parent.parent.modelData.label
                                                color: root.faintText
                                                font.family: root.fontFamily
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignRight
                                                text: parent.parent.modelData.value
                                                color: "#d8d8d8"
                                                font.family: root.monoFamily
                                                font.pixelSize: 11
                                            }

                                            MIcon {
                                                name: "content_copy"
                                                size: 11
                                                color: partMouse.containsMouse ? root.accentColor : "#4a4a4a"
                                            }
                                        }

                                        MouseArea {
                                            id: partMouse

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.runHelper(["copy-text"], { CLIP_TEXT: parent.modelData.value });
                                                root.showToast("Copied " + parent.modelData.value, "check_circle");
                                            }
                                        }
                                    }
                                }
                            }

                            // Link / file
                            ColumnLayout {
                                anchors.fill: parent
                                visible: root.current && (root.current.kind === "link" || root.current.kind === "file")
                                spacing: 8

                                Item { Layout.fillHeight: true }

                                MIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    name: root.current ? root.kinds[root.current.kind].icon : "link"
                                    size: 40
                                    color: root.current ? root.kinds[root.current.kind].tint : "#777777"
                                }

                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.current ? (root.current.kind === "link" ? root.current.meta : root.current.title) : ""
                                    color: root.primaryText
                                    elide: Text.ElideMiddle
                                    font.family: root.fontFamily
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                }

                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.current ? (root.current.kind === "link" ? root.current.previewClean : (root.current.paths || []).join("\n")) : ""
                                    color: root.secondaryText
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 5
                                    elide: Text.ElideRight
                                    font.family: root.monoFamily
                                    font.pixelSize: 10
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        // Actions
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            ActionButton {
                                icon: "content_copy"
                                label: "Copy"
                                primary: true
                                onClicked: root.copyItem(root.current, false)
                            }

                            ActionButton {
                                icon: "keyboard_return"
                                label: "Paste"
                                onClicked: root.copyItem(root.current, true)
                            }

                            ActionButton {
                                icon: root.current && root.current.pinned ? "keep_off" : "keep"
                                label: root.current && root.current.pinned ? "Unpin" : "Pin"
                                onClicked: root.togglePin(root.current)
                            }

                            ActionButton {
                                icon: "open_in_new"
                                label: "Open"
                                active: root.current !== null && (root.current.kind === "link" || root.current.kind === "file" || root.current.kind === "image")
                                onClicked: root.openItem(root.current)
                            }

                            ActionButton {
                                Layout.fillWidth: false
                                Layout.preferredWidth: 32
                                icon: "delete"
                                label: ""
                                danger: true
                                onClicked: root.deleteItem(root.current)
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 10 }

        // Footer: shortcuts, replaced by a toast after an action.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.footerHeight

            Text {
                id: shortcutsText

                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "⏎ copy · ⇧⏎ paste · ^P pin · ^O open · ^D delete · Tab filter · middle-click pastes"
                color: root.faintText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 10
            }

            Row {
                id: toast

                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                opacity: 0

                MIcon {
                    id: toastIconItem

                    anchors.verticalCenter: parent.verticalCenter
                    name: root.toastIcon
                    size: 14
                    color: root.accentColor
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.toastText
                    color: "#e0e0e0"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            SequentialAnimation {
                id: toastAnim

                ParallelAnimation {
                    NumberAnimation { target: shortcutsText; property: "opacity"; to: 0; duration: 120 }
                    NumberAnimation { target: toast; property: "opacity"; from: 0; to: 1; duration: 160 }
                    NumberAnimation { target: toast; property: "x"; from: -8; to: 0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    NumberAnimation { target: toastIconItem; property: "scale"; from: 0.3; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 3 }
                }
                PauseAnimation { duration: 1600 }
                ParallelAnimation {
                    NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 200 }
                    NumberAnimation { target: shortcutsText; property: "opacity"; to: 1; duration: 260 }
                }
            }
        }
    }
}
