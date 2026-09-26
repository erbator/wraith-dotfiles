import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// To-do, with one smart input:
//   "Matek doga #suli !! péntek"   → tag suli, high priority, due Friday
//   "gym every monday"             → repeats: ticking it off makes next week's
//   "Angol házi holnap #angol"     → due tomorrow
// Views: Today (overdue + due today) · Upcoming · All · Done, filterable by
// tag. Each task opens into a drawer with steps (subtasks), quick due date
// and priority, and hands-off to Reminders ("remind me") and the Timer
// ("focus on this").
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested
    // Cross-panel hand-offs, opened by the shell.
    signal remindRequested(string text)
    signal focusRequested(string text)

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color overdueColor: "#f87171"
    readonly property color todayColor: "#fbbf24"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"
    readonly property var priorityColors: ["#3a3a3a", "#fbbf24", "#fb923c", "#f87171"]
    readonly property var tagPalette: ["#60a5fa", "#f472b6", "#fbbf24", "#a78bfa", "#34d399", "#fb923c", "#22d3ee", "#f87171"]

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int inputHeight: 42
    readonly property int assistHeight: 24
    readonly property int tabsHeight: 30
    readonly property int listHeight: 248
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 10

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.inputHeight + root.assistHeight + root.tabsHeight + root.listHeight + root.hintHeight + root.sectionSpacing * 6
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    property real now: Date.now()
    readonly property real today: root.startOfDay(root.now)

    // { id, text, done, doneAt, created, due, priority, tags[], repeat, steps[{id,text,done}], order }
    property var items: []
    property bool loaded: false
    property int idCounter: 0
    property var undoStack: []

    property string view: "all" // today | upcoming | all | done
    property string tagFilter: ""
    property string draft: ""
    property string editingId: ""
    property string selectedId: ""
    property string expandedId: ""
    property var justDone: ({}) // stays in place for a moment after ticking
    property string toast: ""
    property bool confirmClear: false

    readonly property var views: [
        { id: "today", label: "Today", icon: "today" },
        { id: "upcoming", label: "Upcoming", icon: "event_upcoming" },
        { id: "all", label: "All", icon: "checklist" },
        { id: "done", label: "Done", icon: "task_alt" }
    ]

    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    // ── Helpers ───────────────────────────────────────────────────────────
    function pad2(value) {
        return value < 10 ? "0" + value : String(value);
    }

    function startOfDay(ms) {
        const date = new Date(ms);
        return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    }

    function addDays(ms, days) {
        const date = new Date(ms);
        date.setDate(date.getDate() + days);
        return root.startOfDay(date.getTime());
    }

    function nextId() {
        root.idCounter += 1;
        return Date.now().toString(36) + "-" + root.idCounter;
    }

    function tagColor(tag) {
        let hash = 0;
        for (let i = 0; i < tag.length; i++)
            hash = (hash * 31 + tag.charCodeAt(i)) >>> 0;
        return root.tagPalette[hash % root.tagPalette.length];
    }

    function dueLabel(due) {
        if (due === null || due === undefined)
            return "";
        const diff = Math.round((due - root.today) / 86400000);
        if (diff < -1)
            return -diff + " days late";
        if (diff === -1)
            return "Yesterday";
        if (diff === 0)
            return "Today";
        if (diff === 1)
            return "Tomorrow";
        const date = new Date(due);
        if (diff < 7)
            return root.dayNames[date.getDay()];
        return root.monthNames[date.getMonth()] + " " + date.getDate();
    }

    function dueColor(due) {
        if (due === null || due === undefined)
            return root.secondaryText;
        if (due < root.today)
            return root.overdueColor;
        if (due === root.today)
            return root.todayColor;
        return root.secondaryText;
    }

    function repeatLabel(repeat) {
        if (!repeat)
            return "";
        const names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        switch (repeat.kind) {
        case "day":
            return "Daily";
        case "weekday":
            return "Weekdays";
        case "week":
            return repeat.dow !== undefined ? "Every " + names[repeat.dow] : "Weekly";
        case "month":
            return "Monthly";
        }
        return "";
    }

    function nextDue(due, repeat) {
        let base = due !== null && due !== undefined ? due : root.today;
        let date = new Date(base);
        do {
            if (repeat.kind === "month")
                date.setMonth(date.getMonth() + 1);
            else if (repeat.kind === "week")
                date.setDate(date.getDate() + 7);
            else {
                date.setDate(date.getDate() + 1);
                if (repeat.kind === "weekday")
                    while (date.getDay() === 0 || date.getDay() === 6)
                        date.setDate(date.getDate() + 1);
            }
        } while (root.startOfDay(date.getTime()) <= root.today)
        return root.startOfDay(date.getTime());
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    // ── Parser ────────────────────────────────────────────────────────────
    // Pulls #tags, !/!!/!!! priority, a due day and a repeat out of the
    // text; whatever is left is the task. English and Hungarian day words.
    function parseTask(raw) {
        const W = "a-z0-9áéíóöőúüű_";
        const pre = "(?:^|[^" + W + "])";
        const post = "(?=$|[^" + W + "])";
        let work = raw.toLowerCase();
        let orig = raw;
        const result = { tags: [], priority: 0, due: null, repeat: null, hasDue: false };

        const blank = (index, length) => {
            const spaces = " ".repeat(length);
            work = work.slice(0, index) + spaces + work.slice(index + length);
            orig = orig.slice(0, index) + spaces + orig.slice(index + length);
        };
        const take = source => {
            const match = new RegExp(pre + "(?:" + source + ")" + post).exec(work);
            if (match)
                blank(match.index, match[0].length);
            return match;
        };

        // Tags
        let tagMatch;
        const tagRegex = /(^|\s)#([^\s#!]+)/g;
        const found = [];
        while ((tagMatch = tagRegex.exec(work)) !== null)
            found.push({ index: tagMatch.index + tagMatch[1].length, length: tagMatch[2].length + 1, tag: tagMatch[2] });
        for (const t of found) {
            if (result.tags.indexOf(t.tag) === -1)
                result.tags.push(t.tag);
            blank(t.index, t.length);
        }

        // Priority
        const priorityMatch = /(^|\s)(!{1,3})(?=\s|$)/.exec(work);
        if (priorityMatch) {
            result.priority = priorityMatch[2].length;
            blank(priorityMatch.index + priorityMatch[1].length, priorityMatch[2].length);
        }

        const enDays = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun";
        const huDays = "hétfő[a-záéíóöőúüű]*|kedd[a-záéíóöőúüű]*|szerd[a-záéíóöőúüű]*|csütörtök[a-záéíóöőúüű]*|péntek[a-záéíóöőúüű]*|szombat[a-záéíóöőúüű]*|vasárnap[a-záéíóöőúüű]*";
        const dowOf = word => {
            const hu = [["vasár", 0], ["hétf", 1], ["kedd", 2], ["szerd", 3], ["csüt", 4], ["pént", 5], ["szomb", 6]];
            for (const [stem, dow] of hu)
                if (word.startsWith(stem))
                    return dow;
            return ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(word.slice(0, 3));
        };
        const dayAfter = dow => {
            const diff = (dow - new Date(root.today).getDay() + 7) % 7;
            return root.addDays(root.today, diff === 0 ? 7 : diff);
        };

        // Repeat
        let m;
        if ((m = take("every\\s+(" + enDays + ")|minden\\s+(" + huDays + ")"))) {
            const dow = dowOf(m[1] || m[2]);
            result.repeat = { kind: "week", dow: dow };
            result.due = dayAfter(dow);
            if (dow === new Date(root.today).getDay())
                result.due = root.today;
        } else if (take("every\\s+(?:weekday|weekdays|workday)|hétköznap(?:onként)?")) {
            result.repeat = { kind: "weekday" };
        } else if (take("every\\s+day|everyday|daily|naponta|minden\\s+nap")) {
            result.repeat = { kind: "day" };
        } else if (take("every\\s+week|weekly|hetente")) {
            result.repeat = { kind: "week" };
        } else if (take("every\\s+month|monthly|havonta")) {
            result.repeat = { kind: "month" };
        }

        // Due day
        if (result.due === null) {
            if (take("day\\s+after\\s+tomorrow|holnapután"))
                result.due = root.addDays(root.today, 2);
            else if (take("tomorrow|tmrw|tmr|holnap(?:ra)?"))
                result.due = root.addDays(root.today, 1);
            else if (take("today|tonight|ma|mára"))
                result.due = root.today;
            else if (take("next\\s+week|jövő\\s+héten|jövő\\s+hét"))
                result.due = root.addDays(root.today, ((8 - new Date(root.today).getDay()) % 7) || 7);
            else if ((m = take("in\\s+(\\d+)\\s*(?:days?|d)|(\\d+)\\s*nap\\s*múlva")))
                result.due = root.addDays(root.today, parseInt(m[1] || m[2], 10));
            else if ((m = take("(?:next\\s+|on\\s+|by\\s+)?(" + enDays + ")|(" + huDays + ")")))
                result.due = dayAfter(dowOf(m[1] || m[2]));
            else if ((m = take("(\\d{4})[.\\-/](\\d{1,2})[.\\-/](\\d{1,2})\\.?")))
                result.due = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10)).getTime();
            else if ((m = take("(\\d{1,2})[./](\\d{1,2})\\.?"))) {
                let due = new Date(new Date(root.today).getFullYear(), parseInt(m[1], 10) - 1, parseInt(m[2], 10)).getTime();
                if (due < root.today)
                    due = new Date(new Date(root.today).getFullYear() + 1, parseInt(m[1], 10) - 1, parseInt(m[2], 10)).getTime();
                result.due = due;
            }
        }
        if (result.repeat && result.due === null)
            result.due = root.today;
        result.hasDue = result.due !== null;

        let text = orig.replace(/\s+/g, " ").trim();
        for (let i = 0; i < 3; i++)
            text = text.replace(/^(on|by|due|for|-|,|:)\s+|\s+(on|by|due|for|-|,)$|^[-,:]+|[-,:]+$/i, "").trim();
        result.text = text;
        return result;
    }

    function phraseFor(item) {
        let phrase = item.text;
        for (const tag of item.tags || [])
            phrase += " #" + tag;
        if (item.priority > 0)
            phrase += " " + "!".repeat(item.priority);
        if (item.repeat) {
            const names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
            phrase += " " + (item.repeat.kind === "week" && item.repeat.dow !== undefined ? "every " + names[item.repeat.dow] : ({ day: "every day", weekday: "every weekday", week: "every week", month: "every month" })[item.repeat.kind]);
        } else if (item.due !== null && item.due !== undefined) {
            if (item.due === root.today)
                phrase += " today";
            else if (item.due === root.addDays(root.today, 1))
                phrase += " tomorrow";
            else {
                const date = new Date(item.due);
                phrase += " " + date.getFullYear() + "." + root.pad2(date.getMonth() + 1) + "." + root.pad2(date.getDate());
            }
        }
        return phrase;
    }

    readonly property var parsed: root.draft.trim() === "" ? null : root.parseTask(root.draft)

    // ── Derived lists ─────────────────────────────────────────────────────
    function isOpen(item) {
        return !item.done || root.justDone[item.id] === true;
    }

    function matchesTag(item) {
        return root.tagFilter === "" || (item.tags || []).indexOf(root.tagFilter) !== -1;
    }

    function byPriority(a, b) {
        if (a.priority !== b.priority)
            return b.priority - a.priority;
        const ad = a.due === null ? Infinity : a.due;
        const bd = b.due === null ? Infinity : b.due;
        if (ad !== bd)
            return ad - bd;
        return a.order - b.order;
    }

    readonly property var openItems: root.items.filter(item => root.isOpen(item) && root.matchesTag(item))
    readonly property var doneItems: root.items.filter(item => item.done && root.matchesTag(item))
    readonly property int overdueCount: root.items.filter(item => !item.done && item.due !== null && item.due < root.today).length
    readonly property int todayOpen: root.items.filter(item => !item.done && item.due !== null && item.due <= root.today).length
    readonly property int doneToday: root.items.filter(item => item.done && item.doneAt >= root.today).length
    readonly property real todayProgress: root.todayOpen + root.doneToday > 0 ? root.doneToday / (root.todayOpen + root.doneToday) : (root.items.length > 0 ? root.items.filter(i => i.done).length / root.items.length : 0)

    readonly property var counts: ({
        today: root.openItems.filter(i => i.due !== null && i.due <= root.today).length,
        upcoming: root.openItems.filter(i => i.due !== null && i.due > root.today).length,
        all: root.openItems.length,
        done: root.doneItems.length
    })

    readonly property var allTags: {
        const counts = {};
        for (const item of root.items)
            if (!item.done)
                for (const tag of item.tags || [])
                    counts[tag] = (counts[tag] || 0) + 1;
        return Object.keys(counts).sort((a, b) => counts[b] - counts[a]).map(tag => ({ tag: tag, count: counts[tag] }));
    }

    readonly property var rows: {
        const rows = [];
        const push = (label, list, tone) => {
            if (list.length === 0)
                return;
            rows.push({ kind: "header", key: "h-" + label, label: label, count: list.length, tone: tone || "" });
            for (const item of list)
                rows.push({ kind: "task", key: item.id, item: item });
        };

        if (root.view === "done") {
            const done = root.doneItems.slice().sort((a, b) => (b.doneAt || 0) - (a.doneAt || 0));
            push("Today", done.filter(i => (i.doneAt || 0) >= root.today), "accent");
            push("Earlier", done.filter(i => (i.doneAt || 0) < root.today));
            return rows;
        }

        const open = root.openItems.slice().sort(root.byPriority);
        const overdue = open.filter(i => i.due !== null && i.due < root.today);
        const dueToday = open.filter(i => i.due === root.today);

        if (root.view === "today") {
            push("Overdue", overdue, "overdue");
            push("Today", dueToday, "today");
        } else if (root.view === "upcoming") {
            const later = open.filter(i => i.due !== null && i.due > root.today).sort((a, b) => a.due - b.due || root.byPriority(a, b));
            let day = null;
            let bucket = [];
            for (const item of later) {
                if (item.due !== day) {
                    push(root.dueLabel(day), bucket);
                    bucket = [];
                    day = item.due;
                }
                bucket.push(item);
            }
            push(root.dueLabel(day), bucket);
        } else {
            push("Overdue", overdue, "overdue");
            push("Today", dueToday, "today");
            push("Tomorrow", open.filter(i => i.due === root.addDays(root.today, 1)));
            push("Later", open.filter(i => i.due !== null && i.due > root.addDays(root.today, 1)));
            push("Someday", open.filter(i => i.due === null));
        }
        return rows;
    }

    readonly property var itemById: {
        const map = {};
        for (const i of root.items)
            map[i.id] = i;
        return map;
    }

    // The ListView runs on a ListModel patched row by row (not the JS array
    // directly), so rows survive changes and ticks/strikes get to animate.
    ListModel {
        id: rowModel
    }

    function syncRows() {
        const next = root.rows.map(r => ({ kind: r.kind, rowKey: r.key, label: r.label || "", count: r.count || 0, tone: r.tone || "" }));
        const wanted = {};
        for (const r of next)
            wanted[r.rowKey] = true;
        for (let i = rowModel.count - 1; i >= 0; i--)
            if (!wanted[rowModel.get(i).rowKey])
                rowModel.remove(i);
        for (let i = 0; i < next.length; i++) {
            if (i < rowModel.count && rowModel.get(i).rowKey === next[i].rowKey) {
                const current = rowModel.get(i);
                if (current.label !== next[i].label || current.count !== next[i].count || current.tone !== next[i].tone)
                    rowModel.set(i, next[i]);
                continue;
            }
            let found = -1;
            for (let j = i + 1; j < rowModel.count; j++)
                if (rowModel.get(j).rowKey === next[i].rowKey) {
                    found = j;
                    break;
                }
            if (found >= 0) {
                rowModel.move(found, i, 1);
                rowModel.set(i, next[i]);
            } else {
                rowModel.insert(i, next[i]);
            }
        }
    }

    onRowsChanged: Qt.callLater(root.syncRows)

    readonly property var taskKeys: root.rows.filter(row => row.kind === "task").map(row => row.key)
    readonly property string currentKey: root.taskKeys.indexOf(root.selectedId) !== -1 ? root.selectedId : (root.taskKeys.length > 0 ? root.taskKeys[0] : "")

    function item(id) {
        return root.items.find(i => i.id === id) || null;
    }

    function moveSelection(delta) {
        const keys = root.taskKeys;
        if (keys.length === 0)
            return;
        root.selectedId = keys[Math.max(0, Math.min(keys.length - 1, keys.indexOf(root.currentKey) + delta))];
        const rowIndex = root.rows.findIndex(row => row.key === root.selectedId);
        if (rowIndex >= 0)
            list.positionViewAtIndex(rowIndex, ListView.Contain);
    }

    // ── Mutations ─────────────────────────────────────────────────────────
    function snapshot() {
        root.undoStack = root.undoStack.concat([JSON.stringify(root.items)]).slice(-25);
    }

    function undo() {
        if (root.undoStack.length === 0) {
            root.showToast("Nothing to undo");
            return;
        }
        root.items = JSON.parse(root.undoStack[root.undoStack.length - 1]);
        root.undoStack = root.undoStack.slice(0, -1);
        root.justDone = ({});
        root.showToast("Undone");
        root.save();
    }

    function update(id, patch) {
        root.items = root.items.map(i => i.id === id ? Object.assign({}, i, patch) : i);
        root.save();
    }

    function commit() {
        const result = root.parsed;
        if (!result || result.text === "") {
            if (root.draft.trim() !== "")
                shake.restart();
            return;
        }
        root.snapshot();

        if (root.editingId !== "") {
            root.update(root.editingId, { text: result.text, tags: result.tags, priority: result.priority, due: result.due, repeat: result.repeat });
            root.selectedId = root.editingId;
            root.showToast("Saved");
            root.editingId = "";
        } else {
            const order = root.items.reduce((max, i) => Math.max(max, i.order || 0), 0) + 1;
            const entry = { id: root.nextId(), text: result.text, done: false, doneAt: 0, created: root.now, due: result.due, priority: result.priority, tags: result.tags, repeat: result.repeat, steps: [], order: order };
            // Typed while a tag is filtered: it belongs to that tag.
            if (root.tagFilter !== "" && entry.tags.indexOf(root.tagFilter) === -1)
                entry.tags = entry.tags.concat([root.tagFilter]);
            root.items = root.items.concat([entry]);
            root.selectedId = entry.id;
            addFlash.key = entry.id;
            addFlash.restart();
            // Land where it shows up.
            if (root.view === "done" || (root.view === "today" && (entry.due === null || entry.due > root.today)) || (root.view === "upcoming" && (entry.due === null || entry.due <= root.today)))
                root.view = "all";
            root.save();
        }
        input.text = "";
        root.draft = "";
    }

    function toggle(id) {
        const target = root.item(id);
        if (!target)
            return;
        root.snapshot();
        const done = !target.done;
        let items = root.items.map(i => i.id === id ? Object.assign({}, i, { done: done, doneAt: done ? Date.now() : 0 }) : i);

        if (done && target.repeat) {
            const next = root.nextDue(target.due, target.repeat);
            items = items.concat([Object.assign({}, target, { id: root.nextId(), done: false, doneAt: 0, due: next, steps: (target.steps || []).map(s => Object.assign({}, s, { done: false })), order: target.order + 0.5 })]);
            root.showToast("Done · next one " + root.dueLabel(next).toLowerCase());
        } else if (done) {
            const left = items.filter(i => !i.done && i.due !== null && i.due <= root.today).length;
            if (target.due !== null && target.due <= root.today && left === 0)
                root.showToast("All clear for today");
        }
        root.items = items;

        if (done && root.view !== "done") {
            const pending = Object.assign({}, root.justDone);
            pending[id] = true;
            root.justDone = pending;
            settleTimer.restart();
        }
        root.save();
    }

    function remove(id) {
        const target = root.item(id);
        if (!target)
            return;
        root.snapshot();
        root.items = root.items.filter(i => i.id !== id);
        if (root.expandedId === id)
            root.expandedId = "";
        root.showToast("Deleted “" + target.text + "” · Ctrl+Z to undo");
        root.save();
    }

    // Alt+↑/↓: swap with the neighbour in the same section.
    function move(delta) {
        const index = root.rows.findIndex(row => row.key === root.currentKey);
        const other = root.rows[index + delta];
        if (index < 0 || !other || other.kind !== "task")
            return;
        const a = root.item(root.currentKey);
        const b = root.item(other.key);
        if (a.priority !== b.priority) {
            root.showToast("Sorted by priority — change it to move past");
            return;
        }
        root.snapshot();
        const orderA = a.order;
        const orderB = b.order === orderA ? orderA + delta : b.order;
        root.items = root.items.map(i => i.id === a.id ? Object.assign({}, i, { order: orderB }) : (i.id === b.id ? Object.assign({}, i, { order: orderA }) : i));
        root.save();
    }

    function startEdit(id) {
        const target = root.item(id);
        if (!target)
            return;
        root.editingId = id;
        input.text = root.phraseFor(target);
        root.draft = input.text;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }

    function cancelEdit() {
        root.editingId = "";
        input.text = "";
        root.draft = "";
    }

    function addStep(id, text) {
        const target = root.item(id);
        if (!target || text.trim() === "")
            return;
        root.snapshot();
        root.update(id, { steps: (target.steps || []).concat([{ id: root.nextId(), text: text.trim(), done: false }]) });
    }

    function toggleStep(id, stepId) {
        const target = root.item(id);
        if (!target)
            return;
        root.update(id, { steps: target.steps.map(s => s.id === stepId ? Object.assign({}, s, { done: !s.done }) : s) });
    }

    function removeStep(id, stepId) {
        const target = root.item(id);
        if (!target)
            return;
        root.snapshot();
        root.update(id, { steps: target.steps.filter(s => s.id !== stepId) });
    }

    function setDue(id, due) {
        root.snapshot();
        root.update(id, { due: due });
    }

    function setPriority(id, level) {
        const target = root.item(id);
        root.snapshot();
        root.update(id, { priority: target && target.priority === level ? 0 : level });
    }

    function clearDone() {
        if (!root.confirmClear) {
            root.confirmClear = true;
            confirmTimer.restart();
            return;
        }
        root.confirmClear = false;
        root.snapshot();
        const count = root.items.filter(i => i.done).length;
        root.items = root.items.filter(i => !i.done);
        root.showToast("Cleared " + count + " done · Ctrl+Z to undo");
        root.save();
    }

    function toggleExpanded(id) {
        root.expandedId = root.expandedId === id ? "" : id;
        root.selectedId = id;
    }

    function remind(id) {
        const target = root.item(id);
        if (!target)
            return;
        let when = "";
        if (target.due !== null && target.due > root.today)
            when = target.due === root.addDays(root.today, 1) ? " tomorrow 9:00" : " " + new Date(target.due).getFullYear() + "." + root.pad2(new Date(target.due).getMonth() + 1) + "." + root.pad2(new Date(target.due).getDate()) + " 9:00";
        root.remindRequested(target.text + when + (when === "" ? " " : ""));
    }

    function focusOn(id) {
        const target = root.item(id);
        if (target)
            root.focusRequested(target.text);
    }

    function copyMarkdown() {
        const lines = [];
        for (const row of root.rows) {
            if (row.kind === "header") {
                lines.push((lines.length > 0 ? "\n" : "") + "## " + row.label);
                continue;
            }
            const i = row.item;
            let line = "- [" + (i.done ? "x" : " ") + "] " + i.text;
            if (i.priority > 0)
                line += " " + "!".repeat(i.priority);
            for (const tag of i.tags || [])
                line += " #" + tag;
            if (i.due !== null)
                line += " 📅 " + new Date(i.due).getFullYear() + "-" + root.pad2(new Date(i.due).getMonth() + 1) + "-" + root.pad2(new Date(i.due).getDate());
            lines.push(line);
            for (const step of i.steps || [])
                lines.push("    - [" + (step.done ? "x" : " ") + "] " + step.text);
        }
        if (lines.length === 0) {
            root.showToast("Nothing to copy");
            return;
        }
        Quickshell.execDetached(["wl-copy", lines.join("\n")]);
        root.showToast("Copied " + root.taskKeys.length + " tasks as a Markdown checklist");
    }

    // ── Persistence ───────────────────────────────────────────────────────
    readonly property string storePath: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/todos.json"

    function save() {
        if (root.loaded)
            saveTimer.restart();
    }

    function apply(text) {
        try {
            const data = JSON.parse(text);
            const list = Array.isArray(data) ? data : (data && Array.isArray(data.items) ? data.items : []);
            let order = 0;
            root.items = list.filter(e => e && typeof e.text === "string").map(e => ({
                id: String(e.id !== undefined ? e.id : root.nextId()),
                text: e.text,
                done: e.done === true,
                doneAt: typeof e.doneAt === "number" ? e.doneAt : (e.done === true ? root.startOfDay(Date.now()) - 1 : 0),
                created: typeof e.created === "number" ? e.created : Date.now(),
                due: typeof e.due === "number" ? e.due : null,
                priority: typeof e.priority === "number" ? Math.max(0, Math.min(3, e.priority)) : 0,
                tags: Array.isArray(e.tags) ? e.tags.filter(t => typeof t === "string") : [],
                repeat: e.repeat && typeof e.repeat.kind === "string" ? e.repeat : null,
                steps: Array.isArray(e.steps) ? e.steps.filter(s => s && typeof s.text === "string").map(s => ({ id: String(s.id || root.nextId()), text: s.text, done: s.done === true })) : [],
                order: typeof e.order === "number" ? e.order : ++order
            }));
            if (data && typeof data.view === "string" && ["today", "upcoming", "all", "done"].indexOf(data.view) !== -1)
                root.view = data.view;
        } catch (error) {
            // Missing or hand-broken file: start empty.
        }
        root.loaded = true;
        if (legacyFile.migrated)
            root.save(); // migrate into the new location
    }

    FileView {
        id: storeFile

        path: root.storePath
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.apply(storeFile.text())
        onLoadFailed: legacyFile.reload()
    }

    // The old per-shell state file, read once when the new one doesn't exist.
    FileView {
        id: legacyFile

        property bool migrated: false

        path: Quickshell.statePath("todos.json")
        printErrors: false
        onLoaded: {
            legacyFile.migrated = true;
            root.apply(legacyFile.text());
        }
        onLoadFailed: root.apply("")
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: storeFile.setText(JSON.stringify({ view: root.view, items: root.items }, null, 2) + "\n")
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.now = Date.now()
    }

    Timer {
        id: settleTimer

        interval: 1100
        onTriggered: root.justDone = ({})
    }

    Timer {
        id: toastTimer

        interval: 2600
        onTriggered: root.toast = ""
    }

    Timer {
        id: confirmTimer

        interval: 2500
        onTriggered: root.confirmClear = false
    }

    Timer {
        id: addFlash

        property string key: ""

        interval: 1200
        onTriggered: addFlash.key = ""
    }

    onViewChanged: root.save()

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
            input.forceActiveFocus();
            if (root.typedEarly !== "") {
                input.insert(input.cursorPosition, root.typedEarly);
                root.typedEarly = "";
                input.textEdited();
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
            root.now = Date.now();
            root.typedEarly = "";
            root.forceActiveFocus();
            focusAfterOpen.restart();
        } else {
            root.expandedId = "";
            root.confirmClear = false;
        }
    }

    // ── Components ────────────────────────────────────────────────────────

    component IconButton: Rectangle {
        id: iconButton

        required property string icon
        property color tint: "#9a9a9a"
        property int iconSize: 14
        property string tip: ""

        signal clicked

        width: 26
        height: 26
        radius: 9
        color: iconHover.hovered ? "#1c1c1c" : "transparent"
        scale: iconMouse.pressed ? 0.86 : (iconHover.hovered ? 1.08 : 1)

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler {
            id: iconHover

            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered && iconButton.tip !== "")
                    root.hint = iconButton.tip;
                else if (!hovered && root.hint === iconButton.tip)
                    root.hint = "";
            }
        }

        MIcon {
            anchors.centerIn: parent
            name: iconButton.icon
            size: iconButton.iconSize
            color: iconHover.hovered ? root.primaryText : iconButton.tint
        }

        MouseArea {
            id: iconMouse

            anchors.fill: parent
            onClicked: iconButton.clicked()
        }
    }

    component Pill: Rectangle {
        id: pill

        required property string text
        property color tint: root.secondaryText
        property bool active: false
        property string icon: ""

        signal clicked

        implicitWidth: pillRow.implicitWidth + 16
        implicitHeight: 22
        radius: 7
        color: pill.active ? Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, 0.16) : (pillHover.hovered ? "#171717" : "#0d0d0d")
        border.width: 1
        border.color: pill.active ? Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, 0.55) : (pillHover.hovered ? "#2c2c2c" : "#1c1c1c")
        scale: pillMouse.pressed ? 0.92 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }

        HoverHandler {
            id: pillHover

            cursorShape: Qt.PointingHandCursor
        }

        Row {
            id: pillRow

            anchors.centerIn: parent
            spacing: 4

            MIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.icon !== ""
                name: pill.icon
                size: 12
                color: pill.active ? pill.tint : "#8a8a8a"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.active ? pill.tint : (pillHover.hovered ? root.primaryText : "#9a9a9a")
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: pillMouse

            anchors.fill: parent
            onClicked: pill.clicked()
        }
    }

    // A round checkbox that pops and ripples when ticked.
    component Check: Item {
        id: check

        property bool checked: false
        property color ring: "#3a3a3a"
        property int size: 18

        signal toggled

        width: check.size
        height: check.size

        property bool armed: false

        Component.onCompleted: Qt.callLater(() => check.armed = true)
        onCheckedChanged: if (check.checked && check.armed) pop.restart()

        Rectangle {
            id: ripple

            anchors.centerIn: parent
            width: check.size
            height: check.size
            radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: root.accentColor
            opacity: 0
        }

        Rectangle {
            id: box

            anchors.centerIn: parent
            width: check.size
            height: check.size
            radius: width / 2
            color: check.checked ? root.accentColor : (checkHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12) : "transparent")
            border.width: check.checked ? 0 : 1.5
            border.color: checkHover.hovered ? root.accentColor : check.ring

            Behavior on color { ColorAnimation { duration: 160 } }

            MIcon {
                anchors.centerIn: parent
                name: "check"
                size: check.size - 4
                color: check.checked ? "#0b0b0b" : root.accentColor
                opacity: check.checked ? 1 : (checkHover.hovered ? 0.6 : 0)
                scale: check.checked ? 1 : 0.7

                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 } }
            }
        }

        ParallelAnimation {
            id: pop

            SequentialAnimation {
                NumberAnimation { target: box; property: "scale"; to: 0.7; duration: 70 }
                NumberAnimation { target: box; property: "scale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
            }
            NumberAnimation { target: ripple; property: "scale"; from: 1; to: 2.3; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: ripple; property: "opacity"; from: 0.7; to: 0; duration: 520; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: checkHover

            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: check.toggled()
        }
    }

    property string hint: ""
    // → opened the drawer from the keyboard: put the cursor in "Add a step".
    property bool stepFocusPending: false

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

            Item {
                Layout.preferredWidth: root.headerHeight
                Layout.preferredHeight: root.headerHeight

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#090909"
                    border.width: 1
                    border.color: "#1f1f1f"
                }

                // Today's progress around the icon.
                Shape {
                    id: progressRing

                    property real shown: root.todayProgress

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

                    ShapePath {
                        strokeColor: progressRing.shown > 0.001 ? root.accentColor : "transparent"
                        strokeWidth: 2.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: progressRing.width / 2
                            centerY: progressRing.height / 2
                            radiusX: progressRing.width / 2 - 1.5
                            radiusY: progressRing.height / 2 - 1.5
                            startAngle: -90
                            sweepAngle: 360 * Math.min(0.9999, progressRing.shown)
                        }
                    }
                }

                MIcon {
                    id: headerIcon

                    anchors.centerIn: parent
                    name: root.todayProgress >= 1 && root.doneToday > 0 ? "done_all" : "checklist"
                    size: 16
                    color: root.todayProgress >= 1 && root.doneToday > 0 ? root.accentColor : root.primaryText
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "To-do"
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const parts = [];
                        if (root.todayOpen > 0)
                            parts.push(root.todayOpen + " left today");
                        if (root.overdueCount > 0)
                            parts.push(root.overdueCount + " overdue");
                        if (root.doneToday > 0)
                            parts.push(root.doneToday + " done today");
                        if (parts.length === 0)
                            return root.counts.all > 0 ? root.counts.all + " open  ·  nothing due today" : "All clear";
                        return parts.join("  ·  ");
                    }
                    color: root.overdueCount > 0 ? root.overdueColor : root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            IconButton {
                icon: "content_copy"
                tip: "Copy this view as a Markdown checklist  (Ctrl+Shift+C)"
                onClicked: root.copyMarkdown()
            }

            IconButton {
                icon: "undo"
                tip: "Undo  (Ctrl+Z)"
                opacity: root.undoStack.length > 0 ? 1 : 0.35
                onClicked: root.undo()
            }

            IconButton {
                visible: root.items.some(i => i.done)
                icon: root.confirmClear ? "delete_forever" : "cleaning_services"
                tint: root.confirmClear ? root.overdueColor : "#9a9a9a"
                tip: root.confirmClear ? "Click again to clear every done task" : "Clear done tasks"
                onClicked: root.clearDone()
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 9
                color: closeHover.hovered ? "#1a1a1a" : "#0a0a0a"
                border.width: 1
                border.color: "#232323"
                scale: closeMouse.pressed ? 0.88 : (closeHover.hovered ? 1.08 : 1)

                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                HoverHandler {
                    id: closeHover

                    cursorShape: Qt.PointingHandCursor
                }

                MIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: 13
                    color: "#a8a8a8"
                }

                MouseArea {
                    id: closeMouse

                    anchors.fill: parent
                    onClicked: root.closeRequested()
                }
            }
        }

        // Input
        Rectangle {
            id: inputBox

            readonly property color stateColor: root.editingId !== "" ? root.todayColor : root.accentColor

            Layout.fillWidth: true
            Layout.preferredHeight: root.inputHeight
            radius: 13
            color: "#0a0a0a"
            border.width: 1
            border.color: input.activeFocus ? Qt.rgba(inputBox.stateColor.r, inputBox.stateColor.g, inputBox.stateColor.b, root.draft === "" && root.editingId === "" ? 0.35 : 0.7) : "#1f1f1f"

            Behavior on border.color { ColorAnimation { duration: 180 } }

            transform: Translate {
                id: shakeShift
            }

            SequentialAnimation {
                id: shake

                NumberAnimation { target: shakeShift; property: "x"; to: 8; duration: 50 }
                NumberAnimation { target: shakeShift; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: shakeShift; property: "x"; to: 4; duration: 60 }
                NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 70 }
            }

            MIcon {
                id: inputIcon

                anchors.left: parent.left
                anchors.leftMargin: 13
                anchors.verticalCenter: parent.verticalCenter
                name: root.editingId !== "" ? "edit" : "add_task"
                size: 16
                color: root.draft === "" && root.editingId === "" ? "#5a5a5a" : inputBox.stateColor

                Behavior on color { ColorAnimation { duration: 180 } }
            }

            TextInput {
                id: input

                anchors.left: inputIcon.right
                anchors.right: addButton.left
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: root.primaryText
                selectionColor: "#2f4f3a"
                selectByMouse: true
                clip: true
                font.family: root.fontFamily
                font.pixelSize: 13
                onTextEdited: root.draft = text

                Keys.onReturnPressed: event => {
                    if (input.text.trim() === "" && root.editingId === "")
                        root.toggle(root.currentKey);
                    else
                        root.commit();
                }
                Keys.onEnterPressed: event => {
                    if (input.text.trim() === "" && root.editingId === "")
                        root.toggle(root.currentKey);
                    else
                        root.commit();
                }
                Keys.onEscapePressed: {
                    if (root.editingId !== "")
                        root.cancelEdit();
                    else if (input.text !== "") {
                        input.text = "";
                        root.draft = "";
                    } else if (root.expandedId !== "")
                        root.expandedId = "";
                    else if (root.tagFilter !== "")
                        root.tagFilter = "";
                    else
                        root.closeRequested();
                }
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const alt = event.modifiers & Qt.AltModifier;
                    const empty = input.text === "";
                    if (alt && event.key === Qt.Key_Up)
                        root.move(-1);
                    else if (alt && event.key === Qt.Key_Down)
                        root.move(1);
                    else if (event.key === Qt.Key_Up)
                        root.moveSelection(-1);
                    else if (event.key === Qt.Key_Down)
                        root.moveSelection(1);
                    else if (event.key === Qt.Key_PageUp)
                        root.moveSelection(-6);
                    else if (event.key === Qt.Key_PageDown)
                        root.moveSelection(6);
                    else if (event.key === Qt.Key_Tab)
                        root.view = root.views[(root.views.findIndex(v => v.id === root.view) + 1) % root.views.length].id;
                    else if (event.key === Qt.Key_Backtab)
                        root.view = root.views[(root.views.findIndex(v => v.id === root.view) + root.views.length - 1) % root.views.length].id;
                    else if (ctrl && event.key === Qt.Key_Z)
                        root.undo();
                    else if (ctrl && event.key === Qt.Key_E)
                        root.startEdit(root.currentKey);
                    else if ((ctrl && event.key === Qt.Key_D) || (empty && event.key === Qt.Key_Delete))
                        root.remove(root.currentKey);
                    else if (ctrl && event.key === Qt.Key_R)
                        root.remind(root.currentKey);
                    else if (ctrl && event.key === Qt.Key_F)
                        root.focusOn(root.currentKey);
                    else if (ctrl && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_C)
                        root.copyMarkdown();
                    else if (ctrl && event.key >= Qt.Key_0 && event.key <= Qt.Key_3)
                        root.setPriority(root.currentKey, event.key - Qt.Key_0);
                    else if (empty && event.key === Qt.Key_Right) {
                        root.stepFocusPending = true;
                        root.expandedId = root.currentKey;
                    }
                    else if (empty && event.key === Qt.Key_Left)
                        root.expandedId = "";
                    else if (empty && event.key === Qt.Key_Space)
                        root.toggle(root.currentKey);
                    else
                        return;
                    event.accepted = true;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    width: input.width
                    elide: Text.ElideRight
                    text: root.tagFilter !== "" ? "Add to #" + root.tagFilter + "…" : "Add a task  ·  #tag  !!  friday  every monday"
                    color: "#555555"
                    font: input.font
                }
            }

            Rectangle {
                id: addButton

                readonly property bool ready: root.parsed !== null && root.parsed.text !== ""

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 10
                color: addButton.ready ? inputBox.stateColor : "#141414"
                scale: addMouse.pressed ? 0.88 : (addButton.ready ? 1 : 0.92)

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                MIcon {
                    anchors.centerIn: parent
                    name: root.editingId !== "" ? "check" : "arrow_upward"
                    size: 16
                    color: addButton.ready ? "#0b0b0b" : "#4a4a4a"
                }

                MouseArea {
                    id: addMouse

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.commit()
                }
            }
        }

        // Assist: what the input understood, or tag filters.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.assistHeight
            clip: true

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                opacity: root.parsed !== null ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity { NumberAnimation { duration: 150 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.parsed && root.parsed.text !== "" ? "“" + root.parsed.text + "”" : "Type the task itself too"
                    color: root.parsed && root.parsed.text !== "" ? root.primaryText : root.overdueColor
                    width: Math.min(implicitWidth, 190)
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: root.parsed ? root.parsed.tags : []

                    Pill {
                        required property string modelData

                        text: "#" + modelData
                        tint: root.tagColor(modelData)
                        active: true
                    }
                }

                Pill {
                    visible: root.parsed !== null && root.parsed.priority > 0
                    text: root.parsed ? ["", "Low", "Medium", "High"][root.parsed.priority] : ""
                    icon: "flag"
                    tint: root.parsed ? root.priorityColors[root.parsed.priority] : "#fff"
                    active: true
                }

                Pill {
                    visible: root.parsed !== null && root.parsed.hasDue
                    text: root.parsed && root.parsed.hasDue ? root.dueLabel(root.parsed.due) : ""
                    icon: "event"
                    tint: root.parsed && root.parsed.hasDue ? (root.parsed.due <= root.today ? root.todayColor : "#93c5fd") : "#fff"
                    active: true
                }

                Pill {
                    visible: root.parsed !== null && root.parsed.repeat !== null
                    text: root.parsed ? root.repeatLabel(root.parsed.repeat) : ""
                    icon: "repeat"
                    tint: "#a78bfa"
                    active: true
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                opacity: root.parsed === null ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity { NumberAnimation { duration: 150 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.allTags.length === 0
                    text: "Tip: add #tags to group tasks, !!! for priority, a day like “péntek” for a due date"
                    color: root.faintText
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: root.allTags.slice(0, 8)

                    Pill {
                        required property var modelData

                        text: "#" + modelData.tag + "  " + modelData.count
                        tint: root.tagColor(modelData.tag)
                        active: root.tagFilter === modelData.tag
                        onClicked: {
                            root.tagFilter = root.tagFilter === modelData.tag ? "" : modelData.tag;
                            input.forceActiveFocus();
                        }
                    }
                }
            }
        }

        // View tabs
        Rectangle {
            id: tabBar

            readonly property real cell: (width - 6) / root.views.length
            readonly property int current: root.views.findIndex(v => v.id === root.view)

            Layout.fillWidth: true
            Layout.preferredHeight: root.tabsHeight
            radius: 10
            color: "#0a0a0a"
            border.width: 1
            border.color: "#1c1c1c"

            Rectangle {
                y: 3
                x: 3 + tabBar.current * tabBar.cell
                width: tabBar.cell
                height: parent.height - 6
                radius: 7
                color: "#1d1d1d"
                border.width: 1
                border.color: "#2d2d2d"

                Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            }

            Row {
                x: 3
                y: 3

                Repeater {
                    model: root.views

                    Item {
                        id: tab

                        required property var modelData
                        required property int index

                        readonly property bool active: root.view === modelData.id
                        readonly property int count: root.counts[modelData.id]

                        width: tabBar.cell
                        height: tabBar.height - 6

                        Row {
                            anchors.centerIn: parent
                            spacing: 5

                            MIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: tab.modelData.icon
                                size: 13
                                color: tab.active ? root.primaryText : "#6a6a6a"

                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tab.modelData.label
                                color: tab.active ? root.primaryText : "#7a7a7a"
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold

                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: tab.count > 0
                                width: Math.max(16, countText.implicitWidth + 8)
                                height: 16
                                radius: 8
                                color: tab.modelData.id === "today" && root.overdueCount > 0 ? Qt.rgba(root.overdueColor.r, root.overdueColor.g, root.overdueColor.b, 0.2) : (tab.active ? "#2a2a2a" : "#151515")

                                Text {
                                    id: countText

                                    anchors.centerIn: parent
                                    text: tab.count
                                    color: tab.modelData.id === "today" && root.overdueCount > 0 ? root.overdueColor : (tab.active ? root.primaryText : "#7a7a7a")
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.view = tab.modelData.id;
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // List
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.listHeight
            radius: 14
            color: root.cardColor
            border.width: 1
            border.color: root.cardBorder
            clip: true

            Column {
                anchors.centerIn: parent
                spacing: 6
                visible: root.rows.length === 0

                MIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.view === "done" ? "hourglass_empty" : (root.view === "today" ? "celebration" : "task_alt")
                    size: 30
                    color: root.view === "today" && root.doneToday > 0 ? root.accentColor : "#333333"

                    SequentialAnimation on rotation {
                        running: root.visible && root.view === "today" && root.rows.length === 0 && root.doneToday > 0
                        loops: Animation.Infinite
                        NumberAnimation { to: -10; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 10; duration: 500; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        if (root.tagFilter !== "")
                            return "Nothing tagged #" + root.tagFilter + " here";
                        if (root.view === "today")
                            return root.doneToday > 0 ? "All clear for today" : "Nothing due today";
                        if (root.view === "upcoming")
                            return "Nothing scheduled ahead";
                        if (root.view === "done")
                            return "Nothing finished yet";
                        return "No tasks — enjoy it";
                    }
                    color: "#6a6a6a"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.view === "today" && root.doneToday > 0 ? root.doneToday + " done today" : "Type one above and press Enter"
                    color: "#3f3f3f"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            ListView {
                id: list

                anchors.fill: parent
                anchors.margins: 5
                model: rowModel
                boundsBehavior: Flickable.StopAtBounds
                spacing: 0

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
                    NumberAnimation { property: "x"; from: -14; to: 0; duration: 300; easing.type: Easing.OutCubic }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: 180 }
                    NumberAnimation { property: "x"; to: 24; duration: 220; easing.type: Easing.InCubic }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; to: 1; duration: 120 }
                }
                move: Transition {
                    NumberAnimation { properties: "x,y"; duration: 260; easing.type: Easing.OutCubic }
                }

                delegate: Item {
                    id: row

                    required property string kind
                    required property string rowKey
                    required property string label
                    required property int count
                    required property string tone
                    required property int index

                    readonly property bool isHeader: kind === "header"
                    readonly property var task: isHeader ? null : (root.itemById[rowKey] || null)
                    readonly property bool current: !isHeader && root.currentKey === rowKey
                    readonly property bool expanded: !isHeader && root.expandedId === rowKey
                    readonly property var steps: task && task.steps ? task.steps : []
                    readonly property int stepsDone: steps.filter(s => s.done).length
                    readonly property bool settling: task !== null && task.done && root.justDone[task.id] === true
                    readonly property real detailHeight: expanded ? 10 + steps.length * 26 + 30 + 8 + 24 + 8 : 0

                    width: list.width
                    height: isHeader ? 26 : 42 + detailHeight

                    onExpandedChanged: {
                        if (row.expanded && root.stepFocusPending) {
                            root.stepFocusPending = false;
                            stepInput.forceActiveFocus();
                        }
                    }

                    Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                    // Section header
                    Row {
                        visible: row.isHeader
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        spacing: 6

                        Text {
                            text: row.isHeader ? row.label.toUpperCase() : ""
                            color: row.isHeader ? (row.tone === "overdue" ? root.overdueColor : (row.tone === "today" ? root.todayColor : (row.tone === "accent" ? root.accentColor : root.faintText))) : root.faintText
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }

                        Text {
                            text: row.isHeader ? row.count : ""
                            color: "#3a3a3a"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }

                    // Task card
                    Rectangle {
                        id: card

                        visible: !row.isHeader
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 11
                        clip: true
                        color: row.expanded ? "#101010" : (row.current ? "#131313" : (rowHover.hovered ? "#0e0e0e" : "transparent"))
                        border.width: row.current || row.expanded ? 1 : 0
                        border.color: "#232323"

                        Behavior on color { ColorAnimation { duration: 140 } }

                        HoverHandler {
                            id: rowHover
                        }

                        // New-task flash
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.accentColor
                            opacity: addFlash.key !== "" && addFlash.key === row.rowKey ? 0.13 : 0

                            Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                        }

                        // Priority edge
                        Rectangle {
                            x: 0
                            y: 8
                            width: 3
                            height: 26
                            radius: 1.5
                            visible: row.task !== null && row.task.priority > 0 && !row.task.done
                            color: row.task ? root.priorityColors[row.task.priority] : "transparent"
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton) {
                                    root.toggle(row.rowKey);
                                    return;
                                }
                                root.toggleExpanded(row.rowKey);
                                input.forceActiveFocus();
                            }
                            onDoubleClicked: root.startEdit(row.rowKey)
                        }

                        RowLayout {
                            x: 12
                            y: 0
                            width: parent.width - 18
                            height: 40
                            spacing: 10

                            Check {
                                checked: row.task !== null && row.task.done
                                ring: row.task && row.task.priority > 0 ? root.priorityColors[row.task.priority] : "#3a3a3a"
                                onToggled: root.toggle(row.rowKey)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    id: taskText

                                    Layout.fillWidth: true
                                    text: row.task ? row.task.text : ""
                                    color: row.task && row.task.done ? "#6a6a6a" : root.primaryText
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold

                                    Behavior on color { ColorAnimation { duration: 250 } }

                                    // Strike-through that draws across when ticked.
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 1.5
                                        radius: 1
                                        color: "#6a6a6a"
                                        width: row.task && row.task.done ? Math.min(taskText.implicitWidth, taskText.width) : 0

                                        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                    }
                                }

                                Row {
                                    spacing: 7
                                    visible: row.task !== null && (row.task.due !== null || (row.task.tags || []).length > 0 || row.task.repeat || row.steps.length > 0 || row.task.done)

                                    Row {
                                        spacing: 3
                                        visible: row.task !== null && row.task.due !== null && !row.task.done

                                        MIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "event"
                                            size: 10
                                            color: row.task ? root.dueColor(row.task.due) : "#fff"
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.task ? root.dueLabel(row.task.due) : ""
                                            color: row.task ? root.dueColor(row.task.due) : "#fff"
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Text {
                                        visible: row.task !== null && row.task.done
                                        text: row.task && row.task.doneAt ? "done " + (row.task.doneAt >= root.today ? Qt.formatTime(new Date(row.task.doneAt), "HH:mm") : root.dueLabel(root.startOfDay(row.task.doneAt)).toLowerCase()) : ""
                                        color: root.faintText
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                    }

                                    MIcon {
                                        visible: row.task !== null && row.task.repeat !== null && row.task.repeat !== undefined
                                        name: "repeat"
                                        size: 10
                                        color: "#a78bfa"
                                    }

                                    Row {
                                        spacing: 3
                                        visible: row.steps.length > 0

                                        MIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "checklist"
                                            size: 10
                                            color: row.stepsDone === row.steps.length ? root.accentColor : root.secondaryText
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.stepsDone + "/" + row.steps.length
                                            color: row.stepsDone === row.steps.length ? root.accentColor : root.secondaryText
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }
                                    }

                                    Repeater {
                                        model: row.task ? (row.task.tags || []) : []

                                        Text {
                                            required property string modelData

                                            text: "#" + modelData
                                            color: root.tagColor(modelData)
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }

                            Row {
                                visible: rowHover.hovered || row.expanded
                                spacing: 0

                                IconButton {
                                    visible: row.task !== null && !row.task.done
                                    icon: "timer"
                                    tip: "Focus on this — starts a Pomodoro  (Ctrl+F)"
                                    onClicked: root.focusOn(row.rowKey)
                                }

                                IconButton {
                                    visible: row.task !== null && !row.task.done
                                    icon: "notification_add"
                                    tip: "Remind me about this  (Ctrl+R)"
                                    onClicked: root.remind(row.rowKey)
                                }

                                IconButton {
                                    icon: "edit"
                                    tip: "Edit  (Ctrl+E)"
                                    onClicked: root.startEdit(row.rowKey)
                                }

                                IconButton {
                                    icon: "delete"
                                    tint: "#c46a6a"
                                    tip: "Delete  (Del)"
                                    onClicked: root.remove(row.rowKey)
                                }
                            }

                            MIcon {
                                visible: !rowHover.hovered && !row.expanded
                                name: "chevron_right"
                                size: 14
                                color: "#333333"
                            }
                        }

                        // Drawer: steps, due, priority
                        ColumnLayout {
                            x: 40
                            y: 44
                            width: parent.width - 52
                            spacing: 0
                            visible: row.expanded
                            opacity: row.expanded ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Repeater {
                                model: row.steps

                                Item {
                                    id: stepRow

                                    required property var modelData

                                    Layout.fillWidth: true
                                    implicitHeight: 26

                                    HoverHandler {
                                        id: stepHover
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 8

                                        Check {
                                            size: 14
                                            checked: stepRow.modelData.done
                                            onToggled: root.toggleStep(row.rowKey, stepRow.modelData.id)
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: stepRow.modelData.text
                                            color: stepRow.modelData.done ? "#5a5a5a" : "#cfcfcf"
                                            font.strikeout: stepRow.modelData.done
                                            elide: Text.ElideRight
                                            font.family: root.fontFamily
                                            font.pixelSize: 11
                                        }

                                        IconButton {
                                            visible: stepHover.hovered
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 20
                                            icon: "close"
                                            iconSize: 12
                                            onClicked: root.removeStep(row.rowKey, stepRow.modelData.id)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                implicitHeight: 28
                                radius: 8
                                color: "#0a0a0a"
                                border.width: 1
                                border.color: stepInput.activeFocus ? "#2f4f3a" : "#1c1c1c"

                                MIcon {
                                    id: stepIcon

                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "add"
                                    size: 13
                                    color: stepInput.activeFocus ? root.accentColor : "#4a4a4a"
                                }

                                TextInput {
                                    id: stepInput

                                    anchors.left: stepIcon.right
                                    anchors.right: parent.right
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.primaryText
                                    clip: true
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    Keys.onReturnPressed: {
                                        root.addStep(row.rowKey, stepInput.text);
                                        stepInput.text = "";
                                    }
                                    Keys.onEnterPressed: {
                                        root.addStep(row.rowKey, stepInput.text);
                                        stepInput.text = "";
                                    }
                                    Keys.onEscapePressed: input.forceActiveFocus()
                                    Keys.onTabPressed: input.forceActiveFocus()
                                    Keys.onUpPressed: input.forceActiveFocus()

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: stepInput.text === ""
                                        text: stepInput.activeFocus ? "Add a step — Enter adds, Esc goes back" : "Add a step…"
                                        color: "#4a4a4a"
                                        font: stepInput.font
                                    }
                                }
                            }

                            Row {
                                Layout.topMargin: 8
                                spacing: 5

                                Pill {
                                    text: "Today"
                                    icon: "today"
                                    tint: root.todayColor
                                    active: row.task !== null && row.task.due === root.today
                                    onClicked: root.setDue(row.rowKey, root.today)
                                }

                                Pill {
                                    text: "Tomorrow"
                                    tint: "#93c5fd"
                                    active: row.task !== null && row.task.due === root.addDays(root.today, 1)
                                    onClicked: root.setDue(row.rowKey, root.addDays(root.today, 1))
                                }

                                Pill {
                                    text: "Next week"
                                    tint: "#93c5fd"
                                    active: row.task !== null && row.task.due === root.addDays(root.today, ((8 - new Date(root.today).getDay()) % 7) || 7)
                                    onClicked: root.setDue(row.rowKey, root.addDays(root.today, ((8 - new Date(root.today).getDay()) % 7) || 7))
                                }

                                Pill {
                                    text: "No date"
                                    active: row.task !== null && row.task.due === null
                                    onClicked: root.setDue(row.rowKey, null)
                                }

                                Item {
                                    width: 6
                                    height: 1
                                }

                                Repeater {
                                    model: 3

                                    Pill {
                                        required property int index

                                        text: "!".repeat(index + 1)
                                        tint: root.priorityColors[index + 1]
                                        active: row.task !== null && row.task.priority === index + 1
                                        onClicked: root.setPriority(row.rowKey, index + 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Hint / toast
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: root.hintHeight
            horizontalAlignment: Text.AlignHCenter
            text: root.toast !== "" ? root.toast : (root.hint !== "" ? root.hint : (root.editingId !== "" ? "Editing  ·  Enter saves  ·  Esc cancels" : "Enter add / tick  ·  ↑↓ select  ·  → open  ·  Ctrl+E edit  ·  Del delete  ·  Tab view"))
            color: root.toast !== "" ? root.accentColor : (root.editingId !== "" ? root.todayColor : root.faintText)
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
