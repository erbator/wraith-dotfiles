import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Órarend. The timetable lives in ~/.local/share/dynamic-glacier/timetable.json
// ({ bells: [[start, end]…], days: [[{ p: [first, last], subject, teacher,
// room, note }…] × 5] }) and reloads live when edited (E opens it in nvim).
//
//   - a live card: the lesson you're in and how long is left, or the break
//     and where to go next, or when tomorrow starts
//   - day tabs with dates and each day's hours; a week grid (W)
//   - per-lesson notes, edited right here (Enter on a lesson)
//   - homework on each lesson, from Reminders: tasks (no time) and reminders,
//     pinned to the lesson they're for (click one to open it there)
//   - R on a lesson adds to its next occurrence: a task, or a reminder the
//     evening before, in the morning, 10 minutes before, or as it starts
//   - "aliases": { "Magyar": ["nyelvtan", "irodalom"] } in timetable.json
//     lets other words mean a subject (a few Hungarian ones are built in)
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested
    // Hand-offs to the Reminders panel (wired in IslandContent).
    signal reminderRequested(string text, real fireAt, var lesson)
    signal openReminderRequested(string id)

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color noteColor: "#f87171"
    readonly property color taskColor: "#fbbf24"
    readonly property color reminderColor: "#c084fc"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"
    readonly property var subjectPalette: ["#60a5fa", "#f472b6", "#fbbf24", "#a78bfa", "#34d399", "#fb923c", "#22d3ee", "#f87171", "#a3e635", "#e879f9", "#2dd4bf", "#94a3b8", "#fda4af"]
    readonly property var dayTo: ["hétfőre", "keddre", "szerdára", "csütörtökre", "péntekre"]

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int nowHeight: 62
    readonly property int tabsHeight: 46
    readonly property int bodyHeight: 290
    readonly property int tasksHeight: 22
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 10

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.nowHeight + root.tabsHeight + root.bodyHeight + root.tasksHeight + root.hintHeight + root.sectionSpacing * 6
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property var dayShort: ["H", "K", "Sze", "Cs", "P"]
    readonly property var dayLong: ["Hétfő", "Kedd", "Szerda", "Csütörtök", "Péntek"]

    property var bells: []
    property var days: [[], [], [], [], []]
    property bool loaded: false
    property bool missing: false

    property var now: new Date()
    property int selectedDay: 0
    property int selectedLesson: -1
    property int editingLesson: -1
    property int composingLesson: -1
    property int composeWhen: 0
    property var pendingLesson: null
    property bool weekView: false
    property string toast: ""

    // ── Time ──────────────────────────────────────────────────────────────
    function minutes(text) {
        const parts = String(text).split(":");
        return Number(parts[0]) * 60 + Number(parts[1] || 0);
    }

    function nowMinutes() {
        return root.now.getHours() * 60 + root.now.getMinutes() + root.now.getSeconds() / 60;
    }

    function startOf(lesson) {
        return root.bells[lesson.p[0]] ? root.minutes(root.bells[lesson.p[0]][0]) : 0;
    }

    function endOf(lesson) {
        return root.bells[lesson.p[1]] ? root.minutes(root.bells[lesson.p[1]][1]) : 0;
    }

    function hhmm(mins) {
        const m = Math.round(mins);
        return Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") + (m % 60);
    }

    function duration(mins) {
        const m = Math.max(0, Math.ceil(mins));
        if (m < 60)
            return m + " perc";
        return Math.floor(m / 60) + " ó " + (m % 60) + " p";
    }

    // 0 = Monday … 4 = Friday; -1 on weekends.
    readonly property int todayIndex: {
        const d = root.now.getDay();
        return d >= 1 && d <= 5 ? d - 1 : -1;
    }

    // Monday of the week on screen: this week, or next week at the weekend.
    readonly property var monday: {
        const d = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate());
        const dow = d.getDay();
        d.setDate(d.getDate() + (dow === 0 ? 1 : (dow === 6 ? 2 : 1 - dow)));
        return d;
    }

    function dateOf(dayIndex) {
        const d = new Date(root.monday);
        d.setDate(d.getDate() + dayIndex);
        return d;
    }

    function lessonsOf(dayIndex) {
        return (root.days[dayIndex] || []).slice().sort((a, b) => a.p[0] - b.p[0]);
    }

    function dayRange(dayIndex) {
        const list = root.lessonsOf(dayIndex);
        if (list.length === 0)
            return "Szabad";
        return root.hhmm(root.startOf(list[0])) + "–" + root.hhmm(root.endOf(list[list.length - 1]));
    }

    function subjectKey(subject) {
        const word = root.fold(String(subject).toLowerCase().split(/[\s.\-/]+/)[0] || "");
        const aliases = { tori: "tortenelem", tesi: "testneveles", matek: "matematika" };
        return aliases[word] || word;
    }

    function fold(text) {
        const map = { "á": "a", "é": "e", "í": "i", "ó": "o", "ö": "o", "ő": "o", "ú": "u", "ü": "u", "ű": "u" };
        return String(text).toLowerCase().replace(/[áéíóöőúüű]/g, c => map[c]);
    }

    // Colours handed out in order of first appearance in the week, so
    // subjects don't collide the way a hash would.
    readonly property var colorMap: {
        const map = {};
        let next = 0;
        for (let d = 0; d < 5; d++)
            for (const lesson of root.lessonsOf(d)) {
                const key = root.subjectKey(lesson.subject);
                if (map[key] === undefined)
                    map[key] = root.subjectPalette[next++ % root.subjectPalette.length];
            }
        return map;
    }

    function subjectColor(subject) {
        return root.colorMap[root.subjectKey(subject)] || "#94a3b8";
    }

    // ── Live status (always about today) ──────────────────────────────────
    readonly property var status: {
        const t = root.nowMinutes();
        if (root.todayIndex >= 0) {
            const list = root.lessonsOf(root.todayIndex);
            for (let i = 0; i < list.length; i++) {
                const start = root.startOf(list[i]);
                const end = root.endOf(list[i]);
                if (t >= start && t < end) {
                    // Inside a double period: the bell in between is still a break.
                    for (let p = list[i].p[0]; p < list[i].p[1]; p++) {
                        const bellEnd = root.minutes(root.bells[p][1]);
                        const bellStart = root.minutes(root.bells[p + 1][0]);
                        if (t >= bellEnd && t < bellStart)
                            return { kind: "break", lesson: list[i], index: i, until: bellStart, from: bellEnd, inside: true };
                    }
                    return { kind: "class", lesson: list[i], index: i, from: start, until: end, next: list[i + 1] || null };
                }
                if (t < start)
                    return { kind: i === 0 ? "before" : "break", lesson: list[i], index: i, until: start, from: i === 0 ? t : root.endOf(list[i - 1]) };
            }
            if (list.length > 0)
                return root.nextDayStatus("after");
        }
        return root.nextDayStatus(root.todayIndex < 0 ? "weekend" : "after");
    }

    function nextDayStatus(kind) {
        for (let offset = 1; offset <= 7; offset++) {
            const d = new Date(root.now);
            d.setDate(d.getDate() + offset);
            const dow = d.getDay();
            if (dow === 0 || dow === 6)
                continue;
            const list = root.lessonsOf(dow - 1);
            if (list.length > 0)
                return { kind: kind, lesson: list[0], dayIndex: dow - 1, dayName: offset === 1 ? "Holnap" : root.dayLong[dow - 1] };
        }
        return { kind: kind, lesson: null };
    }

    // ── Homework: tasks and reminders from the Reminders panel ────────────
    property var reminders: [] // the Reminders panel's list: tasks and reminders
    property var userAliases: ({}) // from timetable.json

    function startOfDay(ms) {
        const d = new Date(ms);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    }

    // Words that mean a subject without starting like its name. Keys are
    // folded (no accents); values are the subject key's first four letters.
    readonly property var aliasMap: {
        const map = { nyelvtan: "magy", irodalom: "magy", fogalmazas: "magy", helyesiras: "magy", tori: "tort", tesi: "test", matek: "mate" };
        for (const subject in root.userAliases) {
            const key = root.subjectKey(subject).slice(0, 4);
            for (const word of root.userAliases[subject] || [])
                map[root.fold(String(word)).trim()] = key;
        }
        return map;
    }

    // Text is about a lesson when a word of it (or a tag) starts like the
    // subject or like one of its aliases: "matek doga" → Matematika,
    // "#angol" → Angol 11 tim, "nyelvtan" → Magyar.
    function textMatches(text, tags, lesson) {
        const key = root.subjectKey(lesson.subject).slice(0, 4);
        if (key.length < 3)
            return false;
        const words = root.fold(text).split(/[^a-z0-9]+/).concat((tags || []).map(root.fold));
        return words.some(w => {
            if (w.length < 3)
                return false;
            if (w.slice(0, 4) === key)
                return true;
            for (const alias in root.aliasMap)
                if (root.aliasMap[alias] === key && w.startsWith(alias))
                    return true;
            return false;
        });
    }

    function linkFor(lesson, dayIndex, date) {
        const start = new Date(date);
        start.setHours(0, root.startOf(lesson), 0, 0);
        return { date: date, day: dayIndex, p: [lesson.p[0], lesson.p[1]], subject: lesson.subject, start: start.getTime() };
    }

    // The lesson of that subject on a given day ("szerda nyelvtan").
    function lessonOnDate(text, dayMs) {
        const dow = new Date(dayMs).getDay();
        if (dow === 0 || dow === 6)
            return null;
        const lesson = root.lessonsOf(dow - 1).find(l => root.textMatches(text, [], l));
        return lesson ? root.linkFor(lesson, dow - 1, root.startOfDay(dayMs)) : null;
    }

    // The lesson starting at a time ("szerda 10:10"), give or take 5 min.
    function lessonAt(ms) {
        const date = root.startOfDay(ms);
        const dow = new Date(date).getDay();
        if (dow === 0 || dow === 6)
            return null;
        const at = new Date(ms);
        const mins = at.getHours() * 60 + at.getMinutes();
        const lesson = root.lessonsOf(dow - 1).find(l => Math.abs(root.startOf(l) - mins) <= 5);
        return lesson ? root.linkFor(lesson, dow - 1, date) : null;
    }

    // Everything due on a day, handed to the lesson it belongs to:
    //   tasks → the first lesson of that subject that day (that's when
    //   it's due); reminders linked from here → exactly their lesson;
    //   other reminders that day → the lesson of that subject nearest to
    //   when they ring.
    function homeworkOf(dayIndex) {
        const list = root.lessonsOf(dayIndex);
        const date = root.dateOf(dayIndex).getTime();
        const byLesson = list.map(() => []);
        const loose = [];

        for (const r of root.reminders) {
            const timed = typeof r.fireAt === "number";
            const item = { kind: timed ? "reminder" : "task", id: r.id, text: r.text, fireAt: timed ? r.fireAt : 0, date: date };
            let i = -1;
            if (r.lesson) {
                if (r.lesson.date !== date)
                    continue;
                i = list.findIndex(l => l.p[0] === r.lesson.p[0]);
            } else if (!timed) {
                if (r.due !== date)
                    continue;
                i = list.findIndex(l => root.textMatches(r.text, [], l));
            } else {
                if (r.repeat || root.startOfDay(r.fireAt) !== date)
                    continue;
                const at = new Date(r.fireAt);
                const mins = at.getHours() * 60 + at.getMinutes();
                let best = Infinity;
                list.forEach((l, k) => {
                    if (!root.textMatches(r.text, [], l))
                        return;
                    const d = Math.abs(root.startOf(l) - mins);
                    if (d < best) {
                        best = d;
                        i = k;
                    }
                });
            }
            if (i >= 0)
                byLesson[i].push(item);
            else
                loose.push(item);
        }
        return { byLesson: byLesson, loose: loose };
    }

    readonly property var weekHomework: {
        const out = [];
        for (let d = 0; d < 5; d++)
            out.push(root.homeworkOf(d));
        return out;
    }

    function itemsOfDay(dayIndex) {
        const hw = root.weekHomework[dayIndex];
        return hw ? [].concat(...hw.byLesson, hw.loose) : [];
    }

    // When a reminder rings, relative to the lesson's day.
    function reminderWhen(fireAt, lessonDate) {
        const day = root.startOfDay(fireAt);
        const time = Qt.formatTime(new Date(fireAt), "H:mm");
        const before = new Date(lessonDate);
        before.setDate(before.getDate() - 1);
        if (day === lessonDate)
            return time;
        if (day === before.getTime())
            return "előtte " + time;
        const d = new Date(fireAt).getDay();
        return (d >= 1 && d <= 5 ? root.dayShort[d - 1] : (d === 0 ? "V" : "Szo")) + " " + time;
    }

    // ── Reminder for a lesson ─────────────────────────────────────────────
    // The lesson's next occurrence (this week's if it's still ahead).
    readonly property var composeTarget: {
        if (root.composingLesson < 0)
            return null;
        const lesson = root.lessonsOf(root.selectedDay)[root.composingLesson];
        if (!lesson)
            return null;
        const date = root.dateOf(root.selectedDay);
        const start = new Date(date);
        start.setHours(0, root.startOf(lesson), 0, 0);
        if (start.getTime() <= Date.now()) {
            date.setDate(date.getDate() + 7);
            start.setDate(start.getDate() + 7);
        }
        return { lesson: lesson, day: root.selectedDay, date: date.getTime(), start: start.getTime(), nextWeek: date.getTime() !== root.dateOf(root.selectedDay).getTime() };
    }

    readonly property var composeOptions: {
        const t = root.composeTarget;
        if (!t)
            return [];
        const eve = new Date(t.date);
        eve.setDate(eve.getDate() - 1);
        eve.setHours(19, 0, 0, 0);
        const morning = new Date(t.date);
        morning.setHours(6, 30, 0, 0);
        const opts = [
            { label: "Este", at: eve.getTime() },
            { label: "Reggel", at: morning.getTime() },
            { label: "10 p előtte", at: t.start - 600000 },
            { label: "Kezdéskor", at: t.start }
        ];
        const now = Date.now();
        return [{ label: "Feladat", at: -1 }].concat(opts.filter(o => o.at > now && o.at <= t.start && (o.label !== "Reggel" || o.at < t.start - 20 * 60000)));
    }

    function openComposer(lessonIndex) {
        root.editingLesson = -1;
        root.selectedLesson = lessonIndex;
        root.composeWhen = 0;
        root.composingLesson = lessonIndex;
    }

    function closeComposer() {
        root.composingLesson = -1;
        keyScope.forceActiveFocus();
    }

    function commitComposer(text) {
        const t = root.composeTarget;
        const opt = root.composeOptions[Math.min(root.composeWhen, root.composeOptions.length - 1)];
        if (!t || !opt) {
            root.showToast("Ez az óra már elkezdődött");
            return;
        }
        const body = text.trim() !== "" ? text.trim() : t.lesson.subject;
        root.reminderRequested(body, opt.at, { date: t.date, day: t.day, p: [t.lesson.p[0], t.lesson.p[1]], subject: t.lesson.subject, start: t.start });
        root.showToast(opt.at < 0 ? "Feladat · " + t.lesson.subject + " " + root.dayShort[t.day] + " " + new Date(t.date).getDate() + "." : "Emlékeztető · " + opt.label.toLowerCase() + " (" + root.reminderWhen(opt.at, t.date) + ")");
        root.closeComposer();
    }

    // From the Reminders panel: show the lesson a reminder is for.
    function focusLesson(link) {
        root.pendingLesson = link;
        if (root.visible)
            root.applyPendingLesson();
    }

    function applyPendingLesson() {
        const link = root.pendingLesson;
        root.pendingLesson = null;
        if (!link)
            return;
        root.weekView = false;
        root.highlightJump = true;
        dayList.currentIndex = -1;
        root.selectedDay = Math.max(0, Math.min(4, link.day));
        root.selectedLesson = root.lessonsOf(root.selectedDay).findIndex(l => l.p[0] === link.p[0]);
        root.editingLesson = -1;
        root.composingLesson = -1;
        Qt.callLater(root.syncHighlight);
    }

    // For the Reminders panel's "matek óra előtt": the next lesson a text
    // is about, within the next two weeks.
    function nextLessonFor(text) {
        const now = Date.now();
        const today = new Date();
        for (let offset = 0; offset < 14; offset++) {
            const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset);
            const dow = date.getDay();
            if (dow === 0 || dow === 6)
                continue;
            for (const lesson of root.lessonsOf(dow - 1)) {
                if (!root.textMatches(text, [], lesson))
                    continue;
                const start = new Date(date);
                start.setHours(0, root.startOf(lesson), 0, 0);
                if (start.getTime() > now)
                    return { date: date.getTime(), day: dow - 1, p: [lesson.p[0], lesson.p[1]], subject: lesson.subject, start: start.getTime() };
            }
        }
        return null;
    }

    // ── Rows for the day view ─────────────────────────────────────────────
    // Structure only — nothing here depends on the clock, so the list is not
    // rebuilt (and its scroll/selection reset) every tick. Live state is
    // worked out per row in the delegate.
    readonly property var dayRows: {
        const rows = [];
        const list = root.lessonsOf(root.selectedDay);
        const hw = root.weekHomework[root.selectedDay];
        for (let i = 0; i < list.length; i++) {
            const lesson = list[i];
            if (i > 0) {
                const prevEnd = root.endOf(list[i - 1]);
                const gapPeriods = lesson.p[0] - list[i - 1].p[1] - 1;
                rows.push({ kind: gapPeriods > 0 ? "free" : "break", from: prevEnd, until: root.startOf(lesson), periods: gapPeriods });
            }
            rows.push({ kind: "lesson", index: i, lesson: lesson, start: root.startOf(lesson), end: root.endOf(lesson), items: hw.byLesson[i] || [] });
        }
        return rows;
    }

    readonly property int selectedRow: root.dayRows.findIndex(r => r.kind === "lesson" && r.index === root.selectedLesson)

    // True while a day switch is settling: the highlight is hidden and then
    // placed directly, instead of sitting on (or sliding across) whatever row
    // of the new day has the old index — often a break spacer.
    property bool highlightJump: false

    function syncHighlight() {
        const row = root.selectedRow;
        dayList.currentIndex = row >= 0 && row < dayList.count && root.dayRows[row].kind === "lesson" ? row : -1;
        if (root.highlightJump)
            Qt.callLater(() => root.highlightJump = false);
    }

    onSelectedRowChanged: Qt.callLater(root.syncHighlight)
    onDayRowsChanged: Qt.callLater(root.syncHighlight)

    // ── Edits ─────────────────────────────────────────────────────────────
    function setNote(dayIndex, lessonIndex, note) {
        const sorted = root.lessonsOf(dayIndex);
        const target = sorted[lessonIndex];
        if (!target)
            return;
        const days = root.days.map((day, d) => d !== dayIndex ? day : day.map(l => l === target ? Object.assign({}, l, { note: note.trim() }) : l));
        root.days = days;
        root.writeFile();
        root.showToast(note.trim() === "" ? "Note removed" : "Note saved");
    }

    function writeFile() {
        const data = { _help: root.helpText, bells: root.bells, aliases: root.userAliases, days: root.days };
        timetableFile.setText(JSON.stringify(data, null, 2) + "\n");
    }

    readonly property string helpText: "Órarend for the island (Super+O). p = [first, last] period index into bells (0-based; 0 = the 7:20 period). Saved edits reload live."

    function openEditor() {
        if (root.missing) {
            root.bells = [["8:00", "8:45"], ["8:55", "9:40"], ["9:50", "10:35"], ["10:50", "11:35"], ["11:45", "12:30"], ["12:40", "13:25"], ["13:35", "14:20"]];
            root.days = [[{ p: [0, 0], subject: "Matematika", teacher: "", room: "", note: "" }], [], [], [], []];
            root.writeFile();
        }
        Quickshell.execDetached(["kitty", "-e", "nvim", root.filePath]);
        root.closeRequested();
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    // keepPlace: land on the lesson at the same period in the new day
    // (or the nearest one), so ←/→ answers "what's at this time on Kedd?".
    function selectDay(index, keepPlace) {
        const target = Math.max(0, Math.min(4, index));
        if (target === root.selectedDay)
            return;
        const previous = root.lessonsOf(root.selectedDay)[root.selectedLesson] || null;
        const direction = target > root.selectedDay ? 1 : -1;
        root.editingLesson = -1;
        root.composingLesson = -1;
        root.highlightJump = true;
        dayList.currentIndex = -1;
        root.selectedDay = target;

        let pick = -1;
        if (keepPlace && previous) {
            const list = root.lessonsOf(target);
            let best = Infinity;
            list.forEach((lesson, i) => {
                const distance = previous.p[0] >= lesson.p[0] && previous.p[0] <= lesson.p[1] ? -1 : Math.min(Math.abs(lesson.p[0] - previous.p[0]), Math.abs(lesson.p[1] - previous.p[0]));
                if (distance < best) {
                    best = distance;
                    pick = i;
                }
            });
        }
        root.selectedLesson = pick;
        daySwap.direction = direction;
        daySwap.restart();
        Qt.callLater(root.syncHighlight);
    }

    function moveLesson(delta) {
        const count = root.lessonsOf(root.selectedDay).length;
        if (count === 0)
            return;
        root.selectedLesson = root.selectedLesson < 0 ? (delta > 0 ? 0 : count - 1) : Math.max(0, Math.min(count - 1, root.selectedLesson + delta));
    }

    function goToday() {
        root.now = new Date();
        root.weekView = false;
        root.highlightJump = true;
        dayList.currentIndex = -1;
        root.selectedDay = root.todayIndex >= 0 ? root.todayIndex : (root.status.dayIndex !== undefined ? root.status.dayIndex : 0);
        root.selectedLesson = -1;
        root.editingLesson = -1;
        root.composingLesson = -1;
        if (root.todayIndex >= 0 && root.status.index !== undefined && (root.status.kind === "class" || root.status.kind === "break" || root.status.kind === "before"))
            root.selectedLesson = root.status.index;
        Qt.callLater(root.syncHighlight);
    }

    // ── Files ─────────────────────────────────────────────────────────────
    readonly property string filePath: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/timetable.json"

    function applyTimetable(text) {
        try {
            const data = JSON.parse(text);
            if (Array.isArray(data.bells))
                root.bells = data.bells.filter(b => Array.isArray(b) && b.length === 2);
            if (Array.isArray(data.days)) {
                const days = [];
                for (let d = 0; d < 5; d++) {
                    const list = Array.isArray(data.days[d]) ? data.days[d] : [];
                    days.push(list.filter(l => l && Array.isArray(l.p) && typeof l.subject === "string").map(l => ({
                        p: [Number(l.p[0]), Number(l.p[l.p.length - 1])],
                        subject: l.subject,
                        teacher: typeof l.teacher === "string" ? l.teacher : "",
                        room: typeof l.room === "string" ? l.room : "",
                        note: typeof l.note === "string" ? l.note : ""
                    })).filter(l => root.bells[l.p[0]] && root.bells[l.p[1]]));
                }
                root.days = days;
            }
            root.userAliases = data.aliases && typeof data.aliases === "object" && !Array.isArray(data.aliases) ? data.aliases : ({});
            root.missing = false;
        } catch (error) {
            root.showToast("timetable.json has an error — showing the last good version");
        }
        root.loaded = true;
    }

    FileView {
        id: timetableFile

        path: root.filePath
        preload: true
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyTimetable(timetableFile.text())
        onFileChanged: timetableFile.reload()
        onLoadFailed: {
            root.missing = true;
            root.loaded = true;
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.visible
        onTriggered: root.now = new Date()
    }

    Timer {
        id: toastTimer

        interval: 2400
        onTriggered: root.toast = ""
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            root.goToday();
            if (root.pendingLesson)
                root.applyPendingLesson();
            keyScope.forceActiveFocus();
        } else {
            root.editingLesson = -1;
            root.composingLesson = -1;
        }
    }

    // ── Components ────────────────────────────────────────────────────────

    component IconButton: Rectangle {
        id: iconButton

        required property string icon
        property bool active: false

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
            color: iconButton.active ? root.accentColor : "#a8a8a8"
        }

        MouseArea {
            id: iconMouse

            anchors.fill: parent
            onClicked: iconButton.clicked()
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    FocusScope {
        id: keyScope

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const key = event.key;
            if (key === Qt.Key_Escape) {
                if (root.selectedLesson >= 0 && !root.weekView)
                    root.selectedLesson = -1;
                else
                    root.closeRequested();
            } else if (key === Qt.Key_Left)
                root.selectDay(root.selectedDay - 1, true);
            else if (key === Qt.Key_Right)
                root.selectDay(root.selectedDay + 1, true);
            else if (key >= Qt.Key_1 && key <= Qt.Key_5)
                root.selectDay(key - Qt.Key_1, true);
            else if (key === Qt.Key_Up)
                root.moveLesson(-1);
            else if (key === Qt.Key_Down)
                root.moveLesson(1);
            else if ((key === Qt.Key_Return || key === Qt.Key_Enter) && root.weekView)
                root.weekView = false;
            else if (key === Qt.Key_W || key === Qt.Key_Tab)
                root.weekView = !root.weekView;
            else if (key === Qt.Key_T)
                root.goToday();
            else if (key === Qt.Key_E)
                root.openEditor();
            else if ((key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_N) && !root.weekView && root.selectedLesson >= 0) {
                root.composingLesson = -1;
                root.editingLesson = root.selectedLesson;
            } else if (key === Qt.Key_R && root.selectedLesson >= 0) {
                root.weekView = false;
                root.openComposer(root.selectedLesson);
            }
            else if (key === Qt.Key_Delete && !root.weekView && root.selectedLesson >= 0)
                root.setNote(root.selectedDay, root.selectedLesson, "");
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
                        anchors.centerIn: parent
                        name: "school"
                        size: 17
                        color: root.primaryText
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        width: 6
                        height: 6
                        radius: 3
                        color: root.accentColor
                        visible: root.status.kind === "class"

                        SequentialAnimation on opacity {
                            running: root.visible && root.status.kind === "class"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "Órarend"
                        color: root.primaryText
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const d = root.now;
                            const months = ["január", "február", "március", "április", "május", "június", "július", "augusztus", "szeptember", "október", "november", "december"];
                            const names = ["vasárnap", "hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat"];
                            return months[d.getMonth()] + " " + d.getDate() + ", " + names[d.getDay()] + "  ·  " + Qt.formatTime(d, "HH:mm");
                        }
                        color: root.secondaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }
                }

                IconButton {
                    icon: "today"
                    onClicked: root.goToday()
                }

                IconButton {
                    icon: root.weekView ? "view_agenda" : "calendar_view_week"
                    active: root.weekView
                    onClicked: root.weekView = !root.weekView
                }

                IconButton {
                    icon: "edit_calendar"
                    onClicked: root.openEditor()
                }

                IconButton {
                    icon: "close"
                    onClicked: root.closeRequested()
                }
            }

            // Live card
            Rectangle {
                id: nowCard

                readonly property var s: root.status
                readonly property var lesson: s.lesson
                readonly property color tint: s.kind === "class" && lesson ? root.subjectColor(lesson.subject) : (s.kind === "break" || s.kind === "before" ? root.accentColor : "#6a6a6a")
                readonly property real progress: s.kind === "class" || s.kind === "break" ? Math.max(0, Math.min(1, (root.nowMinutes() - s.from) / Math.max(1, s.until - s.from))) : 0

                Layout.fillWidth: true
                Layout.preferredHeight: root.nowHeight
                radius: 14
                color: root.cardColor
                border.width: 1
                border.color: Qt.rgba(nowCard.tint.r, nowCard.tint.g, nowCard.tint.b, 0.35)
                clip: true

                Behavior on border.color { ColorAnimation { duration: 300 } }

                // Progress wash
                Rectangle {
                    width: parent.width * nowCard.progress
                    height: parent.height
                    color: Qt.rgba(nowCard.tint.r, nowCard.tint.g, nowCard.tint.b, 0.08)

                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width * nowCard.progress
                    height: 2
                    color: nowCard.tint

                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goToday()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 12
                        color: Qt.rgba(nowCard.tint.r, nowCard.tint.g, nowCard.tint.b, 0.16)

                        MIcon {
                            anchors.centerIn: parent
                            name: ({ class: "menu_book", break: "coffee", before: "wb_twilight", after: "bedtime", weekend: "weekend" })[nowCard.s.kind]
                            size: 18
                            color: nowCard.tint
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: {
                                const s = nowCard.s;
                                const period = s.lesson ? (s.lesson.p[0] === s.lesson.p[1] ? s.lesson.p[0] + ". óra" : s.lesson.p[0] + "–" + s.lesson.p[1] + ". óra") : "";
                                switch (s.kind) {
                                case "class":
                                    return "MOST  ·  " + period;
                                case "break":
                                    return s.inside ? "SZÜNET  ·  dupla óra közben" : "SZÜNET  ·  következő: " + period;
                                case "before":
                                    return "MA  ·  első óra " + root.hhmm(root.startOf(s.lesson));
                                case "after":
                                    return "VÉGE MÁRA" + (s.lesson ? "  ·  " + s.dayName.toLowerCase() + " " + root.hhmm(root.startOf(s.lesson)) : "");
                                default:
                                    return "HÉTVÉGE" + (s.lesson ? "  ·  " + s.dayName.toLowerCase() + " " + root.hhmm(root.startOf(s.lesson)) : "");
                                }
                            }
                            color: nowCard.tint
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Black
                            font.letterSpacing: 1.3
                        }

                        Text {
                            Layout.fillWidth: true
                            text: nowCard.lesson ? nowCard.lesson.subject : "Nincs óra a héten"
                            color: root.primaryText
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: nowCard.lesson ? [nowCard.lesson.teacher, nowCard.lesson.room, nowCard.lesson.note].filter(x => x !== "").join("  ·  ") : ""
                            color: root.secondaryText
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    ColumnLayout {
                        spacing: 0

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: {
                                const s = nowCard.s;
                                if (s.kind === "class" || s.kind === "break" || s.kind === "before")
                                    return root.duration(s.until - root.nowMinutes());
                                return s.lesson ? root.hhmm(root.startOf(s.lesson)) : "";
                            }
                            color: root.primaryText
                            font.family: root.fontFamily
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: {
                                const s = nowCard.s;
                                if (s.kind === "class")
                                    return "van hátra  ·  csengő " + root.hhmm(s.until);
                                if (s.kind === "break" || s.kind === "before")
                                    return "múlva kezdődik";
                                return s.lesson ? s.dayName.toLowerCase() : "";
                            }
                            color: root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // Day tabs
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tabsHeight
                spacing: 6

                Repeater {
                    model: 5

                    Rectangle {
                        id: dayTab

                        required property int index

                        readonly property bool selected: root.selectedDay === index && !root.weekView
                        readonly property bool isToday: root.todayIndex === index
                        readonly property var dayItems: root.itemsOfDay(index)
                        readonly property int dueCount: dayItems.filter(i => i.kind === "task").length
                        readonly property int reminderCount: dayItems.filter(i => i.kind === "reminder").length

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: dayTab.selected ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13) : (tabHover.hovered ? "#121212" : root.cardColor)
                        border.width: 1
                        border.color: dayTab.selected ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55) : (dayTab.isToday ? "#2c2c2c" : root.cardBorder)
                        scale: tabMouse.pressed ? 0.94 : 1

                        Behavior on color { ColorAnimation { duration: 160 } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                        HoverHandler {
                            id: tabHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 1

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 4

                                Text {
                                    id: dayLetter

                                    text: root.dayShort[dayTab.index]
                                    color: dayTab.selected || dayTab.isToday ? root.accentColor : root.primaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Black
                                }

                                Text {
                                    anchors.baseline: dayLetter.baseline
                                    text: root.dateOf(dayTab.index).getDate() + "."
                                    color: root.secondaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.dayRange(dayTab.index)
                                color: root.faintText
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 5
                            spacing: 2

                            Rectangle {
                                visible: dayTab.reminderCount > 0
                                width: 6
                                height: 6
                                radius: 3
                                color: root.reminderColor
                            }

                            Rectangle {
                                visible: dayTab.dueCount > 0
                                width: 6
                                height: 6
                                radius: 3
                                color: root.taskColor
                            }
                        }

                        MouseArea {
                            id: tabMouse

                            anchors.fill: parent
                            onClicked: {
                                root.weekView = false;
                                root.selectDay(dayTab.index, true);
                            }
                        }
                    }
                }
            }

            // Body: day timeline or week grid
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.bodyHeight
                radius: 14
                color: root.cardColor
                border.width: 1
                border.color: root.cardBorder
                clip: true

                // Missing file / empty day
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: root.missing || (!root.weekView && root.dayRows.length === 0)

                    MIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: root.missing ? "edit_calendar" : "beach_access"
                        size: 28
                        color: "#333333"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.missing ? "No timetable yet" : "Nincs óra — " + root.dayLong[root.selectedDay].toLowerCase() + " szabad"
                        color: "#6a6a6a"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.missing
                        text: "Press E to create one"
                        color: "#444444"
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }
                }

                // ── Day view ──
                ListView {
                    id: dayList

                    anchors.fill: parent
                    anchors.margins: 5
                    // Clip to the list itself: clipped only by the card, rows
                    // scrolled past the top showed through its 5 px margin.
                    clip: true
                    visible: !root.weekView && !root.missing
                    opacity: visible ? 1 : 0
                    model: root.dayRows
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 2

                    // One highlight that glides between lessons, and a view
                    // that scrolls smoothly to keep it in sight.
                    // currentIndex is set once the rows have settled (see
                    // syncHighlight), not bound: a binding could apply the
                    // new day's row number to the old day's rows — landing on
                    // a break spacer — and ListView resets it on model changes.
                    currentIndex: -1
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: root.highlightJump ? 0 : 220
                    highlightMoveVelocity: -1
                    highlightResizeDuration: root.highlightJump ? 0 : 220
                    highlightResizeVelocity: -1
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: 34
                    preferredHighlightEnd: height - 34
                    highlight: Rectangle {
                        radius: 11
                        color: "#141414"
                        border.width: 1
                        border.color: "#2c2c2c"
                        visible: dayList.currentIndex >= 0 && !root.highlightJump
                    }

                    transform: Translate {
                        id: dayShift
                    }

                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    SequentialAnimation {
                        id: daySwap

                        property int direction: 1

                        PropertyAction { target: dayList; property: "opacity"; value: 0.2 }
                        PropertyAction { target: dayShift; property: "x"; value: daySwap.direction * 26 }
                        ParallelAnimation {
                            NumberAnimation { target: dayList; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation { target: dayShift; property: "x"; to: 0; duration: 280; easing.type: Easing.OutCubic }
                        }
                    }

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index

                        readonly property bool isLesson: modelData.kind === "lesson"
                        readonly property var lesson: isLesson ? modelData.lesson : null
                        readonly property bool isDouble: isLesson && lesson.p[1] > lesson.p[0]
                        readonly property bool selected: isLesson && root.selectedLesson === modelData.index
                        readonly property bool editing: isLesson && root.editingLesson === modelData.index
                        readonly property color tint: isLesson ? root.subjectColor(lesson.subject) : root.accentColor
                        readonly property var items: isLesson ? modelData.items : []
                        readonly property bool composing: isLesson && root.composingLesson === modelData.index
                        readonly property real base: isDouble ? 62 : 46
                        readonly property bool isToday: root.selectedDay === root.todayIndex
                        readonly property real from: isLesson ? modelData.start : modelData.from
                        readonly property real until: isLesson ? modelData.end : modelData.until
                        readonly property bool live: isToday && root.nowMinutes() >= from && root.nowMinutes() < until
                        readonly property bool past: isLesson && isToday && root.nowMinutes() >= until
                        readonly property real progress: live ? (root.nowMinutes() - from) / Math.max(1, until - from) : 0
                        // Short breaks are just a spacer unless you're in one.
                        readonly property bool compactGap: !isLesson && modelData.kind === "break" && !live && until - from < 20

                        width: dayList.width
                        height: isLesson ? base + (items.length > 0 ? 18 : 0) + (editing ? 34 : 0) + (composing ? 66 : 0) : (compactGap ? 6 : 22)

                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        // Free period / break
                        Row {
                            visible: !row.isLesson && !row.compactGap
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 1
                                color: row.live ? root.accentColor : "#262626"
                            }

                            MIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: row.modelData.kind === "free" ? "event_busy" : "coffee"
                                size: 11
                                color: row.live ? root.accentColor : "#4a4a4a"
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.isLesson ? "" : (row.modelData.kind === "free" ? "Lyukasóra" + (row.modelData.periods > 1 ? " ×" + row.modelData.periods : "") : "Szünet") + "  ·  " + root.hhmm(row.modelData.from) + "–" + root.hhmm(row.modelData.until) + (row.live ? "  ·  még " + root.duration(row.modelData.until - root.nowMinutes()) : "  ·  " + root.duration(row.modelData.until - row.modelData.from))
                                color: row.live ? root.accentColor : "#4f4f4f"
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        // Lesson card
                        Rectangle {
                            visible: row.isLesson
                            anchors.fill: parent
                            radius: 11
                            clip: true
                            color: row.live ? Qt.rgba(row.tint.r, row.tint.g, row.tint.b, 0.1) : (lessonHover.hovered && !row.selected ? "#0c0c0c" : "transparent")
                            border.width: row.live ? 1 : 0
                            border.color: Qt.rgba(row.tint.r, row.tint.g, row.tint.b, 0.45)
                            opacity: row.past && !row.selected ? 0.45 : 1

                            Behavior on color { ColorAnimation { duration: 160 } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            HoverHandler {
                                id: lessonHover
                            }

                            // Live progress fill
                            Rectangle {
                                visible: row.live
                                width: parent.width * row.progress
                                height: parent.height
                                color: Qt.rgba(row.tint.r, row.tint.g, row.tint.b, 0.08)

                                Behavior on width { NumberAnimation { duration: 600 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.selectedLesson === row.modelData.index)
                                        root.editingLesson = root.editingLesson === row.modelData.index ? -1 : row.modelData.index;
                                    else {
                                        root.selectedLesson = row.modelData.index;
                                        root.editingLesson = -1;
                                        root.composingLesson = -1;
                                    }
                                    keyScope.forceActiveFocus();
                                }
                            }

                            // Subject colour bar
                            Rectangle {
                                x: 0
                                y: 7
                                width: 3
                                height: (row.isDouble ? 62 : 46) - 14
                                radius: 1.5
                                color: row.tint
                            }

                            RowLayout {
                                x: 12
                                y: 0
                                width: parent.width - 24
                                height: row.isDouble ? 62 : 46
                                spacing: 12

                                // Period number
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 9
                                    color: Qt.rgba(row.tint.r, row.tint.g, row.tint.b, 0.14)

                                    Text {
                                        anchors.centerIn: parent
                                        text: row.lesson ? (row.isDouble ? row.lesson.p[0] + "–" + row.lesson.p[1] : row.lesson.p[0]) : ""
                                        color: row.tint
                                        font.family: root.fontFamily
                                        font.pixelSize: row.isDouble ? 9 : 11
                                        font.weight: Font.Black
                                    }
                                }

                                // Times
                                Column {
                                    Layout.preferredWidth: 36
                                    spacing: row.isDouble ? 10 : 1

                                    Text {
                                        text: row.isLesson ? root.hhmm(row.modelData.start) : ""
                                        color: root.primaryText
                                        font.family: root.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.features: { "tnum": 1 }
                                    }

                                    Text {
                                        text: row.isLesson ? root.hhmm(row.modelData.end) : ""
                                        color: root.faintText
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: row.lesson ? row.lesson.subject : ""
                                        color: root.primaryText
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }

                                    Row {
                                        spacing: 10

                                        Row {
                                            spacing: 3
                                            visible: row.lesson !== null && row.lesson.teacher !== ""

                                            MIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: "person"
                                                size: 11
                                                color: root.faintText
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: row.lesson ? row.lesson.teacher : ""
                                                color: root.secondaryText
                                                font.family: root.fontFamily
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Row {
                                            spacing: 3
                                            visible: row.lesson !== null && row.lesson.room !== ""

                                            MIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: "meeting_room"
                                                size: 11
                                                color: root.faintText
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: row.lesson ? row.lesson.room : ""
                                                color: root.secondaryText
                                                font.family: root.fontFamily
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Text {
                                            visible: row.isDouble
                                            text: "dupla óra"
                                            color: root.faintText
                                            font.family: root.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                // Note chip
                                Rectangle {
                                    visible: row.lesson !== null && row.lesson.note !== "" && !row.editing
                                    Layout.maximumWidth: 150
                                    implicitWidth: noteRow.implicitWidth + 14
                                    implicitHeight: 22
                                    radius: 7
                                    color: Qt.rgba(root.noteColor.r, root.noteColor.g, root.noteColor.b, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(root.noteColor.r, root.noteColor.g, root.noteColor.b, 0.35)
                                    clip: true

                                    Row {
                                        id: noteRow

                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 7
                                        spacing: 4

                                        MIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "sticky_note_2"
                                            size: 11
                                            color: root.noteColor
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.lesson ? row.lesson.note : ""
                                            color: root.noteColor
                                            width: Math.min(implicitWidth, 120)
                                            elide: Text.ElideRight
                                            font.family: root.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                // Set a reminder for this lesson
                                Rectangle {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    radius: 8
                                    visible: (lessonHover.hovered || row.selected) && !row.composing
                                    color: bellHover.hovered ? Qt.rgba(root.reminderColor.r, root.reminderColor.g, root.reminderColor.b, 0.18) : "transparent"
                                    border.width: 1
                                    border.color: bellHover.hovered ? Qt.rgba(root.reminderColor.r, root.reminderColor.g, root.reminderColor.b, 0.5) : "#232323"
                                    scale: bellHover.hovered ? 1.08 : 1

                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                                    HoverHandler {
                                        id: bellHover

                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    TapHandler {
                                        onTapped: root.openComposer(row.modelData.index)
                                    }

                                    MIcon {
                                        anchors.centerIn: parent
                                        name: "notification_add"
                                        size: 13
                                        color: bellHover.hovered ? root.reminderColor : "#8a8a8a"
                                    }
                                }

                                // Live: minutes left
                                Text {
                                    visible: row.live
                                    text: row.isLesson ? "még " + root.duration(row.modelData.end - root.nowMinutes()) : ""
                                    color: row.tint
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Black
                                }
                            }

                            // Homework: tasks due and reminders for this lesson
                            Flickable {
                                visible: row.items.length > 0
                                x: 86
                                y: row.base - 6
                                width: parent.width - 96
                                height: 18
                                clip: true
                                contentWidth: itemRow.implicitWidth
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.HorizontalFlick

                                Row {
                                    id: itemRow

                                    height: 18
                                    spacing: 6

                                    Repeater {
                                        model: row.items

                                        Rectangle {
                                            id: hwChip

                                            required property var modelData
                                            readonly property bool isTask: modelData.kind === "task"
                                            readonly property color tint: isTask ? root.taskColor : root.reminderColor

                                            anchors.verticalCenter: parent.verticalCenter
                                            width: hwRow.implicitWidth + 12
                                            height: 16
                                            radius: 5
                                            color: Qt.rgba(tint.r, tint.g, tint.b, hwHover.hovered ? 0.2 : 0.1)
                                            border.width: 1
                                            border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.3)

                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            HoverHandler {
                                                id: hwHover

                                                cursorShape: Qt.PointingHandCursor
                                            }

                                            TapHandler {
                                                onTapped: root.openReminderRequested(hwChip.modelData.id)
                                            }

                                            Row {
                                                id: hwRow

                                                anchors.centerIn: parent
                                                spacing: 3

                                                MIcon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: hwChip.isTask ? "assignment_late" : "notifications_active"
                                                    size: 10
                                                    color: hwChip.tint
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: hwChip.modelData.text
                                                    color: hwChip.tint
                                                    font.family: root.fontFamily
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: !hwChip.isTask
                                                    text: hwChip.isTask ? "" : root.reminderWhen(hwChip.modelData.fireAt, hwChip.modelData.date)
                                                    color: Qt.rgba(hwChip.tint.r, hwChip.tint.g, hwChip.tint.b, 0.7)
                                                    font.family: root.fontFamily
                                                    font.pixelSize: 9
                                                    font.features: { "tnum": 1 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Note editor
                            Rectangle {
                                visible: row.editing
                                x: 86
                                y: row.base + (row.items.length > 0 ? 18 : 0) - 2
                                width: parent.width - 98
                                height: 28
                                radius: 8
                                color: "#0a0a0a"
                                border.width: 1
                                border.color: Qt.rgba(root.noteColor.r, root.noteColor.g, root.noteColor.b, 0.5)

                                onVisibleChanged: {
                                    if (visible) {
                                        noteInput.text = row.lesson ? row.lesson.note : "";
                                        noteInput.forceActiveFocus();
                                        noteInput.selectAll();
                                    }
                                }

                                MIcon {
                                    id: noteIcon

                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "sticky_note_2"
                                    size: 12
                                    color: root.noteColor
                                }

                                TextInput {
                                    id: noteInput

                                    anchors.left: noteIcon.right
                                    anchors.right: parent.right
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.primaryText
                                    selectionColor: "#5a2a2a"
                                    clip: true
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    Keys.onReturnPressed: {
                                        // Close first: saving rebuilds the rows,
                                        // this one included.
                                        const index = row.modelData.index;
                                        const note = noteInput.text;
                                        root.editingLesson = -1;
                                        keyScope.forceActiveFocus();
                                        root.setNote(root.selectedDay, index, note);
                                    }
                                    Keys.onEnterPressed: {
                                        // Close first: saving rebuilds the rows,
                                        // this one included.
                                        const index = row.modelData.index;
                                        const note = noteInput.text;
                                        root.editingLesson = -1;
                                        keyScope.forceActiveFocus();
                                        root.setNote(root.selectedDay, index, note);
                                    }
                                    Keys.onEscapePressed: {
                                        root.editingLesson = -1;
                                        keyScope.forceActiveFocus();
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: noteInput.text === ""
                                        text: "Note for every " + root.dayLong[root.selectedDay].toLowerCase() + " " + (row.lesson ? row.lesson.subject : "") + " — Enter saves"
                                        color: "#555555"
                                        font: noteInput.font
                                        width: noteInput.width
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Reminder for this lesson
                            Column {
                                visible: row.composing
                                x: 86
                                y: row.base + (row.items.length > 0 ? 18 : 0) + (row.editing ? 34 : 0) - 2
                                width: parent.width - 98
                                spacing: 6

                                Rectangle {
                                    width: parent.width
                                    height: 28
                                    radius: 8
                                    color: "#0a0a0a"
                                    border.width: 1
                                    border.color: Qt.rgba(root.reminderColor.r, root.reminderColor.g, root.reminderColor.b, 0.55)

                                    onVisibleChanged: {
                                        if (visible) {
                                            reminderInput.text = "";
                                            reminderInput.forceActiveFocus();
                                        }
                                    }

                                    MIcon {
                                        id: bellIcon

                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "notification_add"
                                        size: 13
                                        color: root.reminderColor
                                    }

                                    TextInput {
                                        id: reminderInput

                                        anchors.left: bellIcon.right
                                        anchors.right: parent.right
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.primaryText
                                        selectionColor: "#4a2a6a"
                                        clip: true
                                        font.family: root.fontFamily
                                        font.pixelSize: 11
                                        Keys.onReturnPressed: root.commitComposer(reminderInput.text)
                                        Keys.onEnterPressed: root.commitComposer(reminderInput.text)
                                        Keys.onEscapePressed: root.closeComposer()
                                        Keys.onTabPressed: root.composeWhen = (root.composeWhen + 1) % Math.max(1, root.composeOptions.length)
                                        Keys.onBacktabPressed: root.composeWhen = (root.composeWhen - 1 + root.composeOptions.length) % Math.max(1, root.composeOptions.length)

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: reminderInput.text === ""
                                            text: "Házi, dolgozat, hozd a… — Enter  ·  Tab: feladat / emlékeztető"
                                            color: "#555555"
                                            font: reminderInput.font
                                            width: reminderInput.width
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Row {
                                    spacing: 5

                                    Repeater {
                                        model: row.composing ? root.composeOptions : []

                                        Rectangle {
                                            id: whenChip

                                            required property var modelData
                                            required property int index
                                            readonly property bool picked: root.composeWhen === index

                                            width: whenRow.implicitWidth + 14
                                            height: 22
                                            radius: 7
                                            color: whenChip.picked ? Qt.rgba(root.reminderColor.r, root.reminderColor.g, root.reminderColor.b, 0.18) : (whenHover.hovered ? "#161616" : "#0d0d0d")
                                            border.width: 1
                                            border.color: whenChip.picked ? Qt.rgba(root.reminderColor.r, root.reminderColor.g, root.reminderColor.b, 0.6) : "#222222"
                                            scale: whenChip.picked ? 1 : 0.97

                                            Behavior on color { ColorAnimation { duration: 140 } }
                                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                                            HoverHandler {
                                                id: whenHover

                                                cursorShape: Qt.PointingHandCursor
                                            }

                                            TapHandler {
                                                onTapped: {
                                                    root.composeWhen = whenChip.index;
                                                    reminderInput.forceActiveFocus();
                                                }
                                            }

                                            Row {
                                                id: whenRow

                                                anchors.centerIn: parent
                                                spacing: 4

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: whenChip.modelData.label
                                                    color: whenChip.picked ? root.reminderColor : "#9a9a9a"
                                                    font.family: root.fontFamily
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root.composeTarget && whenChip.modelData.at > 0 ? root.reminderWhen(whenChip.modelData.at, root.composeTarget.date).replace("előtte ", "") : "nem csörög"
                                                    color: whenChip.picked ? Qt.rgba(root.reminderColor.r, root.reminderColor.g, root.reminderColor.b, 0.75) : "#5a5a5a"
                                                    font.family: root.fontFamily
                                                    font.pixelSize: 10
                                                    font.features: { "tnum": 1 }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: root.composeTarget !== null && root.composeTarget.nextWeek
                                        text: "jövő hét"
                                        color: root.faintText
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: row.composing && root.composeOptions.length === 1
                                        text: "csak feladatként — már nem lehet előtte szólni"
                                        color: root.faintText
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Week grid ──
                Item {
                    id: weekGrid

                    readonly property int periods: root.bells.length
                    readonly property real labelWidth: 42
                    readonly property real headerH: 20
                    readonly property real colW: (width - labelWidth) / 5
                    readonly property real rowH: (height - headerH) / Math.max(1, periods)

                    anchors.fill: parent
                    anchors.margins: 8
                    visible: root.weekView && !root.missing
                    opacity: visible ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    // Day headers
                    Repeater {
                        model: 5

                        Text {
                            required property int index

                            x: weekGrid.labelWidth + index * weekGrid.colW
                            width: weekGrid.colW
                            height: weekGrid.headerH
                            horizontalAlignment: Text.AlignHCenter
                            text: root.dayShort[index] + "  " + root.dateOf(index).getDate() + "."
                            color: index === root.todayIndex ? root.accentColor : root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Black
                        }
                    }

                    // Period labels
                    Repeater {
                        model: weekGrid.periods

                        Column {
                            required property int index

                            x: 0
                            y: weekGrid.headerH + index * weekGrid.rowH + (weekGrid.rowH - height) / 2
                            width: weekGrid.labelWidth - 6

                            Text {
                                anchors.right: parent.right
                                text: index + "."
                                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Black
                            }

                            Text {
                                anchors.right: parent.right
                                text: root.bells[index] ? root.bells[index][0] : ""
                                color: root.faintText
                                font.family: root.fontFamily
                                font.pixelSize: 8
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    // Selected day's column
                    Rectangle {
                        x: weekGrid.labelWidth + root.selectedDay * weekGrid.colW
                        y: 0
                        width: weekGrid.colW
                        height: weekGrid.height
                        radius: 9
                        color: "#101010"
                        border.width: 1
                        border.color: "#1f1f1f"

                        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }

                    // Now line across today's column
                    Rectangle {
                        readonly property real y0: {
                            const t = root.nowMinutes();
                            for (let p = 0; p < root.bells.length; p++) {
                                const s = root.minutes(root.bells[p][0]);
                                const e = root.minutes(root.bells[p][1]);
                                if (t >= s && t < e)
                                    return weekGrid.headerH + (p + (t - s) / (e - s)) * weekGrid.rowH;
                                const next = root.bells[p + 1] ? root.minutes(root.bells[p + 1][0]) : e;
                                if (t >= e && t < next)
                                    return weekGrid.headerH + (p + 1) * weekGrid.rowH;
                            }
                            return -10;
                        }

                        visible: root.todayIndex >= 0 && y0 > 0
                        z: 5
                        x: weekGrid.labelWidth + root.todayIndex * weekGrid.colW - 3
                        y: y0 - 1
                        width: weekGrid.colW + 6
                        height: 2
                        radius: 1
                        color: root.accentColor

                        Rectangle {
                            x: -3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: root.accentColor
                        }
                    }

                    // Lessons
                    Repeater {
                        model: {
                            const cells = [];
                            for (let d = 0; d < 5; d++)
                                root.lessonsOf(d).forEach((lesson, i) => cells.push({ day: d, index: i, lesson: lesson }));
                            return cells;
                        }

                        Rectangle {
                            id: cell

                            required property var modelData

                            readonly property var lesson: modelData.lesson
                            readonly property color tint: root.subjectColor(lesson.subject)
                            readonly property bool live: modelData.day === root.todayIndex && root.status.kind === "class" && root.status.lesson === lesson
                            readonly property bool hasNote: lesson.note !== ""
                            readonly property var homework: (root.weekHomework[modelData.day] || { byLesson: [] }).byLesson[modelData.index] || []
                            readonly property bool hasTask: homework.some(h => h.kind === "task")
                            readonly property bool hasReminder: homework.some(h => h.kind === "reminder")
                            readonly property bool picked: modelData.day === root.selectedDay && modelData.index === root.selectedLesson

                            x: weekGrid.labelWidth + modelData.day * weekGrid.colW + 2
                            y: weekGrid.headerH + lesson.p[0] * weekGrid.rowH + 1
                            width: weekGrid.colW - 4
                            height: (lesson.p[1] - lesson.p[0] + 1) * weekGrid.rowH - 2
                            radius: 7
                            color: Qt.rgba(cell.tint.r, cell.tint.g, cell.tint.b, cellHover.hovered ? 0.3 : (cell.live ? 0.32 : 0.16))
                            border.width: cell.picked ? 2 : (cell.live ? 1.5 : 0)
                            border.color: cell.picked ? "#f7f7f7" : cell.tint
                            z: cell.picked ? 3 : 1
                            opacity: modelData.day === root.todayIndex && root.endOf(lesson) <= root.nowMinutes() ? 0.5 : 1
                            scale: cellMouse.pressed ? 0.95 : 1

                            Behavior on color { ColorAnimation { duration: 140 } }
                            Behavior on scale { NumberAnimation { duration: 140 } }

                            HoverHandler {
                                id: cellHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            Rectangle {
                                x: 0
                                y: 3
                                width: 2
                                height: parent.height - 6
                                radius: 1
                                color: cell.tint
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 12
                                verticalAlignment: Text.AlignVCenter
                                text: cell.lesson.subject.replace(/\s+\d+.*$/, "").replace(/ I+\.?$/, "")
                                color: root.primaryText
                                elide: Text.ElideRight
                                wrapMode: cell.height > weekGrid.rowH * 1.5 ? Text.Wrap : Text.NoWrap
                                maximumLineCount: 2
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }

                            Column {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 3
                                spacing: 2

                                Rectangle {
                                    visible: cell.hasNote
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: root.noteColor
                                }

                                Rectangle {
                                    visible: cell.hasTask
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: root.taskColor
                                }

                                Rectangle {
                                    visible: cell.hasReminder
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: root.reminderColor
                                }
                            }

                            MouseArea {
                                id: cellMouse

                                anchors.fill: parent
                                onClicked: {
                                    root.weekView = false;
                                    root.highlightJump = true;
                                    dayList.currentIndex = -1;
                                    root.selectedDay = cell.modelData.day;
                                    root.selectedLesson = cell.modelData.index;
                                    Qt.callLater(root.syncHighlight);
                                }
                            }
                        }
                    }
                }
            }

            // Homework on the selected day
            Flickable {
                id: dueLine

                readonly property var due: root.itemsOfDay(root.selectedDay)

                Layout.fillWidth: true
                Layout.preferredHeight: root.tasksHeight
                clip: true
                contentWidth: dueRow.implicitWidth
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: dueRow

                    height: dueLine.height
                    spacing: 8

                    MIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: dueLine.due.length > 0 ? "assignment_late" : "assignment_turned_in"
                        size: 13
                        color: dueLine.due.length > 0 ? root.taskColor : root.faintText
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dueLine.due.length > 0 ? root.dayLong[root.selectedDay] + ":" : "Nincs házi vagy emlékeztető " + root.dayTo[root.selectedDay]
                        color: dueLine.due.length > 0 ? root.taskColor : root.faintText
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Black
                    }

                    Repeater {
                        model: dueLine.due

                        Row {
                            id: dueItem

                            required property var modelData
                            readonly property bool isTask: modelData.kind === "task"

                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            MIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: dueItem.isTask ? "assignment" : "notifications"
                                size: 11
                                color: dueItem.isTask ? root.taskColor : root.reminderColor
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: dueItem.modelData.text
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold

                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.openReminderRequested(dueItem.modelData.id) }
                            }
                        }
                    }
                }
            }

            // Hint
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: root.hintHeight
                horizontalAlignment: Text.AlignHCenter
                text: root.toast !== "" ? root.toast : (root.weekView ? "←→ day  ·  ↑↓ lesson  ·  Enter or click opens it  ·  W day view  ·  E edit" : "←→ / 1–5 day  ·  ↑↓ lesson  ·  Enter note  ·  R reminder  ·  W week  ·  T today  ·  E edit")
                color: root.toast !== "" ? root.accentColor : root.faintText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }
}
