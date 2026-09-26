import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Reminders, typed the way you'd say them:
//   "call mom in 20 min"   "dentist tomorrow 14:30"   "pay rent 10.01 9am"
//   "stretch every 2h"     "standup every weekday 9:30"   "holnap 8:00 bevásárlás"
// The line under the input shows exactly when it will fire before you press
// Enter. A week strip filters the list by day (and becomes the default day
// for a reminder typed with only a time). Repeating reminders reschedule
// themselves when they fire; fired ones stay under "Earlier" for a day so
// they can be snoozed.
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested
    // Fired the moment a reminder is due; the shell shows it as an
    // AlertBanner (+ sound) and routes its buttons to handleAlertAction().
    signal alertRequested(var alert)

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color soonColor: "#fbbf24"
    readonly property color errorColor: "#f87171"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int inputHeight: 42
    readonly property int assistHeight: 26
    readonly property int stripHeight: 50
    readonly property int listHeight: 200
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 10

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.inputHeight + root.assistHeight + root.stripHeight + root.listHeight + root.hintHeight + root.sectionSpacing * 5
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    property real now: Date.now()
    property var reminders: [] // { id, text, fireAt, repeat: null | { kind, ms? } }
    property var recent: [] // fired: { id, text, firedAt }
    property bool loaded: false
    property int idCounter: 0

    property string draft: ""
    property string editingId: ""
    property string selectedId: ""
    property string flashId: ""
    property var removing: ({})
    property var filterDay: null // start-of-day ms, or null for everything
    property int stripWeek: 0
    property string toast: ""

    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var longDayNames: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    readonly property var monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    // ── Dates ─────────────────────────────────────────────────────────────
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
        return date.getTime();
    }

    function hhmm(ms) {
        const date = new Date(ms);
        return root.pad2(date.getHours()) + ":" + root.pad2(date.getMinutes());
    }

    function dayLabel(dayMs) {
        const today = root.startOfDay(root.now);
        const diff = Math.round((dayMs - today) / 86400000);
        const date = new Date(dayMs);
        if (diff === 0)
            return "Today";
        if (diff === 1)
            return "Tomorrow";
        if (diff === -1)
            return "Yesterday";
        const base = root.dayNames[date.getDay()] + " " + date.getDate() + " " + root.monthNames[date.getMonth()];
        return diff > 1 && diff < 7 ? root.longDayNames[date.getDay()].charAt(0).toUpperCase() + root.longDayNames[date.getDay()].slice(1) : base;
    }

    function relative(ms) {
        const diff = ms - root.now;
        if (diff < 60000)
            return diff <= 0 ? "now" : "in " + Math.max(1, Math.ceil(diff / 1000)) + "s";
        const minutes = Math.round(diff / 60000);
        if (minutes < 60)
            return "in " + minutes + "m";
        if (minutes < 24 * 60) {
            const h = Math.floor(minutes / 60);
            const m = minutes % 60;
            return "in " + h + "h" + (m > 0 ? " " + m + "m" : "");
        }
        const days = Math.round((root.startOfDay(ms) - root.startOfDay(root.now)) / 86400000);
        return "in " + days + (days === 1 ? " day" : " days");
    }

    function ago(ms) {
        const minutes = Math.floor((root.now - ms) / 60000);
        if (minutes < 1)
            return "just now";
        if (minutes < 60)
            return minutes + "m ago";
        return Math.floor(minutes / 60) + "h ago";
    }

    function repeatLabel(repeat) {
        if (!repeat)
            return "";
        switch (repeat.kind) {
        case "day":
            return "every day";
        case "weekday":
            return "weekdays";
        case "week":
            return "every " + (repeat.dow !== undefined ? root.longDayNames[repeat.dow].charAt(0).toUpperCase() + root.longDayNames[repeat.dow].slice(1) : "week");
        case "month":
            return "every month";
        case "interval":
            return "every " + (repeat.ms % 3600000 === 0 ? repeat.ms / 3600000 + "h" : Math.round(repeat.ms / 60000) + "m");
        }
        return "";
    }

    function nextOccurrence(fireAt, repeat) {
        let next = fireAt;
        let guard = 0;
        do {
            const date = new Date(next);
            if (repeat.kind === "interval") {
                next += repeat.ms;
            } else if (repeat.kind === "month") {
                date.setMonth(date.getMonth() + 1);
                next = date.getTime();
            } else if (repeat.kind === "week") {
                date.setDate(date.getDate() + 7);
                next = date.getTime();
            } else {
                date.setDate(date.getDate() + 1);
                if (repeat.kind === "weekday")
                    while (date.getDay() === 0 || date.getDay() === 6)
                        date.setDate(date.getDate() + 1);
                next = date.getTime();
            }
            guard += 1;
        } while (next <= root.now && guard < 5000)
        return next;
    }

    // ── The parser ────────────────────────────────────────────────────────
    // Finds the "when" in free text, cuts it out, and keeps the rest as the
    // reminder's text. Matching is done on a lower-cased copy; matched spans
    // are blanked in both copies so indices stay aligned.
    readonly property string wordChars: "a-z0-9áéíóöőúüű"

    function parseDraft(raw, baseDay) {
        const W = root.wordChars;
        const pre = "(?:^|[^" + W + "])";
        const post = "(?=$|[^" + W + "])";
        // "tomorrow 14", "friday 9am": a bare hour right after a day word is
        // the time, same as "tomorrow at 14".
        raw = raw.replace(/(today|tonight|tomorrow|tmrw|tmr|holnap|holnapután|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\s+(\d{1,2})(?![\d:.])(?!\s*(?:seconds?|secs?|s|mp|minutes?|mins?|m|perc|hours?|hrs?|h|óra|days?|d|nap|weeks?|w|hét)(?![a-z]))/i, "$1 at $2");
        let work = raw.toLowerCase();
        let orig = raw;
        const found = {};

        const take = source => {
            const regex = new RegExp(pre + "(?:" + source + ")" + post);
            const match = regex.exec(work);
            if (!match)
                return null;
            const blank = " ".repeat(match[0].length);
            work = work.slice(0, match.index) + blank + work.slice(match.index + match[0].length);
            orig = orig.slice(0, match.index) + blank + orig.slice(match.index + match[0].length);
            return match;
        };

        const unitMs = unit => {
            if (/^(s|secs?|seconds?|mp|másodperc)$/.test(unit))
                return 1000;
            if (/^(m|mins?|minutes?|perc)$/.test(unit))
                return 60000;
            if (/^(h|hrs?|hours?|óra|ora)$/.test(unit))
                return 3600000;
            if (/^(d|days?|nap)$/.test(unit))
                return 86400000;
            if (/^(w|weeks?|hét)$/.test(unit))
                return 7 * 86400000;
            return 0;
        };
        const units = "(?:seconds?|secs?|s|mp|másodperc|minutes?|mins?|m|perc|hours?|hrs?|h|óra|ora|days?|d|nap|weeks?|w|hét)";
        const dayAlternation = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun";
        const dowOf = word => ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(word.slice(0, 3));

        // Repeats
        let m = take("every\\s+(\\d+)\\s*(minutes?|mins?|m|hours?|hrs?|h)");
        if (m) {
            found.repeat = { kind: "interval", ms: Math.max(60000, parseInt(m[1], 10) * unitMs(m[2])) };
        } else if ((m = take("every\\s+(?:weekday|weekdays|workday|workdays)|hétköznap"))) {
            found.repeat = { kind: "weekday" };
        } else if ((m = take("every\\s+(" + dayAlternation + ")"))) {
            found.repeat = { kind: "week", dow: dowOf(m[1]) };
            found.dow = found.repeat.dow;
        } else if ((m = take("every\\s+day|everyday|daily|naponta|minden\\s+nap"))) {
            found.repeat = { kind: "day" };
        } else if ((m = take("every\\s+week|weekly|hetente"))) {
            found.repeat = { kind: "week" };
        } else if ((m = take("every\\s+month|monthly|havonta"))) {
            found.repeat = { kind: "month" };
        }

        // Relative: "in 20 min", "in 1h 30m", "10m", "5 perc múlva"
        if ((m = take("in\\s+(?:an?|one)\\s+(hour|minute|min)"))) {
            found.relative = unitMs(m[1]);
        } else if ((m = take("in\\s+half\\s+an\\s+hour|fél\\s+óra\\s+múlva"))) {
            found.relative = 1800000;
        } else if ((m = take("(?:in\\s+)?((?:\\d+(?:[.,]\\d+)?\\s*" + units + "\\s*)+)(?:\\s*(?:múlva|mulva))?"))) {
            const parts = m[1].match(new RegExp("(\\d+(?:[.,]\\d+)?)\\s*(" + units + ")(?=$|[^" + W + "])", "g")) || [];
            let total = 0;
            for (const part of parts) {
                const pm = new RegExp("(\\d+(?:[.,]\\d+)?)\\s*(" + units + ")").exec(part);
                total += parseFloat(pm[1].replace(",", ".")) * unitMs(pm[2]);
            }
            if (total > 0)
                found.relative = total;
        }

        // Clock time
        if ((m = take("(?:at\\s+|@\\s*)?(\\d{1,2}):(\\d{2})\\s*(am|pm)?(?:-kor)?"))) {
            found.time = { h: parseInt(m[1], 10), min: parseInt(m[2], 10), ampm: m[3] || "" };
        } else if ((m = take("(\\d{1,2})\\s*(am|pm)"))) {
            found.time = { h: parseInt(m[1], 10), min: 0, ampm: m[2] };
        } else if ((m = take("(?:at|@)\\s*(\\d{1,2})"))) {
            found.time = { h: parseInt(m[1], 10), min: 0, ampm: "" };
        } else if ((m = take("noon|midday|délben"))) {
            found.time = { h: 12, min: 0, ampm: "", fixed: true };
        } else if ((m = take("midnight|éjfélkor"))) {
            found.time = { h: 23, min: 59, ampm: "", fixed: true };
        } else if ((m = take("tonight|ma\\s+este"))) {
            // After 20:00, "tonight" means the next full hour.
            const hour = new Date(root.now).getHours();
            found.time = { h: hour >= 20 && hour < 23 ? hour + 1 : 20, min: 0, ampm: "", fixed: true };
            found.dayOffset = 0;
        } else if ((m = take("(?:in\\s+the\\s+)?(morning|afternoon|evening|reggel|délután|este)"))) {
            const map = { morning: 9, reggel: 8, afternoon: 15, "délután": 15, evening: 19, este: 19 };
            found.time = { h: map[m[1]], min: 0, ampm: "", fixed: true };
        }

        if (found.time) {
            if (found.time.ampm === "pm" && found.time.h < 12)
                found.time.h += 12;
            if (found.time.ampm === "am" && found.time.h === 12)
                found.time.h = 0;
            if (found.time.h > 23 || found.time.min > 59)
                return { ok: false, error: "That isn't a time on a clock" };
        }

        // Day
        if (found.dayOffset === undefined) {
            if ((m = take("day\\s+after\\s+tomorrow|holnapután")))
                found.dayOffset = 2;
            else if ((m = take("tomorrow|tmrw|tmr|holnap")))
                found.dayOffset = 1;
            else if ((m = take("today|ma")))
                found.dayOffset = 0;
            else if (found.dow === undefined && (m = take("(next\\s+|on\\s+)?(" + dayAlternation + ")"))) {
                found.dow = dowOf(m[2]);
                found.nextWeek = !!m[1] && m[1].trim() === "next";
            }
            else if ((m = take("(\\d{4})[.\\-/](\\d{1,2})[.\\-/](\\d{1,2})\\.?")))
                found.date = { y: parseInt(m[1], 10), mo: parseInt(m[2], 10) - 1, d: parseInt(m[3], 10) };
            else if ((m = take("(\\d{1,2})\\.?\\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|márc|ápr|máj|jún|júl|szept|okt)[a-zá-ű]*\\.?")))
                found.date = { mo: root.monthIndex(m[2]), d: parseInt(m[1], 10) };
            else if ((m = take("(?:on\\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|márc|ápr|máj|jún|júl|szept|okt)[a-zá-ű]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th|\\.)?")))
                found.date = { mo: root.monthIndex(m[1]), d: parseInt(m[2], 10) };
            else if ((m = take("(\\d{1,2})[./](\\d{1,2})\\.?")))
                found.date = { mo: parseInt(m[1], 10) - 1, d: parseInt(m[2], 10) };
        }

        // What's left is the text.
        let text = orig.replace(/\s+/g, " ").trim();
        text = text.replace(/^(remind\s+me\s+(to\s+)?|emlékeztess\s+(arra,?\s+hogy\s+)?)/i, "");
        const filler = /^(to|at|on|in|by|for|about|-|,|:|kor)\s+|\s+(to|at|on|in|by|for|-|,|kor)$|^[-,:]+|[-,:]+$/i;
        for (let i = 0; i < 4; i++)
            text = text.replace(filler, "").trim();
        if (text !== "")
            text = text.charAt(0).toUpperCase() + text.slice(1);

        const hasWhen = found.relative !== undefined || found.time !== undefined || found.dayOffset !== undefined || found.dow !== undefined || found.date !== undefined || found.repeat !== undefined;
        // No time at all is fine once a day is picked in the strip (9:00).
        if (!hasWhen && baseDay === null)
            return { ok: false, text: text, hasWhen: false, error: "When? — in 10m, at 17:30, tomorrow 9am" };

        const nowDate = new Date(root.now);
        let fireAt;
        let dateGiven = true;

        if (found.relative !== undefined) {
            fireAt = root.now + found.relative;
        } else if (found.repeat && found.repeat.kind === "interval" && !found.time) {
            fireAt = root.now + found.repeat.ms;
        } else {
            let day;
            if (found.date) {
                const year = found.date.y !== undefined ? found.date.y : nowDate.getFullYear();
                day = new Date(year, found.date.mo, found.date.d).getTime();
                if (found.date.y === undefined && day < root.startOfDay(root.now))
                    day = new Date(year + 1, found.date.mo, found.date.d).getTime();
                if (found.date.mo < 0 || found.date.mo > 11 || found.date.d < 1 || found.date.d > 31)
                    return { ok: false, error: "That date doesn't exist" };
            } else if (found.dayOffset !== undefined) {
                day = root.addDays(root.startOfDay(root.now), found.dayOffset);
            } else if (found.dow !== undefined) {
                let diff = (found.dow - nowDate.getDay() + 7) % 7;
                if (found.nextWeek && diff === 0)
                    diff = 7;
                day = root.addDays(root.startOfDay(root.now), diff);
            } else {
                dateGiven = false;
                day = baseDay !== null ? baseDay : root.startOfDay(root.now);
            }

            const time = found.time || { h: 9, min: 0, ampm: "", fixed: true };
            const date = new Date(day);
            date.setHours(time.h, time.min, 0, 0);
            fireAt = date.getTime();

            // "at 5" said at two in the afternoon means 17:00.
            if (!dateGiven && time.ampm === "" && !time.fixed && time.h < 12 && fireAt <= root.now && fireAt + 12 * 3600000 > root.now)
                fireAt += 12 * 3600000;

            if (fireAt <= root.now) {
                if (found.dow !== undefined)
                    fireAt = root.addDays(fireAt, 7);
                else if (!dateGiven && (baseDay === null || baseDay === root.startOfDay(root.now)))
                    fireAt = root.addDays(fireAt, 1);
                else if (found.repeat)
                    fireAt = root.nextOccurrence(fireAt, found.repeat);
            }
            if (!found.time && !found.repeat && fireAt <= root.now)
                return { ok: false, error: "Add a time — that day's 9:00 has passed" };
        }

        if (found.repeat && found.repeat.kind === "weekday") {
            const date = new Date(fireAt);
            while (date.getDay() === 0 || date.getDay() === 6)
                date.setDate(date.getDate() + 1);
            fireAt = date.getTime();
        }

        if (fireAt <= root.now)
            return { ok: false, error: "That's already in the past" };

        return { ok: true, text: text !== "" ? text : "Reminder", fireAt: fireAt, repeat: found.repeat || null, hasWhen: true };
    }

    function monthIndex(word) {
        const map = { jan: 0, feb: 1, mar: 2, "már": 2, apr: 3, "ápr": 3, may: 4, "máj": 4, jun: 5, "jún": 5, jul: 6, "júl": 6, aug: 7, sep: 8, sze: 8, oct: 9, okt: 9, nov: 10, dec: 11 };
        const key = Object.keys(map).find(k => word.startsWith(k));
        return key !== undefined ? map[key] : -1;
    }

    // Turns a saved reminder back into a phrase the parser reads the same way,
    // for editing.
    function phraseFor(reminder) {
        const day = root.startOfDay(reminder.fireAt);
        const today = root.startOfDay(root.now);
        const date = new Date(reminder.fireAt);
        let when;
        if (day === today)
            when = "today";
        else if (day === root.addDays(today, 1))
            when = "tomorrow";
        else
            when = date.getFullYear() + "." + root.pad2(date.getMonth() + 1) + "." + root.pad2(date.getDate());
        let phrase = reminder.text + " " + when + " " + root.hhmm(reminder.fireAt);
        const repeat = reminder.repeat;
        if (repeat) {
            if (repeat.kind === "interval")
                phrase = reminder.text + " every " + Math.round(repeat.ms / 60000) + "m";
            else if (repeat.kind === "week" && repeat.dow !== undefined)
                phrase = reminder.text + " every " + root.longDayNames[repeat.dow] + " " + root.hhmm(reminder.fireAt);
            else
                phrase += " " + ({ day: "every day", weekday: "every weekday", week: "every week", month: "every month" })[repeat.kind];
        }
        return phrase;
    }

    readonly property var parsed: root.draft.trim() === "" ? null : root.parseDraft(root.draft, root.filterDay)
    readonly property bool canAdd: root.parsed !== null && root.parsed.ok === true

    // ── List ──────────────────────────────────────────────────────────────
    readonly property var upcoming: root.reminders.slice().sort((a, b) => a.fireAt - b.fireAt)
    readonly property var nextReminder: root.upcoming.length > 0 ? root.upcoming[0] : null

    readonly property var rows: {
        const rows = [];
        const list = root.filterDay === null ? root.upcoming : root.upcoming.filter(r => root.startOfDay(r.fireAt) === root.filterDay);
        let lastDay = null;
        for (const reminder of list) {
            const day = root.startOfDay(reminder.fireAt);
            if (day !== lastDay && root.filterDay === null) {
                rows.push({ kind: "header", label: root.dayLabel(day), key: "h" + day });
                lastDay = day;
            }
            rows.push({ kind: "item", key: reminder.id, reminder: reminder });
        }
        if (root.filterDay === null && root.recent.length > 0) {
            rows.push({ kind: "header", label: "Earlier", key: "h-recent" });
            for (const entry of root.recent)
                rows.push({ kind: "recent", key: "r" + entry.id, reminder: entry });
        }
        return rows;
    }

    readonly property var selectableKeys: root.rows.filter(row => row.kind !== "header").map(row => row.key)
    readonly property string currentKey: root.selectableKeys.indexOf(root.selectedId) !== -1 ? root.selectedId : (root.selectableKeys.length > 0 ? root.selectableKeys[0] : "")

    function moveSelection(delta) {
        const keys = root.selectableKeys;
        if (keys.length === 0)
            return;
        const index = Math.max(0, Math.min(keys.length - 1, keys.indexOf(root.currentKey) + delta));
        root.selectedId = keys[index];
        const rowIndex = root.rows.findIndex(row => row.key === root.selectedId);
        if (rowIndex >= 0)
            list.positionViewAtIndex(rowIndex, ListView.Contain);
    }

    function rowFor(key) {
        return root.rows.find(row => row.key === key) || null;
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function nextId() {
        root.idCounter += 1;
        return Date.now().toString(36) + "-" + root.idCounter;
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    function commit() {
        if (!root.canAdd) {
            if (root.draft.trim() !== "")
                shake.restart();
            return;
        }

        const result = root.parsed;
        let others = root.reminders;
        if (root.editingId !== "")
            others = others.filter(r => r.id !== root.editingId);

        const entry = { id: root.nextId(), text: result.text, fireAt: result.fireAt, repeat: result.repeat, created: root.now };
        root.reminders = others.concat([entry]);
        root.showToast((root.editingId !== "" ? "Updated · " : "Set · ") + root.dayLabel(root.startOfDay(entry.fireAt)) + " " + root.hhmm(entry.fireAt) + "  (" + root.relative(entry.fireAt) + ")");
        root.editingId = "";
        ring.restart();
        root.selectedId = entry.id;
        root.flashId = entry.id;
        flashTimer.restart();
        input.text = "";
        root.draft = "";
        root.save();
    }

    function startEdit(key) {
        const row = root.rowFor(key);
        if (!row)
            return;
        if (row.kind === "recent") {
            input.text = row.reminder.text + " ";
        } else {
            root.editingId = row.reminder.id;
            input.text = root.phraseFor(row.reminder);
        }
        root.draft = input.text;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }

    // From the To-do panel's "remind me": start a reminder with its text.
    function prefill(text) {
        root.editingId = "";
        root.filterDay = null;
        input.text = text;
        root.draft = text;
        input.cursorPosition = text.length;
    }

    function cancelEdit() {
        root.editingId = "";
        input.text = "";
        root.draft = "";
    }

    // Fades the row out first, then drops it.
    function remove(key) {
        const row = root.rowFor(key);
        if (!row || root.removing[key])
            return;
        const pending = Object.assign({}, root.removing);
        pending[key] = true;
        root.removing = pending;
        Qt.callLater(() => removeTimer.restart());
    }

    function finishRemovals() {
        const keys = Object.keys(root.removing);
        if (keys.length === 0)
            return;
        root.reminders = root.reminders.filter(r => keys.indexOf(r.id) === -1);
        root.recent = root.recent.filter(r => keys.indexOf("r" + r.id) === -1);
        if (keys.indexOf(root.editingId) !== -1)
            root.cancelEdit();
        root.removing = ({});
        root.save();
    }

    function snooze(key, minutes) {
        const row = root.rowFor(key);
        if (!row)
            return;
        const entry = { id: root.nextId(), text: row.reminder.text, fireAt: root.now + minutes * 60000, repeat: null };
        root.recent = root.recent.filter(r => "r" + r.id !== key);
        root.reminders = root.reminders.concat([entry]);
        root.selectedId = entry.id;
        root.flashId = entry.id;
        flashTimer.restart();
        ring.restart();
        root.showToast("Snoozed " + minutes + " min · " + root.hhmm(entry.fireAt));
        root.save();
    }

    function appendPhrase(phrase) {
        const base = input.text.replace(/\s+$/, "");
        input.text = base === "" ? phrase + " " : base + " " + phrase;
        root.draft = input.text;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }

    function checkDue() {
        const due = root.reminders.filter(r => r.fireAt <= root.now);
        if (due.length === 0)
            return;

        let kept = root.reminders.filter(r => r.fireAt > root.now);
        let recent = root.recent.slice();

        for (const reminder of due) {
            // Long overdue (machine was off/asleep): don't ring for it, but
            // keep it visible under Earlier.
            const stale = root.now - reminder.fireAt > 10 * 60000;
            let body = "";
            if (reminder.repeat) {
                const next = root.nextOccurrence(reminder.fireAt, reminder.repeat);
                kept.push(Object.assign({}, reminder, { fireAt: next }));
                body = "Repeats " + root.repeatLabel(reminder.repeat) + "  ·  next " + root.dayLabel(root.startOfDay(next)).toLowerCase() + " " + root.hhmm(next);
            } else if (reminder.created) {
                const setDay = root.startOfDay(reminder.created) === root.startOfDay(root.now) ? "today" : root.dayLabel(root.startOfDay(reminder.created)).toLowerCase();
                body = "You set this " + setDay + " at " + root.hhmm(reminder.created);
            }
            const recentId = reminder.id + "-" + reminder.fireAt;
            recent.unshift({ id: recentId, text: reminder.text, firedAt: reminder.fireAt });
            if (!stale) {
                const upcoming = kept.filter(r => r.fireAt > root.now).sort((a, b) => a.fireAt - b.fireAt);
                root.alertRequested({
                    source: "reminder",
                    kind: "reminder",
                    accent: "#fbbf24",
                    icon: reminder.repeat ? "event_repeat" : "notifications_active",
                    kicker: "Reminder  ·  " + root.hhmm(reminder.fireAt),
                    title: reminder.text,
                    body: body,
                    meta: upcoming.length > 0 ? "Next: " + upcoming[0].text + " " + root.relative(upcoming[0].fireAt) : "",
                    actions: [
                        { id: "snooze:10:r" + recentId, label: "10 min", icon: "snooze" },
                        { id: "snooze:60:r" + recentId, label: "1 hour", icon: "schedule" },
                        { id: "dismiss", label: "Done", icon: "check", primary: true }
                    ],
                    timeout: 15000
                });
            }
        }

        root.reminders = kept;
        root.recent = recent.slice(0, 6);
        root.save();
    }

    function handleAlertAction(id) {
        const match = /^snooze:(\d+):(.+)$/.exec(id);
        if (!match)
            return "";
        const before = root.reminders.length;
        root.snooze(match[2], parseInt(match[1], 10));
        if (root.reminders.length === before)
            return "";
        const entry = root.reminders[root.reminders.length - 1];
        return "Snoozed  ·  rings again " + root.hhmm(entry.fireAt);
    }

    function pruneRecent() {
        const fresh = root.recent.filter(r => root.now - r.firedAt < 24 * 3600000);
        if (fresh.length !== root.recent.length) {
            root.recent = fresh;
            root.save();
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────
    readonly property string storePath: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/reminders.json"

    function save() {
        if (root.loaded)
            saveTimer.restart();
    }

    function apply(text) {
        try {
            const data = JSON.parse(text);
            const list = Array.isArray(data) ? data : (data && Array.isArray(data.reminders) ? data.reminders : []);
            root.reminders = list.filter(r => r && typeof r.text === "string" && typeof r.fireAt === "number").map(r => ({
                id: String(r.id !== undefined ? r.id : root.nextId()),
                text: r.text,
                fireAt: r.fireAt,
                repeat: r.repeat && typeof r.repeat.kind === "string" ? r.repeat : null,
                created: typeof r.created === "number" ? r.created : 0
            }));
            root.recent = data && Array.isArray(data.recent) ? data.recent.filter(r => r && typeof r.text === "string" && typeof r.firedAt === "number") : [];
        } catch (error) {
            // Missing or hand-broken file: start empty.
        }
        root.loaded = true;
        root.now = Date.now();
        root.checkDue();
        root.pruneRecent();
    }

    FileView {
        id: storeFile

        path: root.storePath
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.apply(storeFile.text())
        // First run on the new location: pick up the old per-shell state file.
        onLoadFailed: legacyFile.reload()
    }

    FileView {
        id: legacyFile

        path: Quickshell.statePath("reminders.json")
        printErrors: false
        onLoaded: root.apply(legacyFile.text())
        onLoadFailed: root.apply("")
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: storeFile.setText(JSON.stringify({ reminders: root.reminders, recent: root.recent }, null, 2) + "\n")
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        // `now` drives every relative time in the list, so writing it rebuilt
        // the whole (hidden) list once a second, all day. Hidden, the clock
        // only moves when a reminder is actually due, and once a minute.
        onTriggered: {
            const time = Date.now();
            const minute = new Date(time).getSeconds() === 0;
            if (root.visible || minute || root.reminders.some(r => r.fireAt <= time)) {
                root.now = time;
                root.checkDue();
                if (minute)
                    root.pruneRecent();
            }
        }
    }

    Timer {
        id: removeTimer

        interval: 220
        onTriggered: root.finishRemovals()
    }

    Timer {
        id: flashTimer

        interval: 1400
        onTriggered: root.flashId = ""
    }

    Timer {
        id: toastTimer

        interval: 2600
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
            root.stripWeek = 0;
            root.typedEarly = "";
            root.forceActiveFocus();
            focusAfterOpen.restart();
        }
    }

    // ── Components ────────────────────────────────────────────────────────

    component IconButton: Rectangle {
        id: iconButton

        required property string icon
        property color tint: "#a8a8a8"
        property int iconSize: 13

        signal clicked

        width: 26
        height: 26
        radius: 9
        color: iconMouse.containsMouse ? "#1a1a1a" : "transparent"
        scale: iconMouse.pressed ? 0.86 : (iconMouse.containsMouse ? 1.08 : 1)

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        MIcon {
            anchors.centerIn: parent
            name: iconButton.icon
            size: iconButton.iconSize
            color: iconMouse.containsMouse ? root.primaryText : iconButton.tint
        }

        MouseArea {
            id: iconMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.clicked()
        }
    }

    component QuickChip: Rectangle {
        id: quickChip

        required property string label
        required property string phrase

        implicitWidth: chipText.implicitWidth + 18
        implicitHeight: 24
        radius: 8
        color: chipMouse.containsMouse ? "#171717" : "#0b0b0b"
        border.width: 1
        border.color: chipMouse.containsMouse ? "#2c2c2c" : "#1c1c1c"
        scale: chipMouse.pressed ? 0.92 : 1

        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }

        Text {
            id: chipText

            anchors.centerIn: parent
            text: quickChip.label
            color: chipMouse.containsMouse ? root.primaryText : "#9a9a9a"
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.appendPhrase(quickChip.phrase)
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
                radius: 11
                color: "#090909"
                border.width: 1
                border.color: "#232323"

                MIcon {
                    id: bell

                    anchors.centerIn: parent
                    name: "notifications"
                    size: 16
                    color: root.primaryText
                    transformOrigin: Item.Top
                }

                // The bell rings whenever a reminder is set.
                SequentialAnimation {
                    id: ring

                    NumberAnimation { target: bell; property: "rotation"; to: 18; duration: 70 }
                    NumberAnimation { target: bell; property: "rotation"; to: -15; duration: 110 }
                    NumberAnimation { target: bell; property: "rotation"; to: 10; duration: 100 }
                    NumberAnimation { target: bell; property: "rotation"; to: -5; duration: 90 }
                    NumberAnimation { target: bell; property: "rotation"; to: 0; duration: 120; easing.type: Easing.OutCubic }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "Reminders"
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: root.nextReminder ? "Next  ·  " + root.nextReminder.text + "  " + root.relative(root.nextReminder.fireAt) : "Nothing scheduled"
                    color: root.nextReminder && root.nextReminder.fireAt - root.now < 15 * 60000 ? root.soonColor : root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 9
                color: closeMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                border.width: 1
                border.color: "#232323"
                scale: closeMouse.pressed ? 0.88 : (closeMouse.containsMouse ? 1.08 : 1)

                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                MIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: 13
                    color: "#a8a8a8"
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

        // Smart input
        Rectangle {
            id: inputBox

            readonly property color stateColor: root.editingId !== "" ? root.soonColor : (root.parsed && root.parsed.ok ? root.accentColor : (root.parsed && root.parsed.error ? root.errorColor : "#2a2a2a"))

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
                name: root.editingId !== "" ? "edit" : "add_alert"
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

                Keys.onReturnPressed: root.commit()
                Keys.onEnterPressed: root.commit()
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onDownPressed: root.moveSelection(1)
                Keys.onEscapePressed: {
                    if (root.editingId !== "")
                        root.cancelEdit();
                    else if (input.text !== "") {
                        input.text = "";
                        root.draft = "";
                    } else if (root.filterDay !== null)
                        root.filterDay = null;
                    else
                        root.closeRequested();
                }
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (ctrl && event.key === Qt.Key_E) {
                        root.startEdit(root.currentKey);
                    } else if ((ctrl && event.key === Qt.Key_D) || (event.key === Qt.Key_Delete && input.text === "")) {
                        root.remove(root.currentKey);
                    } else if (ctrl && event.key === Qt.Key_S) {
                        const row = root.rowFor(root.currentKey);
                        if (row && row.kind === "recent")
                            root.snooze(root.currentKey, 10);
                        else
                            return;
                    } else if (input.text === "" && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                        const today = root.startOfDay(root.now);
                        const current = root.filterDay === null ? root.addDays(today, event.key === Qt.Key_Right ? -1 : 1) : root.filterDay;
                        const next = root.addDays(current, event.key === Qt.Key_Right ? 1 : -1);
                        root.filterDay = next < today ? null : next;
                        root.stripWeek = root.filterDay === null ? 0 : Math.floor(Math.round((root.filterDay - today) / 86400000) / 7);
                    } else if (event.key === Qt.Key_PageUp) {
                        root.moveSelection(-5);
                    } else if (event.key === Qt.Key_PageDown) {
                        root.moveSelection(5);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: root.filterDay !== null ? "Remind me " + (root.filterDay <= root.addDays(root.startOfDay(root.now), 1) ? root.dayLabel(root.filterDay).toLowerCase() : "on " + root.dayLabel(root.filterDay)) + " at…" : "Call mom in 20 min  ·  dentist tomorrow 14:30"
                    color: "#555555"
                    font: input.font
                    elide: Text.ElideRight
                    width: input.width
                }
            }

            Rectangle {
                id: addButton

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 10
                color: root.canAdd ? (addMouse.containsMouse ? Qt.lighter(inputBox.stateColor, 1.1) : inputBox.stateColor) : "#141414"
                scale: addMouse.pressed ? 0.88 : (root.canAdd ? 1 : 0.92)

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                MIcon {
                    anchors.centerIn: parent
                    name: root.editingId !== "" ? "check" : "arrow_upward"
                    size: 16
                    color: root.canAdd ? "#0b0b0b" : "#4a4a4a"
                }

                MouseArea {
                    id: addMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.canAdd ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.commit()
                }
            }
        }

        // Assist row: the parse preview, or quick-when chips.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.assistHeight

            readonly property bool showPreview: root.parsed !== null && (root.parsed.ok || root.parsed.hasWhen !== false)
            readonly property bool showChips: !showPreview

            Row {
                id: preview

                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7
                opacity: parent.showPreview ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity { NumberAnimation { duration: 160 } }

                MIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.parsed && root.parsed.ok ? (root.parsed.repeat ? "repeat" : "schedule") : "error"
                    size: 14
                    color: root.parsed && root.parsed.ok ? root.accentColor : root.errorColor
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const p = root.parsed;
                        if (!p)
                            return "";
                        if (!p.ok)
                            return p.error || "";
                        return root.dayLabel(root.startOfDay(p.fireAt)) + "  ·  " + root.hhmm(p.fireAt);
                    }
                    color: root.parsed && root.parsed.ok ? root.primaryText : root.errorColor
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.parsed !== null && root.parsed.ok === true
                    text: root.parsed && root.parsed.ok ? root.relative(root.parsed.fireAt) + (root.parsed.repeat ? "  ·  " + root.repeatLabel(root.parsed.repeat) : "") + "  ·  “" + root.parsed.text + "”" : ""
                    color: root.secondaryText
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.width - root.panelPadding * 2 - 180)
                    font.family: root.fontFamily
                    font.pixelSize: 11
                }
            }

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                opacity: parent.showChips ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity { NumberAnimation { duration: 160 } }

                QuickChip { label: "+10 min"; phrase: "in 10m" }
                QuickChip { label: "+30 min"; phrase: "in 30m" }
                QuickChip { label: "+1 hour"; phrase: "in 1h" }
                QuickChip { label: "Tonight"; phrase: "tonight" }
                QuickChip { label: "Tomorrow 9:00"; phrase: "tomorrow 9:00" }
                QuickChip { label: "Every day"; phrase: "every day" }
            }
        }

        // Week strip
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.stripHeight
            spacing: 4

            IconButton {
                icon: "chevron_left"
                iconSize: 16
                opacity: root.stripWeek > 0 ? 1 : 0.25
                enabled: root.stripWeek > 0
                onClicked: root.stripWeek -= 1
            }

            Repeater {
                model: 7

                Rectangle {
                    id: dayCell

                    required property int index

                    readonly property real dayMs: root.addDays(root.startOfDay(root.now), root.stripWeek * 7 + index)
                    readonly property bool isToday: dayMs === root.startOfDay(root.now)
                    readonly property bool selected: root.filterDay === dayMs
                    readonly property int count: root.reminders.filter(r => root.startOfDay(r.fireAt) === dayMs).length
                    readonly property bool weekend: new Date(dayMs).getDay() % 6 === 0

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    color: dayCell.selected ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : (dayMouse.containsMouse ? "#131313" : root.cardColor)
                    border.width: 1
                    border.color: dayCell.selected ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.6) : (dayCell.isToday ? "#2c2c2c" : root.cardBorder)
                    scale: dayMouse.pressed ? 0.93 : 1

                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on border.color { ColorAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 1

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCell.isToday ? "TODAY" : root.dayNames[new Date(dayCell.dayMs).getDay()].toUpperCase()
                            color: dayCell.selected || dayCell.isToday ? root.accentColor : (dayCell.weekend ? "#5a5a5a" : root.secondaryText)
                            font.family: root.fontFamily
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: new Date(dayCell.dayMs).getDate()
                            color: dayCell.selected ? root.accentColor : root.primaryText
                            font.family: root.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 4
                            spacing: 2

                            Repeater {
                                model: Math.min(3, dayCell.count)

                                Rectangle {
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: root.accentColor
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: dayMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.filterDay = dayCell.selected ? null : dayCell.dayMs;
                            input.forceActiveFocus();
                        }
                    }
                }
            }

            IconButton {
                icon: "chevron_right"
                iconSize: 16
                onClicked: root.stripWeek += 1
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
                opacity: visible ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 200 } }

                MIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.filterDay !== null ? "event_available" : "notifications_off"
                    size: 24
                    color: "#333333"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.filterDay !== null ? "Nothing on " + root.dayLabel(root.filterDay) : "No reminders yet"
                    color: "#5a5a5a"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Type one above and press Enter"
                    color: "#3f3f3f"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            ListView {
                id: list

                anchors.fill: parent
                anchors.margins: 5
                model: root.rows
                boundsBehavior: Flickable.StopAtBounds
                spacing: 0

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property bool isHeader: modelData.kind === "header"
                    readonly property bool isRecent: modelData.kind === "recent"
                    readonly property var reminder: modelData.reminder || null
                    readonly property bool current: !isHeader && root.currentKey === modelData.key
                    readonly property bool leaving: root.removing[modelData.key] === true
                    readonly property bool soon: !isHeader && !isRecent && reminder && reminder.fireAt - root.now < 15 * 60000
                    readonly property bool editing: !isHeader && !isRecent && reminder && reminder.id === root.editingId

                    width: list.width
                    height: (isHeader ? 24 : 38) * (leaving ? 0 : 1)

                    HoverHandler {
                        id: rowHover

                        enabled: !row.isHeader
                    }
                    opacity: leaving ? 0 : 1
                    clip: true

                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    Text {
                        visible: row.isHeader
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        text: row.isHeader ? row.modelData.label.toUpperCase() : ""
                        color: row.modelData.label === "Today" ? root.accentColor : root.faintText
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                    }

                    Rectangle {
                        visible: !row.isHeader
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 10
                        color: row.editing ? Qt.rgba(root.soonColor.r, root.soonColor.g, root.soonColor.b, 0.08) : (row.current ? "#141414" : (rowHover.hovered ? "#0f0f0f" : "transparent"))
                        border.width: row.current ? 1 : 0
                        border.color: "#232323"

                        Behavior on color { ColorAnimation { duration: 140 } }

                        // Just added / snoozed: a green sweep across the row.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.accentColor
                            opacity: root.flashId !== "" && row.reminder && row.reminder.id === root.flashId ? 0.14 : 0

                            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: row.current ? 16 : 0
                            radius: 1.5
                            color: row.isRecent ? root.secondaryText : root.accentColor

                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                    }

                    RowLayout {
                        visible: !row.isHeader
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 6
                        spacing: 10

                        Text {
                            Layout.preferredWidth: 38
                            text: row.reminder ? root.hhmm(row.isRecent ? row.reminder.firedAt : row.reminder.fireAt) : ""
                            color: row.isRecent ? root.faintText : (row.soon ? root.soonColor : root.accentColor)
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: row.reminder ? row.reminder.text : ""
                                color: row.isRecent ? "#7a7a7a" : root.primaryText
                                font.strikeout: row.isRecent
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Row {
                                spacing: 4
                                visible: row.reminder !== null && (row.isRecent || row.reminder.repeat)

                                MIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: row.isRecent ? "done" : "repeat"
                                    size: 10
                                    color: root.faintText
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.reminder ? (row.isRecent ? "rang " + root.ago(row.reminder.firedAt) : root.repeatLabel(row.reminder.repeat)) : ""
                                    color: root.faintText
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Text {
                            visible: !row.isRecent && !rowActions.shown
                            text: row.reminder && !row.isRecent ? root.relative(row.reminder.fireAt) : ""
                            color: row.soon ? root.soonColor : root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }

                        Row {
                            id: rowActions

                            readonly property bool shown: rowHover.hovered || row.current && input.text === "" || row.isRecent

                            visible: shown
                            spacing: 0

                            IconButton {
                                visible: row.isRecent
                                icon: "snooze"
                                tint: root.soonColor
                                onClicked: root.snooze(row.modelData.key, 10)
                            }

                            IconButton {
                                icon: row.isRecent ? "replay" : "edit"
                                onClicked: root.startEdit(row.modelData.key)
                            }

                            IconButton {
                                icon: row.isRecent ? "close" : "delete"
                                tint: row.isRecent ? "#a8a8a8" : "#c46a6a"
                                onClicked: root.remove(row.modelData.key)
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse

                        z: -1
                        anchors.fill: parent
                        enabled: !row.isHeader
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.MiddleButton) {
                                root.remove(row.modelData.key);
                                return;
                            }
                            root.selectedId = row.modelData.key;
                            input.forceActiveFocus();
                        }
                        onDoubleClicked: root.startEdit(row.modelData.key)
                    }
                }
            }
        }

        // Hint / toast
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: root.hintHeight
            horizontalAlignment: Text.AlignHCenter
            text: root.toast !== "" ? root.toast : (root.editingId !== "" ? "Editing  ·  Enter saves  ·  Esc cancels" : "Enter add  ·  ↑↓ select  ·  Ctrl+E edit  ·  Del remove  ·  ←→ day")
            color: root.toast !== "" ? root.accentColor : (root.editingId !== "" ? root.soonColor : root.faintText)
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

}
