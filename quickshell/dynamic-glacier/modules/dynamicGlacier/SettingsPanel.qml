import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Glacier settings, in three tabs:
//   Island    the island itself (glass, handle, size, UI font)
//   Hyprland  window looks, applied live by set-compositor.sh
//   Terminal  kitty, applied live by set-kitty.sh
//
// Rows are grouped into cards with no per-row descriptions; hovering a row
// explains it in the hint line at the bottom instead. Every change applies
// immediately, sliders included (throttled while dragging).
Item {
    id: root

    // Island
    property bool liquidGlassEnabled: false
    property string handleStyle: "bump"
    property int idleWidth: 340
    property int idleHeight: 132
    property string fontFamily: "Noto Sans"
    property var fontOptions: []
    // Hyprland — one object owned by DynamicGlacier
    property var compositor: ({})
    property real morph: 0

    signal closeRequested
    signal liquidGlassRequested(bool enabled)
    signal handleStyleRequested(string style)
    signal fontFamilyRequested(string family)
    signal idleWidthRequested(int width)
    signal idleHeightRequested(int height)
    signal resetRequested
    signal compositorRequested(var patch)

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"
    readonly property color hairline: "#141414"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int tabBarHeight: 32
    readonly property int hintHeight: 16
    readonly property int sectionSpacing: 12
    readonly property int rowHeight: 36

    property int currentTab: 0
    property int previousTab: 0
    property string hint: ""

    readonly property var tabs: [
        { label: "Island", icon: "rounded_corner", blurb: "The island itself — saved with the shell" },
        { label: "Hyprland", icon: "desktop_windows", blurb: "Window looks — applied live, kept across reloads" },
        { label: "Terminal", icon: "terminal", blurb: "Kitty — every open window reloads instantly" }
    ]

    readonly property real activeTabHeight: [islandTab.implicitHeight, hyprTab.implicitHeight, terminalTab.implicitHeight][root.currentTab]

    // The panel grows and shrinks with the tab's content; animated so a tab
    // switch morphs the whole island rather than jumping.
    property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.tabBarHeight + root.activeTabHeight + root.hintHeight + root.sectionSpacing * 3
    Behavior on contentHeight { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // ── Hyprland ──────────────────────────────────────────────────────────
    readonly property var compositorDefaults: ({ glass: true, opacity: 65, gaps: 6, rounding: 18, border: 0, blur: true, animations: true, dim: false })
    readonly property var layoutPresets: [
        { label: "Floating", gaps: 6, rounding: 18, border: 0 },
        { label: "Tight", gaps: 3, rounding: 10, border: 1 },
        { label: "Edge to Edge", gaps: 0, rounding: 0, border: 2 }
    ]
    readonly property int currentPreset: root.layoutPresets.findIndex(p => p.gaps === root.comp("gaps", 6) && p.rounding === root.comp("rounding", 18) && p.border === root.comp("border", 0))

    function comp(key, fallback) {
        return root.compositor && root.compositor[key] !== undefined ? root.compositor[key] : fallback;
    }

    function setComp(patch) {
        root.compositorRequested(patch);
    }

    // ── Terminal (kitty) ──────────────────────────────────────────────────
    readonly property string kittyConfigPath: Quickshell.env("HOME") + "/.config/kitty/kitty.conf"
    readonly property string setKittyPath: Quickshell.env("HOME") + "/.config/hypr/scripts/set-kitty.sh"
    readonly property var terminalFonts: ["CaskaydiaCove", "JetBrainsMono", "FiraCode", "Hack", "MesloLGM", "SFMono", "IosevkaTerm", "FantasqueSansM"]
    readonly property var kittyDefaults: ({ font_family: "CaskaydiaCove Nerd Font Mono", font_size: 11, window_padding_width: 10, cursor_shape: "block", cursor_trail: 1 })

    property string kittyFont: ""
    property int kittySize: 11
    property int kittyOpacity: 100
    property int kittyPadding: 0
    property string kittyCursor: "block"
    property bool kittyTrail: false
    property var kittyQueue: ({})

    function parseKittyConfig(text) {
        const lines = text.split("\n");
        const value = key => {
            for (const line of lines) {
                const match = line.match(new RegExp("^\\s*" + key + "\\s+(.+?)\\s*$"));
                if (match)
                    return match[1];
            }
            return null;
        };

        const family = value("font_family");
        const familyMatch = family ? family.match(/family="([^"]+)"/) : null;
        root.kittyFont = familyMatch ? familyMatch[1] : (family || "");
        root.kittySize = Math.round(Number(value("font_size")) || 11);
        root.kittyOpacity = Math.round((Number(value("background_opacity") ?? 1) || 1) * 100);
        root.kittyPadding = Math.round(Number((value("window_padding_width") || "0").split(/\s+/)[0]) || 0);
        root.kittyCursor = value("cursor_shape") || "block";
        root.kittyTrail = Number(value("cursor_trail") || 0) > 0;
    }

    // Writes go through a queue so a slider being dragged never has two
    // edits of kitty.conf racing each other; only the newest value per
    // setting is kept while one is in flight.
    function setKitty(key, value) {
        const queue = Object.assign({}, root.kittyQueue);
        queue[key] = String(value);
        root.kittyQueue = queue;
        root.flushKitty();
    }

    function flushKitty() {
        if (kittyProcess.running)
            return;

        const keys = Object.keys(root.kittyQueue);

        if (keys.length === 0)
            return;

        const key = keys[0];
        const queue = Object.assign({}, root.kittyQueue);
        const value = queue[key];
        delete queue[key];
        root.kittyQueue = queue;

        kittyProcess.command = [root.setKittyPath, key, value];
        kittyProcess.running = true;
    }

    function fontLabel(name) {
        return name.replace("CaskaydiaCove", "Caskaydia").replace("JetBrainsMono", "JetBrains").replace("FantasqueSansM", "Fantasque").replace("IosevkaTerm", "Iosevka");
    }

    function resetCurrentTab() {
        if (root.currentTab === 0) {
            root.resetRequested();
        } else if (root.currentTab === 1) {
            root.setComp(root.compositorDefaults);
        } else {
            for (const key of Object.keys(root.kittyDefaults)) {
                const value = root.kittyDefaults[key];
                root.setKitty(key, key === "background_opacity" ? (value / 100).toFixed(2) : value);
            }
        }

        root.hint = "Reset " + root.tabs[root.currentTab].label + " to defaults";
        hintResetTimer.restart();
    }

    function selectTab(index) {
        if (index < 0 || index >= root.tabs.length || index === root.currentTab)
            return;

        root.previousTab = root.currentTab;
        root.currentTab = index;
        root.hint = "";
    }

    Process {
        id: kittyProcess

        onExited: (exitCode, exitStatus) => root.flushKitty()
    }

    Process {
        id: hyprReloadProcess

        command: ["hyprctl", "reload"]
    }

    FileView {
        id: kittyConfigFile

        path: root.kittyConfigPath
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: root.parseKittyConfig(kittyConfigFile.text())
        onFileChanged: kittyConfigFile.reload()
    }

    Timer {
        id: hintResetTimer

        interval: 2200
        onTriggered: root.hint = ""
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            root.hint = "";
            kittyConfigFile.reload();
            keyScope.forceActiveFocus();
        }
    }

    // ── Building blocks ───────────────────────────────────────────────────

    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: 2
        color: root.faintText
        font.family: root.fontFamily
        font.pixelSize: 9
        font.weight: Font.Bold
        font.letterSpacing: 1.2
    }

    // A card holding rows, hairlines between them.
    component Group: Rectangle {
        id: group

        default property alias rows: groupColumn.data

        Layout.fillWidth: true
        implicitHeight: groupColumn.implicitHeight
        radius: 14
        color: root.cardColor
        border.width: 1
        border.color: root.cardBorder
        clip: true

        ColumnLayout {
            id: groupColumn

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0
        }
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        implicitHeight: 1
        color: root.hairline
    }

    // Shared hover background + hint for every row type.
    component RowBase: Item {
        id: rowBase

        property string hintText: ""
        readonly property bool hovered: rowHover.hovered

        Layout.fillWidth: true
        implicitHeight: root.rowHeight

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 10
            color: "#ffffff"
            opacity: rowBase.hovered ? 0.03 : 0

            Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        HoverHandler {
            id: rowHover

            onHoveredChanged: {
                if (hovered && rowBase.hintText !== "")
                    root.hint = rowBase.hintText;
                else if (!hovered && root.hint === rowBase.hintText)
                    root.hint = "";
            }
        }
    }

    component SwitchRow: RowBase {
        id: switchRow

        required property string label
        property string icon: ""
        required property bool checked

        signal toggled

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            MIcon {
                visible: switchRow.icon !== ""
                name: switchRow.icon
                size: 15
                color: switchRow.checked ? "#e8e8e8" : "#6a6a6a"

                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Text {
                Layout.fillWidth: true
                text: switchRow.label
                color: root.primaryText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Rectangle {
                id: track

                Layout.preferredWidth: 36
                Layout.preferredHeight: 20
                radius: 10
                color: switchRow.checked ? root.accentColor : "#161616"
                border.width: 1
                border.color: switchRow.checked ? root.accentColor : "#2a2a2a"

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }

                Rectangle {
                    width: switchMouse.pressed ? 18 : 14
                    height: 14
                    radius: 7
                    y: 3
                    x: switchRow.checked ? track.width - width - 3 : 3
                    color: switchRow.checked ? "#04140a" : "#6a6a6a"

                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                    Behavior on width { NumberAnimation { duration: 120 } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }
        }

        MouseArea {
            id: switchMouse

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: switchRow.toggled()
        }
    }

    component SliderRow: RowBase {
        id: sliderRow

        required property string label
        required property int from
        required property int to
        property int step: 1
        required property int value
        property string suffix: ""

        signal committed(int value)

        property bool dragging: false
        property real live: value
        readonly property real fraction: (sliderRow.live - sliderRow.from) / (sliderRow.to - sliderRow.from)

        onValueChanged: if (!sliderRow.dragging) sliderRow.live = sliderRow.value

        Behavior on live {
            enabled: !sliderRow.dragging
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        function setFromX(x) {
            const f = Math.max(0, Math.min(1, x / trackArea.width));
            const raw = sliderRow.from + f * (sliderRow.to - sliderRow.from);
            const snapped = Math.round(raw / sliderRow.step) * sliderRow.step;

            if (snapped !== sliderRow.live) {
                sliderRow.live = snapped;

                if (!throttle.running)
                    throttle.start();
            }
        }

        // Applies while dragging, but no more than every 120ms.
        Timer {
            id: throttle

            interval: 120
            onTriggered: sliderRow.committed(Math.round(sliderRow.live))
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            Text {
                Layout.preferredWidth: 92
                text: sliderRow.label
                color: root.primaryText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Item {
                id: trackArea

                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: "#1c1c1c"
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(4, knob.x + knob.width / 2)
                    height: 4
                    radius: 2
                    color: root.accentColor
                    opacity: sliderRow.dragging || sliderRow.hovered ? 1 : 0.75

                    Behavior on opacity { NumberAnimation { duration: 140 } }
                }

                Rectangle {
                    id: knob

                    property real size: sliderRow.dragging ? 18 : (sliderRow.hovered ? 15 : 13)

                    width: size
                    height: size
                    radius: size / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: sliderRow.fraction * (trackArea.width - width)
                    color: "#f2f2f2"
                    border.width: sliderRow.dragging ? 3 : 0
                    border.color: root.accentColor

                    Behavior on size { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                }

                // Value bubble while dragging
                Rectangle {
                    anchors.horizontalCenter: knob.horizontalCenter
                    anchors.bottom: knob.top
                    anchors.bottomMargin: 6
                    width: bubbleLabel.implicitWidth + 12
                    height: 18
                    radius: 6
                    color: root.accentColor
                    opacity: sliderRow.dragging ? 1 : 0
                    scale: sliderRow.dragging ? 1 : 0.6
                    transformOrigin: Item.Bottom

                    Behavior on opacity { NumberAnimation { duration: 130 } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                    Text {
                        id: bubbleLabel

                        anchors.centerIn: parent
                        text: Math.round(sliderRow.live) + sliderRow.suffix
                        color: "#04140a"
                        font.family: root.fontFamily
                        font.features: { "tnum": 1 }
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -6
                    anchors.bottomMargin: -6
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: mouse => {
                        sliderRow.dragging = true;
                        sliderRow.setFromX(mouse.x);
                    }
                    onPositionChanged: mouse => sliderRow.setFromX(mouse.x)
                    onReleased: {
                        throttle.stop();
                        sliderRow.dragging = false;
                        sliderRow.committed(Math.round(sliderRow.live));
                    }
                    // Scroll to nudge by one step.
                    onWheel: wheel => {
                        const next = Math.max(sliderRow.from, Math.min(sliderRow.to, sliderRow.value + (wheel.angleDelta.y > 0 ? sliderRow.step : -sliderRow.step)));
                        if (next !== sliderRow.value)
                            sliderRow.committed(next);
                    }
                }
            }

            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: Math.round(sliderRow.live) + sliderRow.suffix
                color: sliderRow.dragging ? root.accentColor : "#c8c8c8"
                font.family: root.fontFamily
                font.features: { "tnum": 1 }
                font.pixelSize: 11
                font.weight: Font.DemiBold

                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }
    }

    // Segmented control with a pill that slides to the chosen option.
    component SegmentRow: RowBase {
        id: segmentRow

        required property string label
        required property var options
        required property int currentIndex

        signal picked(int index)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 12

            Text {
                Layout.preferredWidth: 92
                text: segmentRow.label
                color: root.primaryText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Rectangle {
                id: segmentTrack

                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 9
                color: "#0d0d0d"
                border.width: 1
                border.color: "#1e1e1e"

                readonly property real cell: (width - 4) / segmentRow.options.length

                Rectangle {
                    visible: segmentRow.currentIndex >= 0
                    y: 2
                    x: 2 + Math.max(0, segmentRow.currentIndex) * segmentTrack.cell
                    width: segmentTrack.cell
                    height: parent.height - 4
                    radius: 7
                    color: "#1f1f1f"
                    border.width: 1
                    border.color: "#2e2e2e"

                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                }

                Row {
                    x: 2
                    y: 2

                    Repeater {
                        model: segmentRow.options

                        Item {
                            required property var modelData
                            required property int index

                            width: segmentTrack.cell
                            height: segmentTrack.height - 4

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: parent.index === segmentRow.currentIndex ? root.primaryText : "#7a7a7a"
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold

                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: segmentRow.picked(parent.index)
                            }
                        }
                    }
                }
            }
        }
    }

    // Wrapping row of pill choices (fonts).
    component ChipRow: RowBase {
        id: chipRow

        required property string label
        required property var options
        required property int currentIndex
        property var labels: null
        property var fontFor: null

        signal picked(int index)

        implicitHeight: chipFlow.implicitHeight + 16

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 12

            Text {
                Layout.preferredWidth: 92
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 5
                text: chipRow.label
                color: root.primaryText
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Flow {
                id: chipFlow

                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: chipRow.options

                    Rectangle {
                        id: chip

                        required property var modelData
                        required property int index

                        readonly property bool selected: index === chipRow.currentIndex

                        width: chipLabel.implicitWidth + 16
                        height: 24
                        radius: 8
                        color: chip.selected ? "#f0f0f0" : (chipMouse.containsMouse ? "#181818" : "#0f0f0f")
                        border.width: 1
                        border.color: chip.selected ? "#f0f0f0" : "#232323"
                        scale: chipMouse.pressed ? 0.92 : 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                        Text {
                            id: chipLabel

                            anchors.centerIn: parent
                            text: chipRow.labels ? chipRow.labels[chip.index] : chip.modelData
                            color: chip.selected ? "#050505" : "#cfcfcf"
                            font.family: chipRow.fontFor ? chipRow.fontFor(chip.modelData) : root.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: chipMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: chipRow.picked(chip.index)
                        }
                    }
                }
            }
        }
    }

    component ActionButton: Rectangle {
        id: action

        required property string icon
        required property string label
        property string hintText: ""

        signal clicked

        Layout.fillWidth: true
        Layout.preferredHeight: 30
        radius: 10
        color: actionMouse.containsMouse ? "#151515" : root.cardColor
        border.width: 1
        border.color: actionMouse.containsMouse ? "#2a2a2a" : root.cardBorder
        scale: actionMouse.pressed ? 0.95 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        Row {
            anchors.centerIn: parent
            spacing: 6

            MIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: action.icon
                size: 13
                color: "#bdbdbd"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: action.label
                color: "#cfcfcf"
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (action.hintText !== "") root.hint = action.hintText
            onExited: if (root.hint === action.hintText) root.hint = ""
            onClicked: action.clicked()
        }
    }

    component HeaderButton: Rectangle {
        id: headerButton

        required property string icon
        property string hintText: ""

        signal clicked

        width: 26
        height: 26
        radius: 9
        color: headerMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
        border.width: 1
        border.color: "#232323"
        scale: headerMouse.pressed ? 0.88 : (headerMouse.containsMouse ? 1.08 : 1)

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

        MIcon {
            id: headerIcon

            anchors.centerIn: parent
            name: headerButton.icon
            size: 13
            color: "#a8a8a8"
        }

        MouseArea {
            id: headerMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (headerButton.hintText !== "") root.hint = headerButton.hintText
            onExited: if (root.hint === headerButton.hintText) root.hint = ""
            onClicked: {
                spin.restart();
                headerButton.clicked();
            }
        }

        RotationAnimation {
            id: spin

            target: headerIcon
            from: 0
            to: headerButton.icon === "restart_alt" ? -360 : 0
            duration: 500
            easing.type: Easing.OutCubic
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    FocusScope {
        id: keyScope

        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.closeRequested()
        Keys.onLeftPressed: root.selectTab(root.currentTab - 1)
        Keys.onRightPressed: root.selectTab(root.currentTab + 1)
        Keys.onPressed: event => {
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
                root.selectTab(event.key - Qt.Key_1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                root.selectTab((root.currentTab + 1) % root.tabs.length);
                event.accepted = true;
            }
        }

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
                    radius: 11
                    color: "#090909"
                    border.width: 1
                    border.color: "#232323"

                    MIcon {
                        anchors.centerIn: parent
                        name: "settings"
                        size: 16
                        color: root.primaryText
                        rotation: root.currentTab * 60

                        Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "Settings"
                        color: root.primaryText
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.tabs[root.currentTab].blurb
                        color: root.secondaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }
                }

                HeaderButton {
                    icon: "restart_alt"
                    hintText: "Reset this tab to defaults"
                    onClicked: root.resetCurrentTab()
                }

                HeaderButton {
                    icon: "close"
                    onClicked: root.closeRequested()
                }
            }

            // Tab bar
            Rectangle {
                id: tabBar

                Layout.fillWidth: true
                Layout.preferredHeight: root.tabBarHeight
                radius: 11
                color: "#0a0a0a"
                border.width: 1
                border.color: "#1c1c1c"

                readonly property real cell: (width - 6) / root.tabs.length

                Rectangle {
                    y: 3
                    x: 3 + root.currentTab * tabBar.cell
                    width: tabBar.cell
                    height: parent.height - 6
                    radius: 8
                    color: "#1d1d1d"
                    border.width: 1
                    border.color: "#2d2d2d"

                    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        width: 14
                        height: 2
                        radius: 1
                        color: root.accentColor
                    }
                }

                Row {
                    x: 3
                    y: 3

                    Repeater {
                        model: root.tabs

                        Item {
                            id: tabItem

                            required property var modelData
                            required property int index

                            readonly property bool active: index === root.currentTab

                            width: tabBar.cell
                            height: tabBar.height - 6

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                MIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: tabItem.modelData.icon
                                    size: 13
                                    color: tabItem.active ? root.primaryText : "#6a6a6a"
                                    scale: tabItem.active ? 1.1 : 1

                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabItem.modelData.label
                                    color: tabItem.active ? root.primaryText : "#7a7a7a"
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold

                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectTab(tabItem.index)
                            }
                        }
                    }
                }
            }

            // Tab pages: the active one slides in from the side it lies on,
            // the others slide out and fade.
            Item {
                id: pages

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    id: islandTab

                    readonly property int tabIndex: 0

                    width: pages.width
                    spacing: 8
                    opacity: root.currentTab === tabIndex ? 1 : 0
                    x: (tabIndex - root.currentTab) * 40
                    visible: opacity > 0.01
                    enabled: root.currentTab === tabIndex

                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                    SectionLabel { text: "APPEARANCE" }

                    Group {
                        SwitchRow {
                            label: "Liquid Glass"
                            icon: "water_drop"
                            hintText: "Real backdrop blur behind every island surface (experimental)"
                            checked: root.liquidGlassEnabled
                            onToggled: root.liquidGlassRequested(!root.liquidGlassEnabled)
                        }

                        Divider {}

                        SegmentRow {
                            label: "Handle"
                            hintText: "What the island looks like at rest"
                            options: ["Strip", "Bump"]
                            currentIndex: root.handleStyle === "strip" ? 0 : 1
                            onPicked: index => root.handleStyleRequested(index === 0 ? "strip" : "bump")
                        }

                        Divider {}

                        ChipRow {
                            label: "Font"
                            hintText: "Font for every island panel"
                            options: root.fontOptions
                            labels: root.fontOptions.map(name => name.replace(" Nerd Font Mono", "").replace(" Pro Display", " Pro"))
                            fontFor: name => name
                            currentIndex: root.fontOptions.indexOf(root.fontFamily)
                            onPicked: index => root.fontFamilyRequested(root.fontOptions[index])
                        }
                    }

                    SectionLabel { text: "SIZE" }

                    Group {
                        SliderRow {
                            label: "Width"
                            hintText: "Width of the island when it peeks open"
                            from: 300
                            to: 520
                            step: 10
                            suffix: " px"
                            value: root.idleWidth
                            onCommitted: value => root.idleWidthRequested(value)
                        }

                        Divider {}

                        SliderRow {
                            label: "Height"
                            hintText: "Height of the island when it peeks open"
                            from: 112
                            to: 180
                            step: 4
                            suffix: " px"
                            value: root.idleHeight
                            onCommitted: value => root.idleHeightRequested(value)
                        }
                    }
                }

                ColumnLayout {
                    id: hyprTab

                    readonly property int tabIndex: 1

                    width: pages.width
                    spacing: 8
                    opacity: root.currentTab === tabIndex ? 1 : 0
                    x: (tabIndex - root.currentTab) * 40
                    visible: opacity > 0.01
                    enabled: root.currentTab === tabIndex

                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                    SectionLabel { text: "LAYOUT" }

                    Group {
                        SegmentRow {
                            label: "Preset"
                            hintText: "Gaps, rounding and border in one go — edge to edge lets the island float over windows"
                            options: root.layoutPresets.map(p => p.label)
                            currentIndex: root.currentPreset
                            onPicked: index => {
                                const p = root.layoutPresets[index];
                                root.setComp({ gaps: p.gaps, rounding: p.rounding, border: p.border });
                            }
                        }

                        Divider {}

                        SliderRow {
                            label: "Gaps"
                            hintText: "Space between windows and around the screen edge"
                            from: 0
                            to: 24
                            suffix: " px"
                            value: root.comp("gaps", 6)
                            onCommitted: value => root.setComp({ gaps: value })
                        }

                        Divider {}

                        SliderRow {
                            label: "Rounding"
                            hintText: "Window corner radius"
                            from: 0
                            to: 24
                            suffix: " px"
                            value: root.comp("rounding", 18)
                            onCommitted: value => root.setComp({ rounding: value })
                        }

                        Divider {}

                        SliderRow {
                            label: "Border"
                            hintText: "Window border width, in the theme's border colour"
                            from: 0
                            to: 6
                            suffix: " px"
                            value: root.comp("border", 0)
                            onCommitted: value => root.setComp({ border: value })
                        }
                    }

                    SectionLabel { text: "EFFECTS" }

                    Group {
                        SliderRow {
                            label: "Opacity"
                            hintText: "Opacity of every window — terminals too (their background only, text stays sharp)"
                            from: 30
                            to: 100
                            step: 5
                            suffix: "%"
                            value: root.comp("opacity", 65)
                            onCommitted: value => root.setComp({ opacity: value })
                        }

                        Divider {}

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 0
                            rowSpacing: 0

                            SwitchRow {
                                label: "HyprGlass"
                                icon: "blur_on"
                                hintText: "HyprGlass plugin: refraction and blur on windows"
                                checked: root.comp("glass", true)
                                onToggled: root.setComp({ glass: !root.comp("glass", true) })
                            }

                            SwitchRow {
                                label: "Blur"
                                icon: "lens_blur"
                                hintText: "Hyprland's own background blur"
                                checked: root.comp("blur", true)
                                onToggled: root.setComp({ blur: !root.comp("blur", true) })
                            }

                            SwitchRow {
                                label: "Animations"
                                icon: "animation"
                                hintText: "Window and workspace animations"
                                checked: root.comp("animations", true)
                                onToggled: root.setComp({ animations: !root.comp("animations", true) })
                            }

                            SwitchRow {
                                label: "Dim inactive"
                                icon: "contrast"
                                hintText: "Darken windows that do not have focus"
                                checked: root.comp("dim", false)
                                onToggled: root.setComp({ dim: !root.comp("dim", false) })
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 8

                        ActionButton {
                            icon: "refresh"
                            label: "Reload Hyprland"
                            hintText: "Re-read every Hyprland config file"
                            onClicked: {
                                hyprReloadProcess.running = false;
                                hyprReloadProcess.running = true;
                                root.hint = "Hyprland reloaded";
                                hintResetTimer.restart();
                            }
                        }

                        ActionButton {
                            icon: "edit_note"
                            label: "Edit config"
                            hintText: "Open ~/.config/hypr in Neovim"
                            onClicked: {
                                Quickshell.execDetached(["kitty", "--directory", Quickshell.env("HOME") + "/.config/hypr", "-e", "nvim", "."]);
                                root.closeRequested();
                            }
                        }
                    }
                }

                ColumnLayout {
                    id: terminalTab

                    readonly property int tabIndex: 2

                    width: pages.width
                    spacing: 8
                    opacity: root.currentTab === tabIndex ? 1 : 0
                    x: (tabIndex - root.currentTab) * 40
                    visible: opacity > 0.01
                    enabled: root.currentTab === tabIndex

                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                    // Live sample in the chosen font, size and opacity.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        radius: 12
                        clip: true
                        border.width: 1
                        border.color: root.cardBorder
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#3a2a4a" }
                            GradientStop { position: 1; color: "#1f3a3a" }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "#121110"
                            opacity: root.kittyOpacity / 100

                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8 + root.kittyPadding * 0.6
                            spacing: 2

                            Behavior on anchors.leftMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            Row {
                                spacing: 0

                                Text {
                                    text: "~/github "
                                    color: "#68a8e4"
                                    font.family: root.kittyFont
                                    font.pixelSize: Math.round(root.kittySize * 1.25)
                                }

                                Text {
                                    text: "❯ "
                                    color: "#98bc37"
                                    font.family: root.kittyFont
                                    font.pixelSize: Math.round(root.kittySize * 1.25)
                                }

                                Text {
                                    text: "echo \"0O 1lI {} => != ≤\""
                                    color: "#fce8c3"
                                    font.family: root.kittyFont
                                    font.pixelSize: Math.round(root.kittySize * 1.25)
                                }

                                // Cursor in the chosen shape
                                Item {
                                    width: Math.round(root.kittySize * 0.8)
                                    height: Math.round(root.kittySize * 1.5)

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: root.kittyCursor === "beam" ? 2 : parent.width
                                        height: root.kittyCursor === "underline" ? 2 : parent.height
                                        color: "#fce8c3"

                                        Behavior on width { NumberAnimation { duration: 160 } }
                                        Behavior on height { NumberAnimation { duration: 160 } }

                                        SequentialAnimation on opacity {
                                            running: terminalTab.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 1; duration: 0 }
                                            PauseAnimation { duration: 550 }
                                            NumberAnimation { to: 0.1; duration: 120 }
                                            PauseAnimation { duration: 450 }
                                            NumberAnimation { to: 1; duration: 120 }
                                        }
                                    }
                                }
                            }

                            Text {
                                text: root.kittyFont + " · " + root.kittySize + "pt"
                                color: "#918175"
                                font.family: root.fontFamily
                                font.pixelSize: 9
                            }
                        }
                    }

                    SectionLabel { text: "TEXT" }

                    Group {
                        ChipRow {
                            label: "Font"
                            hintText: "Terminal font (Nerd Font Mono variants, so prompt icons fit their cells)"
                            options: root.terminalFonts
                            labels: root.terminalFonts.map(name => root.fontLabel(name))
                            fontFor: name => name + " Nerd Font Mono"
                            currentIndex: root.terminalFonts.findIndex(name => root.kittyFont.startsWith(name))
                            onPicked: index => root.setKitty("font_family", root.terminalFonts[index] + " Nerd Font Mono")
                        }

                        Divider {}

                        SliderRow {
                            label: "Size"
                            hintText: "Font size in points"
                            from: 8
                            to: 20
                            suffix: " pt"
                            value: root.kittySize
                            onCommitted: value => root.setKitty("font_size", value)
                        }
                    }

                    SectionLabel { text: "WINDOW" }

                    Group {
                        SliderRow {
                            label: "Padding"
                            hintText: "Space between the text and the window edge"
                            from: 0
                            to: 24
                            suffix: " px"
                            value: root.kittyPadding
                            onCommitted: value => root.setKitty("window_padding_width", value)
                        }

                        Divider {}

                        SegmentRow {
                            label: "Cursor"
                            hintText: "Cursor shape"
                            options: ["Block", "Beam", "Underline"]
                            currentIndex: ["block", "beam", "underline"].indexOf(root.kittyCursor)
                            onPicked: index => root.setKitty("cursor_shape", ["block", "beam", "underline"][index])
                        }

                        Divider {}

                        SwitchRow {
                            label: "Cursor trail"
                            icon: "gesture"
                            hintText: "The smear kitty draws behind a moving cursor"
                            checked: root.kittyTrail
                            onToggled: root.setKitty("cursor_trail", root.kittyTrail ? 0 : 1)
                        }
                    }

                    ActionButton {
                        Layout.topMargin: 2
                        icon: "edit_note"
                        label: "Edit kitty.conf"
                        hintText: "Open kitty.conf in Neovim"
                        onClicked: {
                            Quickshell.execDetached(["kitty", "-e", "nvim", root.kittyConfigPath]);
                            root.closeRequested();
                        }
                    }
                }
            }

            // Hint line: hovered row's explanation, else the key shortcuts.
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: root.hintHeight
                text: root.hint !== "" ? root.hint : "← → or 1–3 switch tabs · scroll a slider to nudge it · Esc closes"
                color: root.hint !== "" ? "#bdbdbd" : root.faintText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                font.family: root.fontFamily
                font.pixelSize: 10

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }
}
