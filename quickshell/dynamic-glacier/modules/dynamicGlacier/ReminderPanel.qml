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
    readonly property color mutedText: "#444444"
    readonly property color accentColor: "#4ade80"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int sectionSpacing: 6
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // --- Calendar geometry ------------------------------------------------
    readonly property int monthHeaderHeight: 22
    readonly property int weekdayHeaderHeight: 16
    readonly property int calendarRowGap: 2
    readonly property int dayCellHeight: 27
    readonly property int calendarRows: 6
    readonly property real contentWidth: root.width - root.panelPadding * 2
    readonly property real dayCellWidth: root.contentWidth / 7
    readonly property real calendarHeight: root.monthHeaderHeight + root.calendarRowGap + root.weekdayHeaderHeight + root.calendarRowGap + root.calendarRows * root.dayCellHeight

    // --- Agenda (selected day's reminders) --------------------------------
    readonly property int agendaLabelHeight: 16
    readonly property int agendaRowHeight: 25
    readonly property int agendaMaxVisible: 2
    readonly property real agendaHeight: root.agendaLabelHeight + 4 + root.agendaRowHeight * root.agendaMaxVisible

    readonly property int addRowHeight: 30

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.calendarHeight + root.sectionSpacing + root.agendaHeight + root.sectionSpacing + root.addRowHeight

    signal closeRequested
    signal settingsRequested
    // Emitted the instant a reminder's time is up. The shell (DynamicGlacier)
    // turns this into a notification banner + alert sound — this panel only
    // owns the calendar and the list.
    signal reminderFired(string text)

    // Reminders keep ticking via the Timer below even while this panel isn't
    // the visible one, the same way TimerPanel's Pomodoro clock does — every
    // panel is a permanently-instantiated child of IslandContent, just
    // hidden (opacity 0) when inactive, so its own Timers never stop.
    property var reminders: []
    property bool remindersLoaded: false
    property int idCounter: 0
    property real now: Date.now()

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var weekdayLabels: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property var selectedDate: root.startOfDay(new Date())

    property string draftText: ""
    property string draftTime: "09:00"

    function nextId() {
        root.idCounter += 1;
        return Date.now() + "-" + root.idCounter;
    }

    function startOfDay(date) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate());
    }

    function goToMonth(delta) {
        const next = new Date(root.viewYear, root.viewMonth + delta, 1);

        root.viewYear = next.getFullYear();
        root.viewMonth = next.getMonth();
    }

    function goToToday() {
        const today = new Date();

        root.viewYear = today.getFullYear();
        root.viewMonth = today.getMonth();
        root.selectedDate = root.startOfDay(today);
    }

    function selectDay(day) {
        root.selectedDate = new Date(root.viewYear, root.viewMonth, day);
    }

    // 42 cells (6x7): null for the leading/trailing blanks outside this
    // month, otherwise a fixed-shape record the day-cell delegate binds to.
    readonly property var calendarCells: {
        const firstOfMonth = new Date(root.viewYear, root.viewMonth, 1);
        const daysInMonth = new Date(root.viewYear, root.viewMonth + 1, 0).getDate();
        // getDay() is 0=Sunday..6=Saturday; shift so the grid's first column
        // is Monday (0) and Sunday becomes the last column (6).
        const leadingBlanks = (firstOfMonth.getDay() + 6) % 7;
        const today = root.startOfDay(new Date());
        const cells = [];

        for (let i = 0; i < leadingBlanks; i++)
            cells.push(null);

        for (let day = 1; day <= daysInMonth; day++) {
            const date = new Date(root.viewYear, root.viewMonth, day);
            const timestamp = date.getTime();

            cells.push({
                day: day,
                isToday: timestamp === today.getTime(),
                isSelected: root.selectedDate !== null && timestamp === root.selectedDate.getTime(),
                hasReminder: root.reminders.some(reminder => root.startOfDay(new Date(reminder.fireAt)).getTime() === timestamp)
            });
        }

        while (cells.length < root.calendarRows * 7)
            cells.push(null);

        return cells;
    }

    readonly property string monthLabel: root.monthNames[root.viewMonth] + " " + root.viewYear

    readonly property var selectedDayReminders: root.reminders.filter(reminder => root.startOfDay(new Date(reminder.fireAt)).getTime() === root.selectedDate.getTime()).sort((a, b) => a.fireAt - b.fireAt)

    readonly property string selectedDateLabel: {
        const today = root.startOfDay(new Date());

        if (root.selectedDate.getTime() === today.getTime())
            return "Today";

        const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

        return names[root.selectedDate.getDay()] + ", " + root.monthNames[root.selectedDate.getMonth()] + " " + root.selectedDate.getDate();
    }

    // Accepts "H:MM" or "HH:MM"; returns {hours, minutes} or null.
    function parseTime(text) {
        const match = /^([0-9]{1,2}):([0-9]{2})$/.exec((text || "").trim());

        if (!match)
            return null;

        const hours = parseInt(match[1], 10);
        const minutes = parseInt(match[2], 10);

        if (hours > 23 || minutes > 59)
            return null;

        return {
            hours: hours,
            minutes: minutes
        };
    }

    readonly property var parsedDraftTime: root.parseTime(root.draftTime)

    readonly property var pendingFireAt: {
        if (!root.parsedDraftTime)
            return null;

        return new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), root.selectedDate.getDate(), root.parsedDraftTime.hours, root.parsedDraftTime.minutes).getTime();
    }

    readonly property bool canConfirm: root.draftText.trim() !== "" && root.pendingFireAt !== null && root.pendingFireAt > Date.now()

    function confirmReminder() {
        if (!root.canConfirm)
            return;

        root.reminders = root.reminders.concat([{
            id: root.nextId(),
            text: root.draftText.trim(),
            fireAt: root.pendingFireAt
        }]).sort((a, b) => a.fireAt - b.fireAt);
        root.saveReminders();
        root.draftText = "";
        reminderTextInput.text = "";
        reminderTextInput.forceActiveFocus();
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
            root.goToToday();
            reminderFocusScope.forceActiveFocus();
        }
    }

    FocusScope {
        id: reminderFocusScope

        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.closeRequested()

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
                    text: "Reminders"
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

            // --- Calendar --------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.calendarHeight
                spacing: root.calendarRowGap

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.monthHeaderHeight

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 7
                        color: prevMonthMouse.containsMouse ? "#1a1a1a" : "transparent"

                        MIcon {
                            anchors.centerIn: parent
                            name: "chevron_left"
                            size: 15
                            color: root.secondaryText
                        }

                        MouseArea {
                            id: prevMonthMouse

                            anchors.fill: parent
                            hoverEnabled: true
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
                        font.pixelSize: 13
                        font.weight: Font.DemiBold

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goToToday()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 7
                        color: nextMonthMouse.containsMouse ? "#1a1a1a" : "transparent"

                        MIcon {
                            anchors.centerIn: parent
                            name: "chevron_right"
                            size: 15
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

                Row {
                    Layout.preferredWidth: root.contentWidth
                    Layout.preferredHeight: root.weekdayHeaderHeight

                    Repeater {
                        model: root.weekdayLabels

                        Text {
                            required property string modelData

                            width: root.dayCellWidth
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Grid {
                    Layout.preferredWidth: root.contentWidth
                    Layout.preferredHeight: root.calendarRows * root.dayCellHeight
                    columns: 7

                    Repeater {
                        model: root.calendarCells

                        Item {
                            id: dayCell

                            required property var modelData

                            width: root.dayCellWidth
                            height: root.dayCellHeight

                            Rectangle {
                                id: selectionRing

                                anchors.centerIn: parent
                                width: Math.min(parent.width, parent.height) - 6
                                height: width
                                radius: width / 2
                                color: dayCell.modelData && dayCell.modelData.isSelected ? root.accentColor : "transparent"
                                border.width: dayCell.modelData && dayCell.modelData.isToday && !dayCell.modelData.isSelected ? 1 : 0
                                border.color: root.accentColor

                                Text {
                                    anchors.centerIn: parent
                                    visible: dayCell.modelData !== null
                                    text: dayCell.modelData ? dayCell.modelData.day : ""
                                    color: {
                                        if (!dayCell.modelData)
                                            return root.secondaryText;
                                        if (dayCell.modelData.isSelected)
                                            return "#0b0b0b";
                                        if (dayCell.modelData.isToday)
                                            return root.accentColor;

                                        return root.primaryText;
                                    }
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.weight: dayCell.modelData && (dayCell.modelData.isSelected || dayCell.modelData.isToday) ? Font.Bold : Font.Normal
                                }
                            }

                            Rectangle {
                                visible: dayCell.modelData !== null && dayCell.modelData.hasReminder && !dayCell.modelData.isSelected
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: selectionRing.bottom
                                anchors.topMargin: 1
                                width: 3
                                height: 3
                                radius: 1.5
                                color: root.accentColor
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: dayCell.modelData !== null
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectDay(dayCell.modelData.day)
                            }
                        }
                    }
                }
            }

            // --- Agenda for the selected day --------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.agendaHeight
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: root.selectedDateLabel
                    color: root.secondaryText
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: root.selectedDayReminders.length === 0
                        text: "No reminders"
                        color: root.mutedText
                        font.family: root.fontFamily
                        font.pixelSize: 11
                    }

                    ListView {
                        anchors.fill: parent
                        visible: root.selectedDayReminders.length > 0
                        model: root.selectedDayReminders
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: reminderRow

                            required property var modelData
                            required property int index

                            width: ListView.view ? ListView.view.width : 0
                            height: root.agendaRowHeight

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Text {
                                    text: {
                                        const date = new Date(reminderRow.modelData.fireAt);

                                        return String(date.getHours()).padStart(2, "0") + ":" + String(date.getMinutes()).padStart(2, "0");
                                    }
                                    color: root.accentColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: reminderRow.modelData.text
                                    elide: Text.ElideRight
                                    color: root.primaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
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
            }

            // --- Quick add: always adds to the selected day -----------------
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.addRowHeight
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.addRowHeight
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

                        onTextChanged: root.draftText = text
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

                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: root.addRowHeight
                    radius: 8
                    color: "#0a0a0a"
                    border.width: 1
                    border.color: timeInput.activeFocus ? root.accentColor : (root.parsedDraftTime ? "#232323" : "#4a2a2a")

                    TextInput {
                        id: timeInput

                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.primaryText
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        maximumLength: 5
                        text: root.draftTime

                        onTextChanged: root.draftTime = text
                        Keys.onReturnPressed: root.confirmReminder()
                        Keys.onEnterPressed: root.confirmReminder()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: root.addRowHeight
                    Layout.preferredHeight: root.addRowHeight
                    radius: 8
                    color: root.canConfirm ? (addMouse.containsMouse ? "#3fc26f" : root.accentColor) : "#151515"
                    border.width: 1
                    border.color: root.canConfirm ? root.accentColor : "#232323"

                    MIcon {
                        anchors.centerIn: parent
                        name: "add"
                        size: 16
                        color: root.canConfirm ? "#0b0b0b" : "#555555"
                    }

                    MouseArea {
                        id: addMouse

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
}
