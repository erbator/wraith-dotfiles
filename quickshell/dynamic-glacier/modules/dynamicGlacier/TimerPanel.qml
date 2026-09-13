import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color accentColor: "#4ade80"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int tabsHeight: 28
    readonly property int statusRowHeight: 18
    readonly property int countdownHeight: 60
    readonly property int buttonsRowHeight: 40
    readonly property int sectionSpacing: 10
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.tabsHeight + root.sectionSpacing + root.statusRowHeight + root.sectionSpacing + root.countdownHeight + root.sectionSpacing + root.buttonsRowHeight

    signal closeRequested
    signal settingsRequested
    // Emitted every time a Pomodoro phase ends and the next one starts —
    // the shell (DynamicGlacier) turns this into a notification banner +
    // alert sound, same as a reminder firing.
    signal phaseCompleted(string label)

    readonly property var tabLabels: ["Pomodoro", "Stopwatch"]

    // "pomodoro" or "stopwatch" — which tab is on screen. Both timers below
    // keep ticking regardless of which one is showing, same as a phone.
    property string activeTab: "pomodoro"

    readonly property int workSeconds: 25 * 60
    readonly property int shortBreakSeconds: 5 * 60
    readonly property int longBreakSeconds: 15 * 60
    readonly property int cyclesBeforeLongBreak: 4

    property string pomodoroPhase: "work" // "work" | "short" | "long"
    property int pomodoroRemaining: root.workSeconds
    property bool pomodoroRunning: false
    // Completed work sessions in the current cycle (0..cyclesBeforeLongBreak-1).
    property int pomodoroCompleted: 0

    property int stopwatchSeconds: 0
    property bool stopwatchRunning: false

    function pomodoroPhaseDuration(phase) {
        switch (phase) {
        case "short":
            return root.shortBreakSeconds;
        case "long":
            return root.longBreakSeconds;
        default:
            return root.workSeconds;
        }
    }

    function pomodoroPhaseLabel(phase) {
        switch (phase) {
        case "short":
            return "SHORT BREAK";
        case "long":
            return "LONG BREAK";
        default:
            return "WORK";
        }
    }

    // Cycles work -> break -> work forever, taking the long break every
    // `cyclesBeforeLongBreak` work sessions. Runs continuously across phases
    // rather than pausing at each boundary, so it behaves like a background
    // timer instead of something that needs a click every 25 minutes.
    function advancePomodoroPhase() {
        if (root.pomodoroPhase === "work") {
            root.pomodoroCompleted += 1;
            root.pomodoroPhase = root.pomodoroCompleted >= root.cyclesBeforeLongBreak ? "long" : "short";
        } else {
            // Only the long break's end starts a new cycle — wrapping the
            // counter back to 0 as soon as the 4th work session finished
            // (instead of when the break after it ends) made the dot
            // tracker show 0/4 progress during the break you'd just earned.
            if (root.pomodoroPhase === "long")
                root.pomodoroCompleted = 0;

            root.pomodoroPhase = "work";
        }

        root.pomodoroRemaining = root.pomodoroPhaseDuration(root.pomodoroPhase);
    }

    function tickPomodoro() {
        root.pomodoroRemaining -= 1;

        if (root.pomodoroRemaining <= 0) {
            root.advancePomodoroPhase();
            // Only a natural, tick-to-zero completion alerts — Skip is the
            // user acting themselves, they don't need to be told about it.
            root.phaseCompleted(root.pomodoroPhaseLabel(root.pomodoroPhase));
        }
    }

    function togglePomodoro() {
        root.pomodoroRunning = !root.pomodoroRunning;
    }

    // Restarts the current phase's clock without discarding cycle progress —
    // matches Reset on the Stopwatch tab only zeroing the running number, not
    // wiping state a click shouldn't touch.
    function resetPomodoro() {
        root.pomodoroRunning = false;
        root.pomodoroRemaining = root.pomodoroPhaseDuration(root.pomodoroPhase);
    }

    function toggleStopwatch() {
        root.stopwatchRunning = !root.stopwatchRunning;
    }

    function resetStopwatch() {
        root.stopwatchRunning = false;
        root.stopwatchSeconds = 0;
    }

    function toggleActiveTimer() {
        if (root.activeTab === "pomodoro")
            root.togglePomodoro();
        else
            root.toggleStopwatch();
    }

    function resetActiveTimer() {
        if (root.activeTab === "pomodoro")
            root.resetPomodoro();
        else
            root.resetStopwatch();
    }

    readonly property bool activeTimerRunning: root.activeTab === "pomodoro" ? root.pomodoroRunning : root.stopwatchRunning

    function pad2(value) {
        return value < 10 ? "0" + value : String(value);
    }

    function formatMMSS(totalSeconds) {
        const s = Math.max(0, totalSeconds);
        return root.pad2(Math.floor(s / 60)) + ":" + root.pad2(s % 60);
    }

    function formatHMS(totalSeconds) {
        const s = Math.max(0, totalSeconds);
        const h = Math.floor(s / 3600);

        if (h <= 0)
            return root.formatMMSS(s);

        return h + ":" + root.pad2(Math.floor((s % 3600) / 60)) + ":" + root.pad2(s % 60);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.pomodoroRunning
        onTriggered: root.tickPomodoro()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.stopwatchRunning
        onTriggered: root.stopwatchSeconds += 1
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible)
            timerFocusScope.forceActiveFocus();
    }

    FocusScope {
        id: timerFocusScope

        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: root.activeTab = "pomodoro"
        Keys.onRightPressed: root.activeTab = "stopwatch"
        Keys.onSpacePressed: root.toggleActiveTimer()
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
                        name: "timer"
                        size: 15
                        color: root.primaryText
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Timer"
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

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tabsHeight
                spacing: 6

                Repeater {
                    model: root.tabLabels

                    Rectangle {
                        id: timerTab

                        required property string modelData
                        required property int index

                        readonly property string tabId: index === 0 ? "pomodoro" : "stopwatch"
                        readonly property bool selected: root.activeTab === tabId
                        readonly property bool tabRunning: tabId === "pomodoro" ? root.pomodoroRunning : root.stopwatchRunning

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: timerTab.selected ? "#1c2f22" : (tabMouse.containsMouse ? "#161616" : "#0a0a0a")
                        border.width: 1
                        border.color: timerTab.selected ? root.accentColor : "#232323"

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5

                            Rectangle {
                                visible: timerTab.tabRunning
                                Layout.preferredWidth: 5
                                Layout.preferredHeight: 5
                                radius: 2.5
                                color: root.accentColor
                            }

                            Text {
                                text: timerTab.modelData
                                color: timerTab.selected ? root.accentColor : root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: tabMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeTab = timerTab.tabId
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.statusRowHeight
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.activeTab === "pomodoro" ? root.pomodoroPhaseLabel(root.pomodoroPhase) : "ELAPSED"
                    color: root.secondaryText
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }

                Row {
                    visible: root.activeTab === "pomodoro"
                    spacing: 4

                    Repeater {
                        model: root.cyclesBeforeLongBreak

                        Rectangle {
                            required property int index

                            width: 6
                            height: 6
                            radius: 3
                            color: index < root.pomodoroCompleted ? root.accentColor : "#2a2a2a"
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.countdownHeight

                Text {
                    anchors.centerIn: parent
                    text: root.activeTab === "pomodoro" ? root.formatMMSS(root.pomodoroRemaining) : root.formatHMS(root.stopwatchSeconds)
                    color: root.activeTimerRunning ? root.accentColor : root.primaryText
                    font.family: root.fontFamily
                    font.features: { "tnum": 1 }
                    font.pixelSize: 40
                    font.weight: Font.Bold
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.buttonsRowHeight
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: root.buttonsRowHeight
                    Layout.preferredHeight: root.buttonsRowHeight
                    radius: 10
                    color: resetMouse.containsMouse ? "#161616" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"

                    MIcon {
                        anchors.centerIn: parent
                        name: "refresh"
                        size: 16
                        color: root.secondaryText
                    }

                    MouseArea {
                        id: resetMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetActiveTimer()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.buttonsRowHeight
                    radius: 10
                    color: root.activeTimerRunning ? "#12271a" : (playMouse.containsMouse ? "#161616" : "#0a0a0a")
                    border.width: 1
                    border.color: root.activeTimerRunning ? root.accentColor : "#232323"

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MIcon {
                            name: root.activeTimerRunning ? "pause" : "play_arrow"
                            size: 16
                            color: root.activeTimerRunning ? root.accentColor : root.primaryText
                        }

                        Text {
                            text: root.activeTimerRunning ? "Pause" : "Start"
                            color: root.activeTimerRunning ? root.accentColor : root.primaryText
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: playMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleActiveTimer()
                    }
                }

                Rectangle {
                    visible: root.activeTab === "pomodoro"
                    Layout.preferredWidth: root.buttonsRowHeight
                    Layout.preferredHeight: root.buttonsRowHeight
                    radius: 10
                    color: skipMouse.containsMouse ? "#161616" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"

                    MIcon {
                        anchors.centerIn: parent
                        name: "skip_next"
                        size: 16
                        color: root.secondaryText
                    }

                    MouseArea {
                        id: skipMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.advancePomodoroPhase()
                    }
                }
            }
        }
    }
}
