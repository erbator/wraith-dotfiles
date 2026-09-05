import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color accentColor: "#4ade80"
    readonly property color noteColor: "#f87171"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int tabsHeight: 28
    readonly property int rowHeight: 36
    readonly property int rowSpacing: 6
    readonly property int sectionSpacing: 10
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // Sized to the busiest day (not the currently selected one) so the panel
    // never resizes when switching tabs — only the row list's own content
    // changes. Days with fewer blocks just leave a little empty space at the
    // bottom instead of growing/shrinking the whole surface on every switch,
    // which is what caused the visible "stretch" when the block count changed.
    readonly property int maxBlocksPerDay: root.schedule.reduce((max, day) => Math.max(max, day.length), 0)
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.tabsHeight + root.sectionSpacing + root.maxBlocksPerDay * root.rowHeight + Math.max(0, root.maxBlocksPerDay - 1) * root.rowSpacing

    signal closeRequested
    signal settingsRequested

    // Bell schedule: index = period number (0-8), [start, end].
    readonly property var bellTimes: [
        ["7:20", "8:05"],
        ["8:15", "9:00"],
        ["9:10", "9:55"],
        ["10:10", "10:55"],
        ["11:05", "11:50"],
        ["12:00", "12:45"],
        ["12:55", "13:40"],
        ["14:10", "14:55"],
        ["15:00", "15:45"]
    ]

    readonly property var dayLabels: ["H", "K", "SZ", "CS", "P"]

    // One entry per weekday (Monday-Friday), each a list of class blocks in
    // period order. A block's "p" range is inclusive and covers merged cells
    // (e.g. a double lab period), matching how the printed timetable groups them.
    readonly property var schedule: [
        [
            { p: [2, 2], subject: "Történelem", meta: "KA" },
            { p: [3, 3], subject: "Hálózatok I. 11.t", meta: "K.O · 2. terem" },
            { p: [4, 4], subject: "Matematika", meta: "" },
            { p: [5, 5], subject: "Magyar", meta: "NL" },
            { p: [6, 6], subject: "IKT Projektmunka II. 11.t", meta: "BAM · 2. terem" },
            { p: [7, 8], subject: "Hálózatok I. 11.t/1", meta: "K.O · 31. terem" }
        ],
        [
            { p: [1, 2], subject: "Testnevelés", meta: "TT", note: "GAMF" },
            { p: [3, 3], subject: "Angol 11 tim", meta: "" },
            { p: [4, 4], subject: "Matematika", meta: "" },
            { p: [5, 5], subject: "Fizika", meta: "BI" },
            { p: [6, 6], subject: "Magyar", meta: "NL" },
            { p: [7, 8], subject: "Hálózatok I. 11.t/2", meta: "K.O · 31. terem" }
        ],
        [
            { p: [1, 1], subject: "Matematika", meta: "" },
            { p: [2, 2], subject: "Történelem", meta: "KA" },
            { p: [3, 3], subject: "Magyar", meta: "NL" },
            { p: [4, 4], subject: "Fizika", meta: "BI" },
            { p: [5, 5], subject: "Szakmai angol 11t", meta: "M.G · 2. terem" },
            { p: [6, 6], subject: "Hálózatok I. 11.t", meta: "K.O · 31. terem" },
            { p: [7, 8], subject: "Hálózatok I. 11.t/1", meta: "K.O · 31. terem" }
        ],
        [
            { p: [1, 1], subject: "Matematika", meta: "" },
            { p: [2, 2], subject: "Hálózatok I. 11.t", meta: "K.O · 35. terem" },
            { p: [3, 4], subject: "Adatbázis-kezelés I. 11.t", meta: "A.P · 2. terem" },
            { p: [5, 6], subject: "Angol 11 tim", meta: "" },
            { p: [7, 8], subject: "Hálózatok I. 11.t/2", meta: "K.O · 31. terem" }
        ],
        [
            { p: [0, 0], subject: "Angol 11 tim", meta: "", note: "!!!" },
            { p: [1, 1], subject: "Szakmai angol 11t", meta: "MG" },
            { p: [2, 2], subject: "Töri", meta: "KA" },
            { p: [3, 3], subject: "Magyar", meta: "NL" },
            { p: [4, 5], subject: "Adatbázis-kezelés I. 11.t", meta: "A.P · 2. terem" },
            { p: [6, 6], subject: "OF", meta: "KA" },
            { p: [7, 8], subject: "Testnevelés", meta: "TT", note: "GAMF" }
        ]
    ]

    // 0 = Monday .. 4 = Friday, -1 on a weekend (nothing to highlight).
    readonly property int todayIndex: {
        const jsDay = liveClock.now.getDay();
        return jsDay >= 1 && jsDay <= 5 ? jsDay - 1 : -1;
    }

    property int selectedDayIndex: 0
    readonly property var dayBlocks: root.schedule[root.selectedDayIndex]

    function timeToMinutes(text) {
        const parts = text.split(":");
        return Number(parts[0]) * 60 + Number(parts[1]);
    }

    // Index of the block currently in progress, or -1. Only ever non-negative
    // for the tab that also matches today, so switching days never leaves a
    // stale "now" highlight behind.
    function activeBlockIndex(dayIndex) {
        if (dayIndex !== root.todayIndex)
            return -1;

        const nowMinutes = liveClock.now.getHours() * 60 + liveClock.now.getMinutes();
        const blocks = root.schedule[dayIndex];

        for (let i = 0; i < blocks.length; i++) {
            const block = blocks[i];
            const start = root.timeToMinutes(root.bellTimes[block.p[0]][0]);
            const end = root.timeToMinutes(root.bellTimes[block.p[1]][1]);

            if (nowMinutes >= start && nowMinutes < end)
                return i;
        }

        return -1;
    }

    function periodLabel(block) {
        return block.p[0] === block.p[1] ? (block.p[0] + ".") : (block.p[0] + "-" + block.p[1] + ".");
    }

    function timeLabel(block) {
        return root.bellTimes[block.p[0]][0] + "–" + root.bellTimes[block.p[1]][1];
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    // Re-picks today's tab and re-grabs focus on every open, same as
    // WallpaperPanel/CalculatorPanel — this panel is instantiated once at
    // startup, long before it is ever shown for the first time.
    onVisibleChanged: {
        if (root.visible) {
            root.selectedDayIndex = root.todayIndex >= 0 ? root.todayIndex : 0;
            timetableFocusScope.forceActiveFocus();
        }
    }

    function moveDayHighlight(delta) {
        root.selectedDayIndex = Math.max(0, Math.min(root.dayLabels.length - 1, root.selectedDayIndex + delta));
    }

    Timer {
        id: liveClock

        property date now: new Date()

        interval: 30000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: now = new Date()
    }

    FocusScope {
        id: timetableFocusScope

        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: root.moveDayHighlight(-1)
        Keys.onRightPressed: root.moveDayHighlight(1)
        Keys.onEscapePressed: root.closeRequested()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.panelPadding
            spacing: root.sectionSpacing
            // The surface's own height Behavior (in IslandSurface.qml) animates
            // toward a longer day's row count, but Qt Quick Layouts don't clip
            // overflow — without this, the rows for the longer day render at
            // full size immediately and visibly poke out past the still-catching-up
            // background shape, reading as the panel "stretching" oddly.
            clip: true

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
                        name: "calendar_month"
                        size: 15
                        color: root.primaryText
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Órarend"
                    color: root.primaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 10
                    color: settingsMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"
                    scale: settingsMouse.pressed ? 0.86 : (settingsMouse.containsMouse ? 1.1 : 1)

                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }

                    MIcon {
                        anchors.centerIn: parent
                        name: "settings"
                        size: 12
                        color: "#999999"
                    }

                    MouseArea {
                        id: settingsMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.settingsRequested()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 10
                    color: closeMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"
                    scale: closeMouse.pressed ? 0.86 : (closeMouse.containsMouse ? 1.1 : 1)

                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }

                    MIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: 12
                        color: "#999999"
                    }

                    MouseArea {
                        id: closeMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tabsHeight
                spacing: 6

                Repeater {
                    model: root.dayLabels

                    Rectangle {
                        id: dayTab

                        required property string modelData
                        required property int index

                        readonly property bool selected: index === root.selectedDayIndex
                        readonly property bool isToday: index === root.todayIndex

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: dayTab.selected ? "#1c2f22" : (dayMouse.containsMouse ? "#161616" : "#0a0a0a")
                        border.width: 1
                        border.color: dayTab.selected ? root.accentColor : "#232323"

                        Text {
                            anchors.centerIn: parent
                            text: dayTab.modelData
                            color: dayTab.selected ? root.accentColor : root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            visible: dayTab.isToday
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 4
                            height: 4
                            radius: 2
                            color: dayTab.selected ? root.accentColor : root.secondaryText
                        }

                        MouseArea {
                            id: dayMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedDayIndex = dayTab.index
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.rowSpacing

                Repeater {
                    model: root.dayBlocks

                    Rectangle {
                        id: blockRow

                        required property var modelData
                        required property int index

                        readonly property bool isNow: index === root.activeBlockIndex(root.selectedDayIndex)

                        Layout.fillWidth: true
                        Layout.preferredHeight: root.rowHeight
                        radius: 9
                        color: blockRow.isNow ? "#12271a" : "#0a0a0a"
                        border.width: 1
                        border.color: blockRow.isNow ? root.accentColor : "#1c1c1c"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            ColumnLayout {
                                Layout.preferredWidth: 58
                                spacing: 0

                                Text {
                                    text: root.periodLabel(blockRow.modelData)
                                    color: blockRow.isNow ? root.accentColor : root.primaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                Text {
                                    text: root.timeLabel(blockRow.modelData)
                                    color: root.secondaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: blockRow.modelData.subject
                                        color: root.primaryText
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        visible: !!blockRow.modelData.note
                                        text: blockRow.modelData.note ?? ""
                                        color: root.noteColor
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: blockRow.modelData.meta !== ""
                                    text: blockRow.modelData.meta
                                    color: root.secondaryText
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
