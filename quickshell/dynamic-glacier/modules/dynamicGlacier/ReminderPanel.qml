import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color accentColor: "#f0a860"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int bodyHeight: 310
    readonly property int footerHeight: 16
    readonly property int sectionSpacing: 8
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.bodyHeight + root.sectionSpacing + root.footerHeight

    signal closeRequested
    signal settingsRequested
    // Emitted the instant a reminder's time is up. The shell (DynamicGlacier)
    // turns this into a notification banner + alert sound — this panel only
    // owns the list and the calendar, not how the alert is presented.
    signal reminderFired(string text)

    // Reminders keep ticking via the Timer below even while this panel isn't
    // the visible one, the same way TimerPanel's Pomodoro clock does — every
    // panel is a permanently-instantiated child of IslandContent, just
    // hidden (opacity 0) when inactive, so its own Timers never stop.
    property var reminders: []
    property bool remindersLoaded: false
    property int idCounter: 0
    property real now: Date.now()

    // "list" shows pending reminders; "add" shows the composer (text +
    // calendar + time). Kept as one fixed-height panel (bodyHeight) so
    // switching views never resizes the island — same fix that solved the
    // Timetable panel's day-switch stretching bug.
    property string viewMode: "list"

    readonly property var weekdayLabels: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    readonly property int calendarRows: 6

    property date draftBase: new Date()
    property int viewYear: root.draftBase.getFullYear()
    property int viewMonth: root.draftBase.getMonth()
    property var selectedDate: null // Date at local midnight, or null
    property string draftHours: "00"
    property string draftMinutes: "00"

    function nextId() {
        root.idCounter += 1;
        return Date.now() + "-" + root.idCounter;
    }

    function startOfDay(date) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate());
    }

    // Resets the composer to "30 minutes from now" — a sensible default that
    // is itself already a valid, future reminder, so hitting Confirm with no
    // further input just works.
    function openComposer() {
        const base = new Date(Date.now() + 30 * 60000);

        root.draftBase = base;
        root.viewYear = base.getFullYear();
        root.viewMonth = base.getMonth();
        root.selectedDate = root.startOfDay(base);
        root.draftHours = String(base.getHours()).padStart(2, "0");
        root.draftMinutes = String(base.getMinutes()).padStart(2, "0");
        root.viewMode = "add";
        reminderTextInput.text = "";
        reminderTextInput.forceActiveFocus();
    }

    function closeComposer() {
        root.viewMode = "list";
    }

    function goToMonth(delta) {
        const next = new Date(root.viewYear, root.viewMonth + delta, 1);
        const earliest = root.startOfDay(new Date());

        if (next.getFullYear() < earliest.getFullYear() || (next.getFullYear() === earliest.getFullYear() && next.getMonth() < earliest.getMonth()))
            return;

        root.viewYear = next.getFullYear();
        root.viewMonth = next.getMonth();
    }

    readonly property bool canGoToPreviousMonth: {
        const today = new Date();

        return root.viewYear > today.getFullYear() || (root.viewYear === today.getFullYear() && root.viewMonth > today.getMonth());
    }

    // 42 cells (6x7): null for the leading/trailing blanks outside this
    // month, otherwise a fixed-shape record the day-cell delegate can bind
    // to without ever needing to reach back into root.
    readonly property var calendarCells: {
        const firstOfMonth = new Date(root.viewYear, root.viewMonth, 1);
        const daysInMonth = new Date(root.viewYear, root.viewMonth + 1, 0).getDate();
        const leadingBlanks = firstOfMonth.getDay();
        const today = root.startOfDay(new Date());
        const cells = [];

        for (let i = 0; i < leadingBlanks; i++)
            cells.push(null);

        for (let day = 1; day <= daysInMonth; day++) {
            const date = new Date(root.viewYear, root.viewMonth, day);

            cells.push({
                day: day,
                timestamp: date.getTime(),
                isToday: date.getTime() === today.getTime(),
                isPast: date.getTime() < today.getTime(),
                isSelected: root.selectedDate !== null && date.getTime() === root.selectedDate.getTime()
            });
        }

        while (cells.length < root.calendarRows * 7)
            cells.push(null);

        return cells;
    }

    readonly property string monthLabel: {
        const names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

        return names[root.viewMonth] + " " + root.viewYear;
    }

    readonly property var pendingFireAt: {
        if (!root.selectedDate)
            return null;

        const hours = parseInt(root.draftHours, 10);
        const minutes = parseInt(root.draftMinutes, 10);

        if (!Number.isFinite(hours) || !Number.isFinite(minutes))
            return null;

        return new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), root.selectedDate.getDate(), hours, minutes).getTime();
    }

    readonly property bool canConfirm: reminderTextInput.text.trim() !== "" && root.pendingFireAt !== null && root.pendingFireAt > Date.now()

    function confirmReminder() {
        if (!root.canConfirm)
            return;

        root.reminders = root.reminders.concat([{
            id: root.nextId(),
            text: reminderTextInput.text.trim(),
            fireAt: root.pendingFireAt
        }]).sort((a, b) => a.fireAt - b.fireAt);
        root.saveReminders();
        root.closeComposer();
    }

    function removeReminder(id) {
        root.reminders = root.reminders.filter(reminder => reminder.id !== id);
        root.saveReminders();
    }

    function checkDueReminders() {
        const due = root.reminders.filter(reminder => reminder.fireAt <= root.now);

        if (due.length === 0)
            return;

        root.reminders = root.reminders.filter(reminder => reminder.fireAt > root.now);
        root.saveReminders();

        for (const reminder of due)
            root.reminderFired(reminder.text);
    }

    function formatFireAt(fireAt) {
        const date = new Date(fireAt);
        const hh = String(date.getHours()).padStart(2, "0");
        const mm = String(date.getMinutes()).padStart(2, "0");

        if (root.startOfDay(date).getTime() === root.startOfDay(new Date()).getTime())
            return "Today " + hh + ":" + mm;

        const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

        return names[date.getMonth()] + " " + date.getDate() + " " + hh + ":" + mm;
    }

    function applyRemindersJson(text) {
        try {
            const parsed = JSON.parse(text);

            if (Array.isArray(parsed)) {
                root.reminders = parsed.filter(entry => entry && typeof entry.text === "string" && typeof entry.fireAt === "number").map(entry => ({
                    id: entry.id !== undefined ? entry.id : root.nextId(),
                    text: entry.text,
                    fireAt: entry.fireAt
                }));
            }
        } catch (error) {
        // No saved reminders yet, or the file was hand-edited into something
        // unparseable — either way, start from an empty list.
        }

        root.remindersLoaded = true;
    }

    function saveReminders() {
        if (!root.remindersLoaded)
            return;

        remindersFile.setText(JSON.stringify(root.reminders, null, 2) + "\n");
    }

    readonly property string remindersPath: Quickshell.statePath("reminders.json")
    readonly property string remindersDir: root.remindersPath.slice(0, Math.max(0, root.remindersPath.lastIndexOf("/"))) || "."

    Process {
        running: true
        command: ["mkdir", "-p", root.remindersDir]
    }

    FileView {
        id: remindersFile

        path: root.remindersPath
        preload: true
        printErrors: false
        onLoaded: root.applyRemindersJson(remindersFile.text())
        onLoadFailed: root.remindersLoaded = true
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now();
            root.checkDueReminders();
        }
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            root.viewMode = "list";
            reminderFocusScope.forceActiveFocus();
        }
    }

    FocusScope {
        id: reminderFocusScope

        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: {
            if (root.viewMode === "add")
                root.closeComposer();
            else
                root.closeRequested();
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.panelPadding
            spacing: root.sectionSpacing

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
                        name: "alarm"
                        size: 15
                        color: root.primaryText
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.viewMode === "add" ? "New Reminder" : "Reminders"
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
                    color: modeToggleMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"

                    MIcon {
                        anchors.centerIn: parent
                        name: root.viewMode === "add" ? "arrow_back" : "add"
                        size: 13
                        color: "#999999"
                    }

                    MouseArea {
                        id: modeToggleMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewMode === "add" ? root.closeComposer() : root.openComposer()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 10
                    color: settingsMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"

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

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.bodyHeight

                // --- List view -------------------------------------------------
                Item {
                    anchors.fill: parent
                    visible: root.viewMode === "list"

                    Text {
                        anchors.centerIn: parent
                        visible: root.reminders.length === 0
                        text: "No reminders set"
                        color: root.secondaryText
                        font.family: root.fontFamily
                        font.pixelSize: 12
                    }

                    ListView {
                        anchors.fill: parent
                        visible: root.reminders.length > 0
                        model: root.reminders
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: reminderRow

                            required property var modelData
                            required property int index

                            width: ListView.view ? ListView.view.width : 0
                            height: 32

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: reminderRow.modelData.text
                                    elide: Text.ElideRight
                                    color: root.primaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                }

                                Text {
                                    text: root.formatFireAt(reminderRow.modelData.fireAt)
                                    color: root.accentColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: deleteMouse.containsMouse ? "#1a1a1a" : "transparent"

                                    MIcon {
                                        anchors.centerIn: parent
                                        name: "close"
                                        size: 11
                                        color: "#666666"
                                    }

                                    MouseArea {
                                        id: deleteMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.removeReminder(reminderRow.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Composer (add) view ----------------------------------------
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.viewMode === "add"
                    spacing: root.sectionSpacing

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 8
                        color: "#0a0a0a"
                        border.width: 1
                        border.color: reminderTextInput.activeFocus ? root.accentColor : "#232323"

                        TextInput {
                            id: reminderTextInput

                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            color: root.primaryText
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            clip: true
                            selectByMouse: true

                            Keys.onReturnPressed: root.confirmReminder()
                            Keys.onEnterPressed: root.confirmReminder()

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: reminderTextInput.text === ""
                                text: "Remind me to…"
                                color: "#5f5f5f"
                                font.family: root.fontFamily
                                font.pixelSize: 12
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22

                            Rectangle {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                radius: 6
                                color: prevMonthMouse.containsMouse && root.canGoToPreviousMonth ? "#1a1a1a" : "transparent"
                                opacity: root.canGoToPreviousMonth ? 1 : 0.3

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "chevron_left"
                                    size: 14
                                    color: root.secondaryText
                                }

                                MouseArea {
                                    id: prevMonthMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: root.canGoToPreviousMonth
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.goToMonth(-1)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.monthLabel
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                radius: 6
                                color: nextMonthMouse.containsMouse ? "#1a1a1a" : "transparent"

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "chevron_right"
                                    size: 14
                                    color: root.secondaryText
                                }

                                MouseArea {
                                    id: nextMonthMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.goToMonth(1)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 16
                            spacing: 0

                            Repeater {
                                model: root.weekdayLabels

                                Text {
                                    required property string modelData

                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    color: root.secondaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 7
                            rowSpacing: 2
                            columnSpacing: 0

                            Repeater {
                                model: root.calendarCells

                                Rectangle {
                                    id: dayCell

                                    required property var modelData

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: dayCell.modelData && dayCell.modelData.isSelected ? root.accentColor : (dayCell.modelData && dayMouse.containsMouse && !dayCell.modelData.isPast ? "#1a1a1a" : "transparent")

                                    Text {
                                        anchors.centerIn: parent
                                        visible: dayCell.modelData !== null
                                        text: dayCell.modelData ? dayCell.modelData.day : ""
                                        color: {
                                            if (!dayCell.modelData)
                                                return root.secondaryText;
                                            if (dayCell.modelData.isSelected)
                                                return "#0b0b0b";
                                            if (dayCell.modelData.isPast)
                                                return "#444444";
                                            if (dayCell.modelData.isToday)
                                                return root.accentColor;

                                            return root.primaryText;
                                        }
                                        font.family: root.fontFamily
                                        font.pixelSize: 11
                                        font.weight: dayCell.modelData && dayCell.modelData.isToday ? Font.Bold : Font.Normal
                                    }

                                    MouseArea {
                                        id: dayMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: dayCell.modelData !== null && !dayCell.modelData.isPast
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedDate = new Date(root.viewYear, root.viewMonth, dayCell.modelData.day)
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 32
                            radius: 8
                            color: "#0a0a0a"
                            border.width: 1
                            border.color: hoursInput.activeFocus ? root.accentColor : "#232323"

                            TextInput {
                                id: hoursInput

                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                maximumLength: 2
                                validator: IntValidator {
                                    bottom: 0
                                    top: 23
                                }
                                text: root.draftHours

                                onTextChanged: root.draftHours = text
                                onEditingFinished: text = text.padStart(2, "0")
                                Keys.onReturnPressed: root.confirmReminder()
                                Keys.onEnterPressed: root.confirmReminder()
                            }
                        }

                        Text {
                            text: ":"
                            color: root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 14
                        }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 32
                            radius: 8
                            color: "#0a0a0a"
                            border.width: 1
                            border.color: minutesFieldInput.activeFocus ? root.accentColor : "#232323"

                            TextInput {
                                id: minutesFieldInput

                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                maximumLength: 2
                                validator: IntValidator {
                                    bottom: 0
                                    top: 59
                                }
                                text: root.draftMinutes

                                onTextChanged: root.draftMinutes = text
                                onEditingFinished: text = text.padStart(2, "0")
                                Keys.onReturnPressed: root.confirmReminder()
                                Keys.onEnterPressed: root.confirmReminder()
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 32
                            radius: 8
                            color: root.canConfirm ? (confirmMouse.containsMouse ? "#c98f4d" : root.accentColor) : "#151515"
                            border.width: 1
                            border.color: root.canConfirm ? root.accentColor : "#232323"

                            Text {
                                anchors.centerIn: parent
                                text: "Set Reminder"
                                color: root.canConfirm ? "#0b0b0b" : "#555555"
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: confirmMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.canConfirm
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmReminder()
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: root.footerHeight
                horizontalAlignment: Text.AlignRight
                text: root.viewMode === "list" ? (root.reminders.length === 0 ? "" : root.reminders.length + (root.reminders.length === 1 ? " reminder" : " reminders")) : (root.canConfirm ? "" : "Pick a future date and time")
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 10
            }
        }
    }
}
