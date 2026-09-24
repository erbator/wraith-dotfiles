import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// Focus (Pomodoro), a countdown Timer and a Stopwatch, sharing one progress
// ring on the left; the right side swaps per tab.
//
// Every clock is timestamp-based (an end time or a start time, never a
// counter bumped once a second), so they stay exact while the panel is
// closed, across suspend, and across shell restarts: state is kept in
// ~/.local/share/dynamic-glacier/timer.json.
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested
    // A Focus phase ended or the countdown ran out; the shell shows it as an
    // AlertBanner (+ the alert sound) and routes its buttons back to
    // handleAlertAction().
    signal alertRequested(var alert)

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"
    readonly property color hairline: "#141414"

    readonly property color focusColor: "#4ade80"
    readonly property color breakColor: "#5eead4"
    readonly property color countdownColor: "#fbbf24"
    readonly property color stopwatchColor: "#93c5fd"
    readonly property color doneColor: "#f87171"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int tabBarHeight: 32
    readonly property int bodyHeight: 176
    readonly property int controlsHeight: 40
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 12
    readonly property int ringSize: 172

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.tabBarHeight + root.bodyHeight + root.controlsHeight + root.hintHeight + root.sectionSpacing * 4
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property var tabs: [
        { label: "Focus", icon: "adjust" },
        { label: "Timer", icon: "hourglass_top" },
        { label: "Stopwatch", icon: "timer" }
    ]

    property int currentTab: 0
    property real now: Date.now()

    // ── Focus ─────────────────────────────────────────────────────────────
    property int workMin: 25
    property int shortMin: 5
    property int longMin: 15
    property int cycles: 4
    property bool autoStart: true

    property string phase: "work" // "work" | "short" | "long"
    property int completed: 0 // finished work sessions in this cycle
    property string focusTask: "" // set by the To-do panel's "focus on this"
    property bool focusRunning: false
    property real focusEndsAt: 0
    property real focusTotalMs: root.workMin * 60000
    property real focusRemainingMs: root.workMin * 60000
    readonly property real focusLeftMs: root.focusRunning ? Math.max(0, root.focusEndsAt - root.now) : root.focusRemainingMs
    readonly property bool focusPristine: !root.focusRunning && root.focusRemainingMs === root.focusTotalMs

    property string statsDate: ""
    property int statsSessions: 0
    property real statsFocusMs: 0
    readonly property string today: Qt.formatDate(new Date(root.now), "yyyy-MM-dd")

    // ── Countdown ─────────────────────────────────────────────────────────
    readonly property var presets: [60, 180, 300, 600, 900, 1500, 2700, 3600]
    property bool cdRunning: false
    property bool cdFinished: false
    property real cdEndsAt: 0
    property real cdTotalMs: 300000
    property real cdRemainingMs: 300000
    property string cdLabel: ""
    readonly property real cdLeftMs: root.cdRunning ? Math.max(0, root.cdEndsAt - root.now) : root.cdRemainingMs
    readonly property bool cdPristine: !root.cdRunning && !root.cdFinished && root.cdRemainingMs === root.cdTotalMs

    // ── Stopwatch ─────────────────────────────────────────────────────────
    property bool swRunning: false
    property real swStartedAt: 0
    property real swAccumMs: 0
    property var laps: [] // newest first: { n, split, total }
    readonly property real swElapsedMs: root.swAccumMs + (root.swRunning ? Math.max(0, root.now - root.swStartedAt) : 0)
    readonly property int bestLap: root.lapExtreme(true)
    readonly property int worstLap: root.lapExtreme(false)

    readonly property bool anyRunning: root.focusRunning || root.cdRunning || root.swRunning
    readonly property bool activeRunning: [root.focusRunning, root.cdRunning, root.swRunning][root.currentTab]

    readonly property color activeColor: {
        if (root.currentTab === 0)
            return root.phase === "work" ? root.focusColor : root.breakColor;
        if (root.currentTab === 1)
            return root.cdFinished ? root.doneColor : root.countdownColor;
        return root.stopwatchColor;
    }

    property string flash: ""

    // ── Formatting ────────────────────────────────────────────────────────
    function pad2(value) {
        return value < 10 ? "0" + value : String(value);
    }

    function formatClock(ms) {
        const s = Math.max(0, Math.ceil(ms / 1000));
        const h = Math.floor(s / 3600);
        const rest = root.pad2(Math.floor((s % 3600) / 60)) + ":" + root.pad2(s % 60);
        return h > 0 ? h + ":" + rest : rest;
    }

    function formatElapsed(ms) {
        const s = Math.floor(Math.max(0, ms) / 1000);
        const h = Math.floor(s / 3600);
        const rest = root.pad2(Math.floor((s % 3600) / 60)) + ":" + root.pad2(s % 60);
        return h > 0 ? h + ":" + rest : rest;
    }

    function centis(ms) {
        return "." + root.pad2(Math.floor(Math.max(0, ms) / 10) % 100);
    }

    function formatLength(seconds) {
        if (seconds < 60)
            return seconds + "s";
        if (seconds < 3600)
            return Math.round(seconds / 60) + "m";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return m > 0 ? h + "h " + m + "m" : h + "h";
    }

    function endsAt(ms) {
        return Qt.formatTime(new Date(ms), "HH:mm");
    }

    function phaseName(phase) {
        return phase === "short" ? "Short break" : (phase === "long" ? "Long break" : "Focus");
    }

    function phaseMs(phase) {
        return (phase === "short" ? root.shortMin : (phase === "long" ? root.longMin : root.workMin)) * 60000;
    }

    function showFlash(text) {
        root.flash = text;
        flashTimer.restart();
    }

    function selectTab(index) {
        root.currentTab = (index + root.tabs.length) % root.tabs.length;
        root.save();
    }

    function touch() {
        root.now = Date.now();
    }

    // ── Focus logic ───────────────────────────────────────────────────────
    function ensureToday() {
        if (root.statsDate !== root.today) {
            root.statsDate = root.today;
            root.statsSessions = 0;
            root.statsFocusMs = 0;
        }
    }

    function toggleFocus() {
        root.touch();
        if (root.focusRunning) {
            root.focusRemainingMs = Math.max(0, root.focusEndsAt - root.now);
            root.focusRunning = false;
        } else {
            root.focusEndsAt = root.now + root.focusRemainingMs;
            root.focusRunning = true;
        }
        root.save();
    }

    // natural: the clock hit zero (alerts, counts towards today's stats,
    // honours auto-start). Otherwise it's a Skip, which keeps the
    // running/paused state as it was.
    function advanceFocus(natural) {
        const endedAt = root.focusEndsAt;
        const finished = root.phase;
        // Hours overdue (the machine slept, the shell was off): catch up
        // silently instead of announcing a phase that ended long ago.
        const stale = natural && root.now - endedAt > 5 * 60000;

        if (finished === "work") {
            root.completed += 1;
            if (natural) {
                root.ensureToday();
                root.statsSessions += 1;
                root.statsFocusMs += root.focusTotalMs;
            }
            root.phase = root.completed >= root.cycles ? "long" : "short";
        } else {
            if (finished === "long")
                root.completed = 0;
            root.phase = "work";
        }

        root.focusTotalMs = root.phaseMs(root.phase);

        if (natural) {
            root.focusRunning = root.autoStart && !stale;
            if (root.focusRunning)
                root.focusEndsAt = endedAt + root.focusTotalMs > root.now ? endedAt + root.focusTotalMs : root.now + root.focusTotalMs;
            else
                root.focusRemainingMs = root.focusTotalMs;

            if (!stale)
                root.alertRequested(root.focusAlert(finished));
        } else if (root.focusRunning) {
            root.focusEndsAt = root.now + root.focusTotalMs;
        } else {
            root.focusRemainingMs = root.focusTotalMs;
        }

        root.save();
    }

    function focusAlert(finished) {
        const minutes = Math.round(root.focusTotalMs / 60000);
        const today = root.statsSessions > 0 ? "Today  ·  " + root.statsSessions + (root.statsSessions === 1 ? " session  ·  " : " sessions  ·  ") + root.formatLength(Math.round(root.statsFocusMs / 1000)) + " focused" : "";
        if (finished === "work") {
            return {
                source: "timer",
                kind: "break",
                accent: String(root.breakColor),
                icon: root.phase === "long" ? "self_improvement" : "coffee",
                kicker: "Focus done  ·  " + root.completed + " of " + root.cycles + (root.focusTask !== "" ? "  ·  " + root.focusTask : ""),
                title: root.phase === "long" ? "Long break — you earned it" : "Break time",
                body: root.autoStart ? minutes + " min break started  ·  ends " + root.endsAt(root.focusEndsAt) : minutes + " min break is ready when you are",
                meta: today,
                actions: root.autoStart ? [
                    { id: "focus-skip", label: "Skip break", icon: "skip_next" },
                    { id: "focus-toggle", label: "Pause", icon: "pause", primary: true }
                ] : [
                    { id: "focus-skip", label: "Skip", icon: "skip_next" },
                    { id: "focus-toggle", label: "Start break", icon: "play_arrow", primary: true }
                ],
                timeout: 12000
            };
        }
        const session = "Session " + (root.completed + 1) + " of " + root.cycles;
        return {
            source: "timer",
            kind: "focus",
            accent: String(root.focusColor),
            icon: "bolt",
            kicker: (finished === "long" ? "Cycle complete" : "Break over") + (root.focusTask !== "" ? "  ·  " + root.focusTask : ""),
            title: "Back to focus",
            body: root.autoStart ? session + "  ·  " + minutes + " min  ·  ends " + root.endsAt(root.focusEndsAt) : session + "  ·  " + minutes + " min",
            meta: today,
            actions: root.autoStart ? [
                { id: "focus-toggle", label: "Pause", icon: "pause" },
                { id: "dismiss", label: "Let's go", icon: "check", primary: true }
            ] : [
                { id: "dismiss", label: "Later", icon: "schedule" },
                { id: "focus-toggle", label: "Start focus", icon: "play_arrow", primary: true }
            ],
            timeout: 12000
        };
    }

    // Buttons on the banner. Returns what happened, shown on the banner.
    function handleAlertAction(id) {
        switch (id) {
        case "focus-toggle":
            root.toggleFocus();
            return root.focusRunning ? root.phaseName(root.phase) + " running  ·  ends " + root.endsAt(root.focusEndsAt) : "Paused";
        case "focus-skip":
            root.advanceFocus(false);
            return root.phaseName(root.phase) + (root.focusRunning ? "  ·  ends " + root.endsAt(root.focusEndsAt) : " is up next");
        case "timer-add1":
            root.touch();
            root.cdFinished = false;
            root.cdTotalMs = 60000;
            root.cdRemainingMs = 60000;
            root.cdEndsAt = root.now + 60000;
            root.cdRunning = true;
            root.save();
            return "One more minute  ·  rings " + root.endsAt(root.cdEndsAt);
        case "timer-again":
            root.cdRunning = false;
            root.toggleCountdown();
            return "Restarted  ·  rings " + root.endsAt(root.cdEndsAt);
        }
        return "";
    }

    // From the To-do panel: a work session labelled with the task.
    function startFocusOn(task) {
        root.focusTask = task;
        root.currentTab = 0;
        if (root.phase !== "work")
            root.setPhase("work");
        if (!root.focusRunning)
            root.toggleFocus();
        root.showFlash("Focusing on “" + task + "”");
        root.save();
    }

    function setPhase(phase) {
        root.touch();
        root.phase = phase;
        root.focusTotalMs = root.phaseMs(phase);
        if (root.focusRunning)
            root.focusEndsAt = root.now + root.focusTotalMs;
        else
            root.focusRemainingMs = root.focusTotalMs;
        root.save();
    }

    // Reset once: restart this phase. Reset again: start the cycle over.
    function resetFocus() {
        if (root.focusPristine) {
            root.completed = 0;
            root.phase = "work";
            root.focusTotalMs = root.phaseMs("work");
            root.focusRemainingMs = root.focusTotalMs;
            root.focusTask = "";
            root.showFlash("Cycle restarted");
        } else {
            root.focusRunning = false;
            root.focusRemainingMs = root.focusTotalMs;
            root.showFlash("Phase restarted — reset again for a new cycle");
        }
        root.save();
    }

    function setLength(phase, minutes) {
        const oldMs = root.phaseMs(phase);
        if (phase === "work")
            root.workMin = minutes;
        else if (phase === "short")
            root.shortMin = minutes;
        else
            root.longMin = minutes;

        if (root.phase === phase) {
            const delta = root.phaseMs(phase) - oldMs;
            root.touch();
            if (root.focusPristine) {
                root.focusTotalMs = root.phaseMs(phase);
                root.focusRemainingMs = root.focusTotalMs;
            } else {
                root.focusTotalMs = Math.max(60000, root.focusTotalMs + delta);
                if (root.focusRunning)
                    root.focusEndsAt = Math.max(root.now + 1000, root.focusEndsAt + delta);
                else
                    root.focusRemainingMs = Math.max(1000, root.focusRemainingMs + delta);
            }
        }
        root.save();
    }

    // ↑/↓ and the scroll wheel on Focus: stretch or trim the current phase.
    function nudgeFocus(ms) {
        root.touch();
        const left = Math.max(root.focusRunning ? 1000 : 60000, Math.min(4 * 3600000, root.focusLeftMs + ms));
        if (root.focusRunning)
            root.focusEndsAt = root.now + left;
        else
            root.focusRemainingMs = left;
        root.focusTotalMs = Math.max(root.focusTotalMs, left);
        root.save();
    }

    // ── Countdown logic ───────────────────────────────────────────────────
    function toggleCountdown() {
        root.touch();
        if (root.cdRunning) {
            root.cdRemainingMs = Math.max(0, root.cdEndsAt - root.now);
            root.cdRunning = false;
        } else {
            if (root.cdFinished || root.cdRemainingMs <= 0) {
                root.cdFinished = false;
                root.cdRemainingMs = root.cdTotalMs;
            }
            root.cdEndsAt = root.now + root.cdRemainingMs;
            root.cdRunning = true;
        }
        root.save();
    }

    function startPreset(seconds) {
        root.touch();
        root.cdFinished = false;
        root.cdTotalMs = seconds * 1000;
        root.cdRemainingMs = root.cdTotalMs;
        root.cdEndsAt = root.now + root.cdTotalMs;
        root.cdRunning = true;
        root.save();
    }

    function nudgeCountdown(ms) {
        root.touch();
        const pristine = root.cdPristine || root.cdFinished;
        const base = root.cdFinished ? 0 : root.cdLeftMs;
        const left = Math.max(root.cdRunning ? 1000 : 0, Math.min(24 * 3600000, base + ms));
        root.cdFinished = false;

        if (root.cdRunning) {
            root.cdEndsAt = root.now + left;
        } else {
            root.cdRemainingMs = left;
            if (pristine)
                root.cdTotalMs = left;
        }
        root.cdTotalMs = Math.max(root.cdTotalMs, left, 1000);
        root.save();
    }

    function resetCountdown() {
        root.cdRunning = false;
        root.cdFinished = false;
        root.cdRemainingMs = root.cdTotalMs;
        root.save();
    }

    function finishCountdown() {
        const stale = root.now - root.cdEndsAt > 5 * 60000;
        root.cdRunning = false;
        root.cdRemainingMs = 0;
        root.cdFinished = true;
        if (!stale) {
            const length = root.formatLength(Math.round(root.cdTotalMs / 1000));
            root.alertRequested({
                source: "timer",
                kind: "countdown",
                accent: String(root.doneColor),
                icon: "hourglass_bottom",
                kicker: "Timer  ·  " + length,
                title: root.cdLabel !== "" ? root.cdLabel : "Time's up",
                body: root.cdLabel !== "" ? "Your " + length + " timer is done" : "Your " + length + " timer ran out",
                meta: "Rang at " + root.endsAt(root.now),
                actions: [
                    { id: "timer-add1", label: "+1 min", icon: "add" },
                    { id: "timer-again", label: "Again", icon: "replay" },
                    { id: "dismiss", label: "Done", icon: "check", primary: true }
                ],
                timeout: 12000
            });
        }
        root.save();
    }

    // ── Stopwatch logic ───────────────────────────────────────────────────
    function toggleStopwatch() {
        root.touch();
        if (root.swRunning) {
            root.swAccumMs += root.now - root.swStartedAt;
            root.swRunning = false;
        } else {
            root.swStartedAt = root.now;
            root.swRunning = true;
        }
        root.save();
    }

    function lap() {
        if (!root.swRunning)
            return;
        root.touch();
        const total = root.swElapsedMs;
        const previous = root.laps.length > 0 ? root.laps[0].total : 0;
        const entry = { n: root.laps.length + 1, split: total - previous, total: total };
        root.laps = [entry].concat(root.laps);
        root.showFlash("Lap " + entry.n + "  ·  " + root.formatElapsed(entry.split) + root.centis(entry.split));
        root.save();
    }

    function resetStopwatch() {
        root.swRunning = false;
        root.swAccumMs = 0;
        root.laps = [];
        root.save();
    }

    function lapExtreme(best) {
        if (root.laps.length < 3)
            return -1;
        let pick = root.laps[0];
        for (const entry of root.laps) {
            if (best ? entry.split < pick.split : entry.split > pick.split)
                pick = entry;
        }
        return pick.n;
    }

    // ── Shared actions ────────────────────────────────────────────────────
    function toggleActive() {
        [root.toggleFocus, root.toggleCountdown, root.toggleStopwatch][root.currentTab]();
    }

    function resetActive() {
        [root.resetFocus, root.resetCountdown, root.resetStopwatch][root.currentTab]();
    }

    function nudgeActive(ms) {
        if (root.currentTab === 0)
            root.nudgeFocus(ms);
        else if (root.currentTab === 1)
            root.nudgeCountdown(ms);
    }

    function tick() {
        root.touch();
        if (root.focusRunning && root.now >= root.focusEndsAt)
            root.advanceFocus(true);
        if (root.cdRunning && root.now >= root.cdEndsAt)
            root.finishCountdown();
    }

    // ── Persistence ───────────────────────────────────────────────────────
    readonly property string statePath: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/timer.json"
    property bool stateLoaded: false

    function save() {
        if (root.stateLoaded)
            saveTimer.restart();
    }

    function writeState() {
        stateFile.setText(JSON.stringify({
            tab: root.currentTab,
            settings: { workMin: root.workMin, shortMin: root.shortMin, longMin: root.longMin, cycles: root.cycles, autoStart: root.autoStart },
            focus: { task: root.focusTask, phase: root.phase, completed: root.completed, running: root.focusRunning, endsAt: root.focusEndsAt, total: root.focusTotalMs, remaining: root.focusRemainingMs },
            countdown: { running: root.cdRunning, finished: root.cdFinished, endsAt: root.cdEndsAt, total: root.cdTotalMs, remaining: root.cdRemainingMs, label: root.cdLabel },
            stopwatch: { running: root.swRunning, startedAt: root.swStartedAt, accum: root.swAccumMs, laps: root.laps },
            stats: { date: root.statsDate, sessions: root.statsSessions, focusMs: root.statsFocusMs }
        }, null, 2) + "\n");
    }

    function applyState(text) {
        let state = null;
        try {
            state = JSON.parse(text);
        } catch (error) {
            state = null;
        }

        if (state && typeof state === "object") {
            const num = (value, fallback) => typeof value === "number" && isFinite(value) ? value : fallback;
            const s = state.settings || {};
            root.workMin = num(s.workMin, 25);
            root.shortMin = num(s.shortMin, 5);
            root.longMin = num(s.longMin, 15);
            root.cycles = num(s.cycles, 4);
            root.autoStart = s.autoStart !== false;
            root.currentTab = Math.max(0, Math.min(2, num(state.tab, 0)));

            const f = state.focus || {};
            root.phase = ["work", "short", "long"].includes(f.phase) ? f.phase : "work";
            root.completed = num(f.completed, 0);
            root.focusTask = typeof f.task === "string" ? f.task : "";
            root.focusTotalMs = num(f.total, root.phaseMs(root.phase));
            root.focusRemainingMs = num(f.remaining, root.focusTotalMs);
            root.focusEndsAt = num(f.endsAt, 0);
            root.focusRunning = f.running === true;

            const c = state.countdown || {};
            root.cdTotalMs = num(c.total, 300000);
            root.cdRemainingMs = num(c.remaining, root.cdTotalMs);
            root.cdEndsAt = num(c.endsAt, 0);
            root.cdFinished = c.finished === true;
            root.cdLabel = typeof c.label === "string" ? c.label : "";
            root.cdRunning = c.running === true;

            const w = state.stopwatch || {};
            root.swAccumMs = num(w.accum, 0);
            root.swStartedAt = num(w.startedAt, 0);
            root.laps = Array.isArray(w.laps) ? w.laps : [];
            root.swRunning = w.running === true;

            const st = state.stats || {};
            root.statsDate = typeof st.date === "string" ? st.date : "";
            root.statsSessions = num(st.sessions, 0);
            root.statsFocusMs = num(st.focusMs, 0);
        }

        root.stateLoaded = true;
        root.tick();
    }

    FileView {
        id: stateFile

        path: root.statePath
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyState(stateFile.text())
        onLoadFailed: root.applyState("")
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: root.writeState()
    }

    // Only redraws; the clocks themselves are end/start timestamps. Fast while
    // the stopwatch's hundredths are on screen, lazy while the panel is shut.
    Timer {
        interval: !root.visible ? 1000 : (root.currentTab === 2 && root.swRunning ? 40 : 200)
        repeat: true
        running: root.anyRunning
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    Timer {
        id: flashTimer

        interval: 1800
        onTriggered: root.flash = ""
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            root.touch();
            keyScope.forceActiveFocus();
        }
    }

    onCurrentTabChanged: tabSwap.restart()

    // ── Components ────────────────────────────────────────────────────────

    component HeaderButton: Rectangle {
        id: headerButton

        required property string icon

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
            onClicked: headerButton.clicked()
        }
    }

    component Chip: Rectangle {
        id: chip

        required property string text
        property bool active: false
        property color tint: root.activeColor

        signal clicked

        Layout.fillWidth: true
        implicitHeight: 28
        radius: 9
        color: chip.active ? Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b, 0.14) : (chipMouse.containsMouse ? "#161616" : "#0a0a0a")
        border.width: 1
        border.color: chip.active ? Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b, 0.55) : (chipMouse.containsMouse ? "#2a2a2a" : "#1c1c1c")
        scale: chipMouse.pressed ? 0.92 : 1

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }

        Text {
            anchors.centerIn: parent
            text: chip.text
            color: chip.active ? chip.tint : (chipMouse.containsMouse ? root.primaryText : "#a0a0a0")
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }

            Behavior on color { ColorAnimation { duration: 160 } }
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component StepButton: Rectangle {
        id: stepButton

        required property string icon
        property bool enabledStep: true

        signal clicked

        width: 20
        height: 20
        radius: 7
        color: stepMouse.containsMouse && stepButton.enabledStep ? "#1d1d1d" : "transparent"
        opacity: stepButton.enabledStep ? 1 : 0.3
        scale: stepMouse.pressed ? 0.85 : 1

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }

        MIcon {
            anchors.centerIn: parent
            name: stepButton.icon
            size: 13
            color: "#b0b0b0"
        }

        MouseArea {
            id: stepMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: stepButton.enabledStep ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (stepButton.enabledStep) stepButton.clicked()
        }
    }

    // A minutes stepper row: − value +, scroll to nudge.
    component Stepper: Item {
        id: stepper

        required property string label
        required property int value
        property int minimum: 1
        property int maximum: 90
        property int step: 1
        property bool current: false

        signal adjusted(int value)

        function nudge(direction) {
            const next = Math.max(stepper.minimum, Math.min(stepper.maximum, stepper.value + direction * stepper.step));
            if (next !== stepper.value)
                stepper.adjusted(next);
        }

        Layout.fillWidth: true
        implicitHeight: 24

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => stepper.nudge(wheel.angleDelta.y > 0 ? 1 : -1)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 4
            spacing: 2

            Rectangle {
                Layout.preferredWidth: 4
                Layout.preferredHeight: 4
                Layout.rightMargin: 4
                radius: 2
                color: root.activeColor
                opacity: stepper.current ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Text {
                Layout.fillWidth: true
                text: stepper.label
                color: stepper.current ? root.primaryText : "#9a9a9a"
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight

                Behavior on color { ColorAnimation { duration: 180 } }
            }

            StepButton {
                icon: "remove"
                enabledStep: stepper.value > stepper.minimum
                onClicked: stepper.nudge(-1)
            }

            Text {
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignHCenter
                text: stepper.value + "m"
                color: root.primaryText
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }

            StepButton {
                icon: "add"
                enabledStep: stepper.value < stepper.maximum
                onClicked: stepper.nudge(1)
            }
        }
    }

    component ControlButton: Rectangle {
        id: control

        required property string icon
        property string text: ""
        property bool primary: false
        property bool lit: false

        signal clicked

        Layout.preferredHeight: root.controlsHeight
        radius: 12
        color: control.lit ? Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.13) : (controlMouse.containsMouse ? "#161616" : "#0a0a0a")
        border.width: 1
        border.color: control.lit ? Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.6) : (controlMouse.containsMouse ? "#2a2a2a" : "#232323")
        scale: controlMouse.pressed ? 0.94 : 1

        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

        Row {
            anchors.centerIn: parent
            spacing: 6

            MIcon {
                id: controlIcon

                anchors.verticalCenter: parent.verticalCenter
                name: control.icon
                size: control.primary ? 18 : 16
                color: control.lit ? root.activeColor : (control.primary ? root.primaryText : root.secondaryText)

                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.text !== ""
                text: control.text
                color: control.lit ? root.activeColor : root.primaryText
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold

                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        // A little pop whenever the icon changes (play ⇄ pause).
        onIconChanged: iconPop.restart()

        SequentialAnimation {
            id: iconPop

            NumberAnimation { target: controlIcon; property: "scale"; to: 0.6; duration: 70 }
            NumberAnimation { target: controlIcon; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 }
        }

        MouseArea {
            id: controlMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: control.clicked()
        }
    }

    // A tab page on the right: slides in from the side it lives on.
    component Page: ColumnLayout {
        id: page

        required property int tabIndex
        readonly property bool active: root.currentTab === page.tabIndex

        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        spacing: 6
        opacity: page.active ? 1 : 0
        x: page.active ? 0 : (page.tabIndex < root.currentTab ? -28 : 28)
        visible: opacity > 0.01
        enabled: page.active

        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    FocusScope {
        id: keyScope

        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.closeRequested()
        Keys.onLeftPressed: root.selectTab(root.currentTab - 1)
        Keys.onRightPressed: root.selectTab(root.currentTab + 1)
        Keys.onUpPressed: root.nudgeActive(60000)
        Keys.onDownPressed: root.nudgeActive(-60000)
        Keys.onPressed: event => {
            const key = event.key;
            if (key >= Qt.Key_1 && key <= Qt.Key_3)
                root.selectTab(key - Qt.Key_1);
            else if (key === Qt.Key_Tab)
                root.selectTab(root.currentTab + 1);
            else if (key === Qt.Key_Backtab)
                root.selectTab(root.currentTab - 1);
            else if (key === Qt.Key_Space || key === Qt.Key_Return || key === Qt.Key_Enter)
                root.toggleActive();
            else if (key === Qt.Key_R)
                root.resetActive();
            else if (key === Qt.Key_S && root.currentTab === 0)
                root.advanceFocus(false);
            else if (key === Qt.Key_L && root.currentTab === 2)
                root.lap();
            else if (key === Qt.Key_N && root.currentTab === 1)
                labelInput.forceActiveFocus();
            else if (key === Qt.Key_Plus || key === Qt.Key_Equal)
                root.nudgeActive(60000);
            else if (key === Qt.Key_Minus)
                root.nudgeActive(-60000);
            else
                return;
            event.accepted = true;
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
                        id: headerIcon

                        anchors.centerIn: parent
                        name: root.tabs[root.currentTab].icon
                        size: 16
                        color: root.primaryText
                    }

                    // Something is ticking somewhere, even on another tab.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        width: 6
                        height: 6
                        radius: 3
                        color: root.activeRunning ? root.activeColor : root.focusColor
                        visible: root.anyRunning

                        SequentialAnimation on opacity {
                            running: root.anyRunning && root.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "Timer"
                        color: root.primaryText
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.statusLine
                        color: root.secondaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }
                }

                HeaderButton {
                    icon: "close"
                    onClicked: root.closeRequested()
                }
            }

            // Tab bar
            Rectangle {
                id: tabBar

                readonly property real cell: (width - 6) / root.tabs.length

                Layout.fillWidth: true
                Layout.preferredHeight: root.tabBarHeight
                radius: 11
                color: "#0a0a0a"
                border.width: 1
                border.color: "#1c1c1c"

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
                        color: root.activeColor

                        Behavior on color { ColorAnimation { duration: 240 } }
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
                            readonly property bool ticking: [root.focusRunning, root.cdRunning, root.swRunning][index]

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

                                // Ticking in the background: a small live time
                                // instead of a dot, so you can glance at it.
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: tabItem.ticking && !tabItem.active
                                    text: [root.formatClock(root.focusLeftMs), root.formatClock(root.cdLeftMs), root.formatElapsed(root.swElapsedMs)][tabItem.index]
                                    color: [root.phase === "work" ? root.focusColor : root.breakColor, root.countdownColor, root.stopwatchColor][tabItem.index]
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
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

            // Body: ring + tab page
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.bodyHeight
                spacing: 16

                Item {
                    id: ring

                    readonly property real target: {
                        if (root.currentTab === 0)
                            return root.focusTotalMs > 0 ? root.focusLeftMs / root.focusTotalMs : 0;
                        if (root.currentTab === 1)
                            return root.cdFinished ? 1 : (root.cdTotalMs > 0 ? root.cdLeftMs / root.cdTotalMs : 0);
                        return (root.swElapsedMs % 60000) / 60000;
                    }
                    property real shown: ring.target
                    readonly property real thickness: 9
                    readonly property real radius: width / 2 - ring.thickness / 2 - 2
                    readonly property real headAngle: (-90 + 360 * ring.shown) * Math.PI / 180
                    readonly property bool paused: !root.activeRunning && (root.currentTab === 0 ? !root.focusPristine : (root.currentTab === 1 ? (!root.cdPristine && !root.cdFinished) : root.swElapsedMs > 0))

                    Behavior on shown {
                        enabled: root.currentTab !== 2 || !root.swRunning
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }

                    Layout.preferredWidth: root.ringSize
                    Layout.preferredHeight: root.ringSize
                    Layout.alignment: Qt.AlignVCenter

                    // Soft glow behind the ring while it runs.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        height: width
                        radius: width / 2
                        color: root.activeColor
                        opacity: root.activeRunning ? 0.06 : (root.cdFinished && root.currentTab === 1 ? 0.1 : 0)

                        Behavior on opacity { NumberAnimation { duration: 400 } }
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: "#161616"
                            strokeWidth: ring.thickness
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: ring.width / 2
                                centerY: ring.height / 2
                                radiusX: ring.radius
                                radiusY: ring.radius
                                startAngle: -90
                                sweepAngle: 360
                            }
                        }

                        ShapePath {
                            strokeColor: ring.shown > 0.002 ? ringColor.value : "transparent"
                            strokeWidth: ring.thickness
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: ring.width / 2
                                centerY: ring.height / 2
                                radiusX: ring.radius
                                radiusY: ring.radius
                                startAngle: -90
                                sweepAngle: 360 * Math.min(0.9999, ring.shown)
                            }
                        }
                    }

                    // Tweened colour for the arc (ShapePath can't take a Behavior).
                    QtObject {
                        id: ringColor

                        property color value: root.activeColor

                        Behavior on value { ColorAnimation { duration: 300 } }
                    }

                    // Minute ticks for the stopwatch's sweep.
                    Repeater {
                        model: root.currentTab === 2 ? 12 : 0

                        Rectangle {
                            required property int index

                            readonly property real angle: index * 30 * Math.PI / 180

                            x: ring.width / 2 + (ring.radius - 12) * Math.sin(angle) - width / 2
                            y: ring.height / 2 - (ring.radius - 12) * Math.cos(angle) - height / 2
                            width: 3
                            height: 3
                            radius: 1.5
                            color: "#2e2e2e"
                        }
                    }

                    // Bright head at the end of the arc.
                    Rectangle {
                        width: ring.thickness + 3
                        height: width
                        radius: width / 2
                        x: ring.width / 2 + ring.radius * Math.cos(ring.headAngle) - width / 2
                        y: ring.height / 2 + ring.radius * Math.sin(ring.headAngle) - height / 2
                        color: "#ffffff"
                        border.width: 2
                        border.color: ringColor.value
                        opacity: root.activeRunning && ring.shown > 0.002 ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    Column {
                        id: ringCenter

                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.currentTab === 0 ? root.phaseName(root.phase).toUpperCase() : (root.currentTab === 1 ? (root.cdFinished ? "DONE" : (root.cdLabel !== "" ? root.cdLabel.toUpperCase() : "TIMER")) : "ELAPSED")
                            width: Math.min(implicitWidth, ring.width - 50)
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            color: ringColor.value
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 1.4
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter

                            Text {
                                id: bigTime

                                text: root.currentTab === 0 ? root.formatClock(root.focusLeftMs) : (root.currentTab === 1 ? root.formatClock(root.cdLeftMs) : root.formatElapsed(root.swElapsedMs))
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: text.length > 5 ? 28 : 36
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }

                                // Paused mid-way: breathe, like a paused clock.
                                SequentialAnimation on opacity {
                                    running: ring.paused && root.visible
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) bigTime.opacity = 1
                                    NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                                }
                            }

                            Text {
                                anchors.baseline: bigTime.baseline
                                visible: root.currentTab === 2
                                text: root.centis(root.swElapsedMs)
                                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.ringCaption
                            color: root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.features: { "tnum": 1 }
                        }
                    }

                    SequentialAnimation {
                        id: tabSwap

                        NumberAnimation { target: ringCenter; property: "opacity"; to: 0; duration: 80 }
                        NumberAnimation { target: ringCenter; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    }

                    // Countdown ran out: the ring pulses until you look.
                    SequentialAnimation on scale {
                        running: root.cdFinished && root.currentTab === 1 && root.visible
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) ring.scale = 1
                        NumberAnimation { to: 1.04; duration: 420; easing.type: Easing.OutQuad }
                        NumberAnimation { to: 1; duration: 420; easing.type: Easing.InQuad }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleActive()
                        onWheel: wheel => root.nudgeActive((wheel.angleDelta.y > 0 ? 1 : -1) * (wheel.modifiers & Qt.ShiftModifier ? 10000 : 60000))
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // ── Focus ──
                    Page {
                        tabIndex: 0

                        Rectangle {
                            id: phaseBar

                            readonly property var phases: ["work", "short", "long"]
                            readonly property real cell: (width - 6) / 3

                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 10
                            color: "#0a0a0a"
                            border.width: 1
                            border.color: "#1c1c1c"

                            Rectangle {
                                y: 3
                                x: 3 + phaseBar.phases.indexOf(root.phase) * phaseBar.cell
                                width: phaseBar.cell
                                height: parent.height - 6
                                radius: 7
                                color: Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.14)
                                border.width: 1
                                border.color: Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.45)

                                Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                            }

                            Row {
                                x: 3
                                y: 3

                                Repeater {
                                    model: ["Focus", "Short", "Long"]

                                    Item {
                                        id: phaseItem

                                        required property string modelData
                                        required property int index

                                        readonly property bool active: phaseBar.phases[index] === root.phase

                                        width: phaseBar.cell
                                        height: phaseBar.height - 6

                                        Text {
                                            anchors.centerIn: parent
                                            text: phaseItem.modelData
                                            color: phaseItem.active ? root.activeColor : "#7a7a7a"
                                            font.family: root.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.Bold

                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (!phaseItem.active) root.setPhase(phaseBar.phases[phaseItem.index])
                                        }
                                    }
                                }
                            }
                        }

                        // Cycle progress
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            implicitHeight: 16
                            spacing: 5

                            Repeater {
                                model: root.cycles

                                Rectangle {
                                    id: cycleDot

                                    required property int index

                                    readonly property bool done: index < root.completed
                                    readonly property bool current: root.phase === "work" && index === root.completed

                                    Layout.fillWidth: true
                                    implicitHeight: 5
                                    radius: 2.5
                                    color: "#1c1c1c"
                                    clip: true

                                    Rectangle {
                                        height: parent.height
                                        radius: parent.radius
                                        color: root.focusColor
                                        width: cycleDot.done ? parent.width : (cycleDot.current ? parent.width * (1 - root.focusLeftMs / Math.max(1, root.focusTotalMs)) : 0)

                                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }

                            Text {
                                text: Math.min(root.completed + (root.phase === "work" ? 1 : 0), root.cycles) + "/" + root.cycles
                                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: lengths.implicitHeight + 4
                            radius: 12
                            color: root.cardColor
                            border.width: 1
                            border.color: root.cardBorder

                            ColumnLayout {
                                id: lengths

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Stepper {
                                    label: "Focus"
                                    value: root.workMin
                                    minimum: 5
                                    maximum: 120
                                    step: 5
                                    current: root.phase === "work"
                                    onAdjusted: value => root.setLength("work", value)
                                }

                                Stepper {
                                    label: "Short break"
                                    value: root.shortMin
                                    minimum: 1
                                    maximum: 30
                                    current: root.phase === "short"
                                    onAdjusted: value => root.setLength("short", value)
                                }

                                Stepper {
                                    label: "Long break"
                                    value: root.longMin
                                    minimum: 5
                                    maximum: 60
                                    step: 5
                                    current: root.phase === "long"
                                    onAdjusted: value => root.setLength("long", value)
                                }

                                // Auto-start switch
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 24

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 18
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Auto-start next phase"
                                            color: "#9a9a9a"
                                            font.family: root.fontFamily
                                            font.pixelSize: 11
                                        }

                                        Rectangle {
                                            implicitWidth: 28
                                            implicitHeight: 16
                                            radius: 8
                                            color: root.autoStart ? Qt.rgba(root.focusColor.r, root.focusColor.g, root.focusColor.b, 0.3) : "#1a1a1a"
                                            border.width: 1
                                            border.color: root.autoStart ? root.focusColor : "#2a2a2a"

                                            Behavior on color { ColorAnimation { duration: 180 } }

                                            Rectangle {
                                                y: 3
                                                x: root.autoStart ? parent.width - width - 3 : 3
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: root.autoStart ? root.focusColor : "#6a6a6a"

                                                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.autoStart = !root.autoStart;
                                            root.save();
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: root.statsDate === root.today && root.statsSessions > 0 ? "Today  ·  " + root.statsSessions + (root.statsSessions === 1 ? " session  ·  " : " sessions  ·  ") + root.formatLength(Math.round(root.statsFocusMs / 1000)) + " focused" : "Today  ·  no sessions yet"
                            color: root.faintText
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    // ── Timer ──
                    Page {
                        tabIndex: 1

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 10
                            color: "#0a0a0a"
                            border.width: 1
                            border.color: labelInput.activeFocus ? Qt.rgba(root.countdownColor.r, root.countdownColor.g, root.countdownColor.b, 0.6) : "#1c1c1c"

                            Behavior on border.color { ColorAnimation { duration: 160 } }

                            MIcon {
                                id: labelIcon

                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                name: "label"
                                size: 13
                                color: labelInput.activeFocus ? root.countdownColor : "#5a5a5a"
                            }

                            TextInput {
                                id: labelInput

                                anchors.left: labelIcon.right
                                anchors.right: parent.right
                                anchors.leftMargin: 7
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.cdLabel
                                color: root.primaryText
                                selectionColor: "#3a3a3a"
                                maximumLength: 32
                                clip: true
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                onTextEdited: {
                                    root.cdLabel = text;
                                    root.save();
                                }
                                Keys.onReturnPressed: keyScope.forceActiveFocus()
                                Keys.onEnterPressed: keyScope.forceActiveFocus()
                                Keys.onEscapePressed: keyScope.forceActiveFocus()

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: labelInput.text === ""
                                    text: labelInput.activeFocus ? "Tea, laundry, pizza…" : "Name it  (N)"
                                    color: "#555555"
                                    font: labelInput.font
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: 6
                            columnSpacing: 6

                            Repeater {
                                model: root.presets

                                Chip {
                                    required property int modelData

                                    text: root.formatLength(modelData)
                                    tint: root.countdownColor
                                    active: root.cdTotalMs === modelData * 1000 && !root.cdPristine
                                    onClicked: root.startPreset(modelData)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Chip {
                                text: "−1m"
                                onClicked: root.nudgeCountdown(-60000)
                            }

                            Chip {
                                text: "+10s"
                                onClicked: root.nudgeCountdown(10000)
                            }

                            Chip {
                                text: "+1m"
                                onClicked: root.nudgeCountdown(60000)
                            }

                            Chip {
                                text: "+5m"
                                onClicked: root.nudgeCountdown(300000)
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: root.cdRunning ? "Scroll the ring to add or trim time" : (root.cdFinished ? "Finished — Space runs it again" : "Presets start right away")
                            color: root.faintText
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    // ── Stopwatch ──
                    Page {
                        tabIndex: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            implicitHeight: 16

                            Text {
                                Layout.fillWidth: true
                                text: "LAPS"
                                color: root.faintText
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 1.2
                            }

                            Text {
                                text: root.laps.length > 0 ? root.laps.length + (root.laps.length === 1 ? " lap" : " laps") : ""
                                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: root.cardColor
                            border.width: 1
                            border.color: root.cardBorder
                            clip: true

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                visible: root.laps.length === 0

                                MIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: "flag"
                                    size: 20
                                    color: "#3a3a3a"
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.swRunning ? "Press L to mark a lap" : "Laps show up here"
                                    color: "#555555"
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            ListView {
                                id: lapList

                                anchors.fill: parent
                                anchors.margins: 4
                                model: root.laps
                                boundsBehavior: Flickable.StopAtBounds
                                spacing: 0

                                add: Transition {
                                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240 }
                                    NumberAnimation { property: "x"; from: -16; to: 0; duration: 300; easing.type: Easing.OutCubic }
                                }
                                displaced: Transition {
                                    NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic }
                                }

                                delegate: Item {
                                    id: lapRow

                                    required property var modelData
                                    required property int index

                                    readonly property bool best: modelData.n === root.bestLap
                                    readonly property bool worst: modelData.n === root.worstLap
                                    readonly property color tone: best ? root.focusColor : (worst ? root.doneColor : root.primaryText)

                                    width: lapList.width
                                    height: 24

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: lapRow.index === 0 ? "#111111" : "transparent"
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text {
                                            Layout.preferredWidth: 42
                                            text: "Lap " + lapRow.modelData.n
                                            color: root.secondaryText
                                            font.family: root.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            font.features: { "tnum": 1 }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.formatElapsed(lapRow.modelData.split) + root.centis(lapRow.modelData.split) + (lapRow.best ? "  best" : (lapRow.worst ? "  slowest" : ""))
                                            color: lapRow.tone
                                            font.family: root.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }

                                        Text {
                                            text: root.formatElapsed(lapRow.modelData.total)
                                            color: root.faintText
                                            font.family: root.fontFamily
                                            font.pixelSize: 10
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Controls
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.controlsHeight
                spacing: 8

                ControlButton {
                    Layout.preferredWidth: 48
                    icon: "restart_alt"
                    onClicked: root.resetActive()
                }

                ControlButton {
                    Layout.fillWidth: true
                    primary: true
                    lit: root.activeRunning
                    icon: root.activeRunning ? "pause" : "play_arrow"
                    text: root.activeRunning ? "Pause" : (ring.paused ? "Resume" : (root.currentTab === 1 && root.cdFinished ? "Again" : "Start"))
                    onClicked: root.toggleActive()
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    icon: ["skip_next", "add", "flag"][root.currentTab]
                    opacity: root.currentTab === 2 && !root.swRunning ? 0.4 : 1
                    onClicked: {
                        if (root.currentTab === 0)
                            root.advanceFocus(false);
                        else if (root.currentTab === 1)
                            root.nudgeCountdown(60000);
                        else
                            root.lap();
                    }
                }
            }

            // Hint line: key help, or a short confirmation after an action.
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: root.hintHeight
                horizontalAlignment: Text.AlignHCenter
                text: root.flash !== "" ? root.flash : root.keyHint
                color: root.flash !== "" ? root.activeColor : root.faintText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold

                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }
    }

    readonly property string keyHint: [
        "Space start  ·  S skip  ·  R reset  ·  ↑↓ ±1 min  ·  Tab switch",
        "Space start  ·  ↑↓ ±1 min  ·  scroll ring (Shift ±10 s)  ·  N name",
        "Space start  ·  L lap  ·  R reset  ·  Tab switch"
    ][root.currentTab]

    readonly property string ringCaption: {
        if (root.currentTab === 0) {
            if (root.focusRunning)
                return "until " + root.endsAt(root.focusEndsAt);
            return "of " + root.formatLength(Math.round(root.focusTotalMs / 1000));
        }
        if (root.currentTab === 1) {
            if (root.cdRunning)
                return "until " + root.endsAt(root.cdEndsAt);
            return "of " + root.formatLength(Math.round(root.cdTotalMs / 1000));
        }
        return root.laps.length > 0 ? "lap " + (root.laps.length + 1) + "  ·  " + root.formatElapsed(root.swElapsedMs - root.laps[0].total) : (root.swRunning ? "running" : "ready");
    }

    readonly property string statusLine: {
        if (root.currentTab === 0) {
            const session = "session " + Math.min(root.completed + 1, root.cycles) + " of " + root.cycles;
            if (root.focusRunning)
                return (root.phase === "work" && root.focusTask !== "" ? "“" + root.focusTask + "”" : root.phaseName(root.phase)) + "  ·  ends " + root.endsAt(root.focusEndsAt) + "  ·  " + session;
            return (root.focusPristine ? "Ready" : "Paused") + "  ·  " + root.phaseName(root.phase).toLowerCase() + ", " + session;
        }
        if (root.currentTab === 1) {
            const name = root.cdLabel !== "" ? root.cdLabel : "Countdown";
            if (root.cdFinished)
                return name + "  ·  time's up";
            if (root.cdRunning)
                return name + "  ·  rings at " + root.endsAt(root.cdEndsAt);
            return root.cdPristine ? "Pick a length, scroll the ring, or ↑↓" : name + "  ·  paused";
        }
        if (root.swRunning)
            return "Running  ·  started " + root.endsAt(root.swStartedAt - root.swAccumMs);
        return root.swElapsedMs > 0 ? "Paused" : "Ready when you are";
    }
}
