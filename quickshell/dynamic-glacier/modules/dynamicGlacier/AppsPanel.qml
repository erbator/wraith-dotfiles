import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// App launcher (Super+D). Favourites grid when the box is empty; type and
// it searches every installed app (name, description, keywords — "browser"
// finds Brave), ranked by match and by how often you launch it.
//
//   Enter launches · 1–9 launch a favourite · Ctrl+P / right-click pins
//   Ctrl+← → reorders favourites · a dot marks apps that are running
//
// Favourites: Quickshell.statePath("favorites.json") (same file as before).
// Launch counts: ~/.local/share/dynamic-glacier/app-usage.json
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color pinColor: "#f2c14b"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 30
    readonly property int searchHeight: 40
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 10
    readonly property int columns: 4
    readonly property int tileHeight: 76
    readonly property int tileSpacing: 6
    readonly property int rowHeight: 42
    readonly property int maxResults: 7

    readonly property int gridRows: Math.max(1, Math.ceil(Math.max(1, root.favourites.length) / root.columns))
    readonly property real bodyHeight: root.query.trim() !== "" ? Math.max(1, Math.min(root.maxResults, root.results.length)) * root.rowHeight : root.gridRows * root.tileHeight + (root.gridRows - 1) * root.tileSpacing
    property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.searchHeight + root.bodyHeight + root.hintHeight + root.sectionSpacing * 3
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    Behavior on contentHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    property string query: ""
    property int cursor: 0
    property var favouriteIds: []
    property var usage: ({})
    property string toast: ""

    // ── Apps ──────────────────────────────────────────────────────────────
    // "Spotify (Launcher)" → "Spotify", "VSCodium - Wayland" → "VSCodium"
    function cleanName(name) {
        const cleaned = String(name).replace(/\s*\([^)]*\)\s*$/, "").replace(/\s+[-–—]\s+.*$/, "").trim();
        return cleaned !== "" ? cleaned : String(name);
    }

    function fold(text) {
        return String(text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }

    readonly property var apps: {
        const list = [];
        const seen = {};
        for (const entry of DesktopEntries.applications.values) {
            if (!entry || entry.noDisplay || seen[entry.id])
                continue;
            seen[entry.id] = true;
            const name = root.cleanName(entry.name || entry.id);
            list.push({
                id: entry.id,
                name: name,
                detail: entry.genericName || entry.comment || "",
                icon: entry.icon ? Quickshell.iconPath(entry.icon, true) : "",
                wmClass: root.fold(entry.startupClass || ""),
                key: root.fold(name),
                extra: root.fold([entry.genericName, entry.comment, (entry.keywords || []).join(" "), (entry.categories || []).join(" "), entry.id].join(" "))
            });
        }
        list.sort((a, b) => a.name.localeCompare(b.name));
        return list;
    }

    function app(id) {
        return root.apps.find(a => a.id === id) || null;
    }

    readonly property var favourites: root.favouriteIds.map(id => root.app(id) || { id: id, name: id.replace(/\.desktop$/, ""), detail: "", icon: "", missing: true, wmClass: "", key: "", extra: "" })

    // Running: match Wayland app ids against desktop id / StartupWMClass.
    readonly property var runningIds: {
        const set = {};
        for (const toplevel of ToplevelManager.toplevels.values) {
            const id = root.fold(toplevel.appId || "");
            if (id !== "")
                set[id] = true;
        }
        return set;
    }

    function isRunning(entry) {
        if (!entry)
            return false;
        const base = root.fold(entry.id.replace(/\.desktop$/, ""));
        const last = base.split(".").pop();
        return root.runningIds[base] === true || root.runningIds[last] === true || (entry.wmClass !== "" && root.runningIds[entry.wmClass] === true);
    }

    function isPinned(id) {
        return root.favouriteIds.indexOf(id) !== -1;
    }

    // Ranked search: name start > word start > anywhere in the name >
    // description/keywords > letters in order; launch count breaks ties.
    readonly property var results: {
        const q = root.fold(root.query.trim());
        if (q === "")
            return [];
        const scored = [];
        for (const a of root.apps) {
            let score = 0;
            if (a.key.startsWith(q))
                score = 100;
            else if (a.key.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
                score = 70;
            else if (a.key.indexOf(q) !== -1)
                score = 55;
            else if (a.extra.indexOf(q) !== -1)
                score = 35;
            else {
                let i = 0;
                for (const c of a.key)
                    if (c === q[i])
                        i++;
                if (i === q.length && q.length >= 2)
                    score = 12;
            }
            if (score > 0)
                scored.push({ app: a, score: score + Math.log2((root.usage[a.id] || 0) + 1) * 8 + (root.isPinned(a.id) ? 40 : 0) });
        }
        scored.sort((x, y) => y.score - x.score || x.app.name.localeCompare(y.app.name));
        // Same app shipped twice (e.g. codium + codium-wayland): keep the
        // better-ranked one, which is the pinned/used one if either is.
        const seenNames = {};
        return scored.filter(s => {
            if (seenNames[s.app.name])
                return false;
            seenNames[s.app.name] = true;
            return true;
        }).slice(0, 40).map(s => s.app);
    }

    readonly property var visibleItems: root.query.trim() !== "" ? root.results : root.favourites

    // ── Actions ───────────────────────────────────────────────────────────
    function launch(entry) {
        if (!entry || entry.missing)
            return;
        const desktop = DesktopEntries.byId(entry.id);
        if (!desktop) {
            root.showToast("Can't find " + entry.name);
            return;
        }
        desktop.execute();
        const usage = Object.assign({}, root.usage);
        usage[entry.id] = (usage[entry.id] || 0) + 1;
        root.usage = usage;
        usageSave.restart();
        root.closeRequested();
    }

    function togglePin(entry) {
        if (!entry)
            return;
        if (root.isPinned(entry.id)) {
            root.favouriteIds = root.favouriteIds.filter(id => id !== entry.id);
            root.showToast("Unpinned " + entry.name);
        } else {
            root.favouriteIds = root.favouriteIds.concat([entry.id]);
            root.showToast("Pinned " + entry.name + " — key " + (root.favouriteIds.length <= 9 ? root.favouriteIds.length : "…"));
        }
        favouritesSave.restart();
    }

    function moveFavourite(delta) {
        if (root.query.trim() !== "" || root.favouriteIds.length < 2)
            return;
        const from = root.cursor;
        const to = from + delta;
        if (to < 0 || to >= root.favouriteIds.length)
            return;
        const ids = root.favouriteIds.slice();
        const moved = ids.splice(from, 1)[0];
        ids.splice(to, 0, moved);
        root.favouriteIds = ids;
        root.cursor = to;
        favouritesSave.restart();
    }

    function move(dx, dy) {
        const count = root.visibleItems.length;
        if (count === 0)
            return;
        if (root.query.trim() !== "")
            root.cursor = Math.max(0, Math.min(count - 1, root.cursor + dy + dx));
        else {
            const next = root.cursor + dx + dy * root.columns;
            if (next >= 0 && next < count)
                root.cursor = next;
        }
        if (root.query.trim() !== "")
            resultList.positionViewAtIndex(root.cursor, ListView.Contain);
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    onQueryChanged: root.cursor = 0

    // ── Files ─────────────────────────────────────────────────────────────
    FileView {
        id: favouritesFile

        path: Quickshell.statePath("favorites.json")
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(favouritesFile.text());
                if (Array.isArray(parsed))
                    root.favouriteIds = parsed.filter(id => typeof id === "string" && id !== "");
            } catch (error) {}
        }
    }

    Timer {
        id: favouritesSave

        interval: 200
        onTriggered: favouritesFile.setText(JSON.stringify(root.favouriteIds))
    }

    FileView {
        id: usageFile

        path: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/app-usage.json"
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(usageFile.text());
                if (parsed && typeof parsed === "object")
                    root.usage = parsed;
            } catch (error) {}
        }
    }

    Timer {
        id: usageSave

        interval: 200
        onTriggered: usageFile.setText(JSON.stringify(root.usage))
    }

    Timer {
        id: toastTimer

        interval: 2200
        onTriggered: root.toast = ""
    }

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
            search.text = "";
            root.query = "";
            root.cursor = 0;
            root.typedEarly = "";
            root.forceActiveFocus();
            focusAfterOpen.restart();
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

            Rectangle {
                Layout.preferredWidth: root.headerHeight
                Layout.preferredHeight: root.headerHeight
                radius: 10
                color: "#090909"
                border.width: 1
                border.color: "#232323"

                MIcon {
                    anchors.centerIn: parent
                    name: "apps"
                    size: 16
                    color: root.primaryText
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "Apps"
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: root.favouriteIds.length + " favourites  ·  " + root.apps.length + " apps"
                    color: root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 8
                color: closeHover.hovered ? "#1a1a1a" : "#0a0a0a"
                border.width: 1
                border.color: "#232323"

                HoverHandler {
                    id: closeHover

                    cursorShape: Qt.PointingHandCursor
                }

                MIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: 13
                    color: "#999999"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.closeRequested()
                }
            }
        }

        // Search
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.searchHeight
            radius: 12
            color: "#0a0a0a"
            border.width: 1
            border.color: search.text !== "" ? "#2f4f3a" : "#1f1f1f"

            Behavior on border.color { ColorAnimation { duration: 160 } }

            MIcon {
                id: searchIcon

                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 16
                color: search.text !== "" ? root.accentColor : "#555555"
            }

            TextInput {
                id: search

                anchors.left: searchIcon.right
                anchors.right: parent.right
                anchors.leftMargin: 9
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: root.primaryText
                selectionColor: "#2f4f3a"
                clip: true
                font.family: root.fontFamily
                font.pixelSize: 13
                onTextEdited: root.query = text

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const key = event.key;
                    const empty = search.text === "";
                    if (ctrl && key === Qt.Key_Left)
                        root.moveFavourite(-1);
                    else if (ctrl && key === Qt.Key_Right)
                        root.moveFavourite(1);
                    else if (key === Qt.Key_Up)
                        root.move(0, -1);
                    else if (key === Qt.Key_Down)
                        root.move(0, 1);
                    else if (key === Qt.Key_Left && empty)
                        root.move(-1, 0);
                    else if (key === Qt.Key_Right && empty)
                        root.move(1, 0);
                    else if (key === Qt.Key_Return || key === Qt.Key_Enter)
                        root.launch(root.visibleItems[root.cursor]);
                    else if (ctrl && key === Qt.Key_P)
                        root.togglePin(root.visibleItems[root.cursor]);
                    else if (empty && key >= Qt.Key_1 && key <= Qt.Key_9 && !ctrl)
                        root.launch(root.favourites[key - Qt.Key_1]);
                    else if (key === Qt.Key_Escape) {
                        if (!empty) {
                            search.text = "";
                            root.query = "";
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
                    text: "Search " + root.apps.length + " apps…"
                    color: "#555555"
                    font: search.font
                }
            }
        }

        // Body
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // ── Favourites grid ──
            Grid {
                id: grid

                readonly property real tileWidth: (width - (root.columns - 1) * root.tileSpacing) / root.columns

                anchors.left: parent.left
                anchors.right: parent.right
                columns: root.columns
                spacing: root.tileSpacing
                visible: root.query.trim() === ""
                opacity: visible ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 160 } }

                Repeater {
                    model: root.favourites

                    Rectangle {
                        id: tile

                        required property var modelData
                        required property int index

                        readonly property bool current: root.cursor === index
                        readonly property bool running: root.isRunning(modelData)

                        width: grid.tileWidth
                        height: root.tileHeight
                        radius: 12
                        color: tile.current ? "#161616" : (tileHover.hovered ? "#101010" : "#0a0a0a")
                        border.width: 1
                        border.color: tile.current ? "#343434" : "#171717"
                        scale: tileMouse.pressed ? 0.94 : 1
                        opacity: modelData.missing ? 0.4 : 1

                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                        HoverHandler {
                            id: tileHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        // Key number
                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 6
                            visible: tile.index < 9
                            text: tile.index + 1
                            color: tile.current || tileHover.hovered ? "#6a6a6a" : "#333333"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }

                        Image {
                            id: tileIcon

                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 11
                            width: 34
                            height: 34
                            source: tile.modelData.icon
                            sourceSize.width: 68
                            sourceSize.height: 68
                            asynchronous: true
                            smooth: true
                            scale: tileHover.hovered || tile.current ? 1.08 : 1

                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                        }

                        MIcon {
                            anchors.centerIn: tileIcon
                            visible: tileIcon.status !== Image.Ready
                            name: "deployed_code"
                            size: 26
                            color: "#7a7a7a"
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: tileIcon.bottom
                            anchors.topMargin: 3
                            width: 4
                            height: 4
                            radius: 2
                            color: root.accentColor
                            visible: tile.running
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            anchors.bottomMargin: 7
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.name
                            color: tile.current ? root.primaryText : "#bdbdbd"
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: tileMouse

                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                root.cursor = tile.index;
                                if (mouse.button === Qt.RightButton)
                                    root.togglePin(tile.modelData);
                                else
                                    root.launch(tile.modelData);
                                search.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.query.trim() === "" && root.favourites.length === 0
                text: "Type to find an app — Ctrl+P pins it here"
                color: "#555555"
                font.family: root.fontFamily
                font.pixelSize: 11
            }

            // ── Search results ──
            ListView {
                id: resultList

                anchors.fill: parent
                visible: root.query.trim() !== ""
                model: root.results
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.cursor
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 140
                highlight: Rectangle {
                    radius: 10
                    color: "#161616"
                    border.width: 1
                    border.color: "#2c2c2c"
                }

                delegate: Item {
                    id: result

                    required property var modelData
                    required property int index

                    readonly property bool pinned: root.isPinned(modelData.id)

                    width: resultList.width
                    height: root.rowHeight

                    HoverHandler {
                        id: resultHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26

                            Image {
                                id: resultIcon

                                anchors.fill: parent
                                source: result.modelData.icon
                                sourceSize.width: 52
                                sourceSize.height: 52
                                asynchronous: true
                                smooth: true
                            }

                            MIcon {
                                anchors.centerIn: parent
                                visible: resultIcon.status !== Image.Ready
                                name: "deployed_code"
                                size: 20
                                color: "#7a7a7a"
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: 1
                                width: 4
                                height: 4
                                radius: 2
                                color: root.accentColor
                                visible: root.isRunning(result.modelData)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: result.modelData.name
                                color: root.primaryText
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: result.modelData.detail
                                color: root.faintText
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: 10
                            }
                        }

                        MIcon {
                            visible: result.pinned || resultHover.hovered
                            name: "star"
                            filled: result.pinned
                            size: 14
                            color: result.pinned ? root.pinColor : "#5a5a5a"

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.togglePin(result.modelData);
                                    search.forceActiveFocus();
                                }
                            }
                        }
                    }

                    MouseArea {
                        z: -1
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            root.cursor = result.index;
                            if (mouse.button === Qt.RightButton)
                                root.togglePin(result.modelData);
                            else
                                root.launch(result.modelData);
                            search.forceActiveFocus();
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.query.trim() !== "" && root.results.length === 0
                text: "No app matches “" + root.query.trim() + "”"
                color: "#555555"
                font.family: root.fontFamily
                font.pixelSize: 11
            }
        }

        // Hint / toast
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: root.hintHeight
            horizontalAlignment: Text.AlignHCenter
            text: root.toast !== "" ? root.toast : (root.query.trim() !== "" ? "Enter launch  ·  ↑↓ choose  ·  Ctrl+P or right-click pins" : "Type to search  ·  1–9 launch  ·  Ctrl+← → reorder  ·  right-click unpins")
            color: root.toast !== "" ? root.accentColor : root.faintText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
    }
}
