import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// Wi-Fi, over NetworkManager (nmcli) with link stats from iw.
//   Up top, the link: signal in dBm on a gauge, PHY (Wi-Fi 4/5/6, MCS,
//   streams, width) and live throughput.
//   Networks: grouped by SSID, strongest first; each opens into its access
//   points (BSSID, channel, width, rate, signal) and connect / forget /
//   share-as-QR. New networks get their password stored through
//   `nmcli con edit` over stdin, never on a command line.
//   Connection: everything about the link, IPv4/IPv6, DHCP, the adapter,
//   plus a quick ping / DNS / public IP check. Click any value to copy it.
//   Spectrum: every AP drawn on its channel and width, per band, with the
//   least crowded channel.
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color warnColor: "#fbbf24"
    readonly property color errorColor: "#f87171"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"
    readonly property string monoFamily: "Hack Nerd Font Mono"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int heroHeight: 124
    readonly property int tabsHeight: 30
    readonly property int pageHeight: 300
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 10

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.heroHeight + root.tabsHeight + root.pageHeight + root.hintHeight + root.sectionSpacing * 4
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // ── State ─────────────────────────────────────────────────────────────
    property string iface: "wlan0"
    property bool radioOn: true
    property bool scanning: false
    property var aps: []          // every BSSID from the last scan
    property var profiles: []     // saved Wi-Fi connection names
    property var dev: ({})        // nmcli dev show, key → value (arrays for [n] keys)
    property var link: ({})       // iw dev link
    property var station: ({})    // iw station dump
    property real lastScanAt: 0

    property var rxHistory: []
    property var txHistory: []
    property real lastRx: -1
    property real lastTx: -1
    property real lastSampleAt: 0
    property real rxRate: 0
    property real txRate: 0

    property string view: "networks" // networks | connection | spectrum
    readonly property var views: [
        { id: "networks", label: "Networks", icon: "wifi" },
        { id: "connection", label: "Connection", icon: "lan" },
        { id: "spectrum", label: "Spectrum", icon: "equalizer" }
    ]
    readonly property int viewIndex: Math.max(0, root.views.findIndex(v => v.id === root.view))

    property string expandedSsid: ""
    property int selectedIndex: -1
    property string password: ""
    property string identity: ""
    property bool revealPassword: false
    property string busySsid: ""
    property string busyLabel: ""
    property string errorSsid: ""
    property string errorText: ""
    property string shareSsid: ""
    property string sharePsk: ""
    property string shareQr: ""
    property bool hiddenOpen: false
    property string hiddenSsid: ""
    property string band: "5"      // spectrum band: "2.4" | "5"
    property string hint: ""
    property string toast: ""

    // Diagnostics: { key: { state: idle|run|ok|fail, value, detail } }
    property var diag: ({})
    property bool diagRunning: false

    // ── Helpers ───────────────────────────────────────────────────────────
    function splitLine(line) {
        const parts = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) {
                current += line[++i];
            } else if (ch === ":") {
                parts.push(current);
                current = "";
            } else {
                current += ch;
            }
        }
        parts.push(current);
        return parts;
    }

    function channelOf(freq) {
        if (freq === 2484)
            return 14;
        if (freq < 2500)
            return Math.round((freq - 2407) / 5);
        if (freq < 5950)
            return Math.round((freq - 5000) / 5);
        return Math.round((freq - 5950) / 5);
    }

    function bandOf(freq) {
        return freq < 3000 ? "2.4" : (freq < 5925 ? "5" : "6");
    }

    // The middle of the whole (bonded) channel, which is what the spectrum
    // is drawn around. nmcli only reports the primary 20 MHz channel.
    function centerFreq(freq, width) {
        if (width <= 20)
            return freq;
        const ch = root.channelOf(freq);
        if (freq < 3000)
            return freq + (ch <= 7 ? 10 : -10);
        const blocks = { 40: 2, 80: 4, 160: 8 }[width] || 1;
        const starts = width === 160 ? [36, 100] : (width === 80 ? [36, 52, 100, 116, 132, 149] : [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157]);
        for (const s of starts) {
            if (ch >= s && ch < s + blocks * 4)
                return 5000 + (s + (blocks * 4 - 4) / 2) * 5;
        }
        return freq;
    }

    function signalColor(q) {
        if (q >= 70)
            return "#4ade80";
        if (q >= 50)
            return "#a3e635";
        if (q >= 35)
            return "#facc15";
        return "#f87171";
    }

    function dbmInfo(dbm) {
        if (dbm >= -50)
            return { label: "Excellent", color: "#4ade80" };
        if (dbm >= -60)
            return { label: "Good", color: "#a3e635" };
        if (dbm >= -67)
            return { label: "Fair · VoIP OK", color: "#facc15" };
        if (dbm >= -75)
            return { label: "Weak", color: "#fb923c" };
        return { label: "Poor", color: "#f87171" };
    }

    function ssidColor(ssid) {
        const palette = ["#60a5fa", "#f472b6", "#fbbf24", "#a78bfa", "#34d399", "#fb923c", "#22d3ee", "#f87171", "#a3e635", "#e879f9"];
        let h = 0;
        for (let i = 0; i < ssid.length; i++)
            h = (h * 31 + ssid.charCodeAt(i)) >>> 0;
        return palette[h % palette.length];
    }

    function withAlpha(c, a) {
        const q = Qt.color(c);
        return Qt.rgba(q.r, q.g, q.b, a);
    }

    function securityLabel(sec, rsn, wpa) {
        if (!sec || sec === "--")
            return "Open";
        if (sec.indexOf("802.1X") !== -1)
            return sec.indexOf("WPA3") !== -1 ? "WPA3-Enterprise" : "WPA2-Enterprise";
        if (sec.indexOf("OWE") !== -1)
            return "OWE";
        if (rsn.indexOf("sae") !== -1 && rsn.indexOf("psk") !== -1)
            return "WPA2/WPA3";
        if (rsn.indexOf("sae") !== -1 || sec.indexOf("WPA3") !== -1)
            return "WPA3-SAE";
        if (sec.indexOf("WPA2") !== -1)
            return sec.indexOf("WPA1") !== -1 ? "WPA/WPA2-PSK" : "WPA2-PSK";
        if (sec.indexOf("WEP") !== -1)
            return "WEP";
        return sec;
    }

    function cipherOf(rsn, wpa) {
        const f = (rsn && rsn !== "(none)" ? rsn : wpa) || "";
        const pair = [];
        if (f.indexOf("pair_ccmp") !== -1)
            pair.push("CCMP");
        if (f.indexOf("pair_gcmp") !== -1)
            pair.push("GCMP");
        if (f.indexOf("pair_tkip") !== -1)
            pair.push("TKIP");
        return pair.join("/") || "—";
    }

    function formatRate(bytesPerSec) {
        const bits = bytesPerSec * 8;
        if (bits >= 1e9)
            return (bits / 1e9).toFixed(2) + " Gb/s";
        if (bits >= 1e6)
            return (bits / 1e6).toFixed(bits >= 1e8 ? 0 : 1) + " Mb/s";
        if (bits >= 1e3)
            return (bits / 1e3).toFixed(0) + " kb/s";
        return Math.round(bits) + " b/s";
    }

    function formatBytes(b) {
        if (b >= 1e9)
            return (b / 1e9).toFixed(2) + " GB";
        if (b >= 1e6)
            return (b / 1e6).toFixed(1) + " MB";
        if (b >= 1e3)
            return (b / 1e3).toFixed(0) + " kB";
        return b + " B";
    }

    function formatDuration(sec) {
        sec = Math.max(0, Math.round(sec));
        const d = Math.floor(sec / 86400);
        const h = Math.floor(sec % 86400 / 3600);
        const m = Math.floor(sec % 3600 / 60);
        if (d > 0)
            return d + "d " + h + "h";
        if (h > 0)
            return h + "h " + m + "m";
        return m + "m " + (sec % 60) + "s";
    }

    function prefixToMask(prefix) {
        const bits = Math.max(0, Math.min(32, prefix));
        const out = [];
        for (let i = 0; i < 4; i++) {
            const n = Math.max(0, Math.min(8, bits - i * 8));
            out.push(256 - Math.pow(2, 8 - n));
        }
        return out.join(".");
    }

    function devValue(key) {
        const v = root.dev[key];
        return v === undefined ? "" : v;
    }

    function devList(prefix) {
        const out = [];
        for (let i = 1; i < 16; i++) {
            const v = root.dev[prefix + "[" + i + "]"];
            if (v === undefined)
                break;
            out.push(v);
        }
        return out;
    }

    function dhcpOption(name) {
        for (const o of root.devList("DHCP4.OPTION")) {
            const eq = o.indexOf(" = ");
            if (eq !== -1 && o.substr(0, eq) === name)
                return o.substr(eq + 3);
        }
        return "";
    }

    function copy(label, value) {
        if (!value || value === "—")
            return;
        Quickshell.execDetached(["wl-copy", String(value)]);
        root.showToast("Copied " + label);
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    // ── Derived ───────────────────────────────────────────────────────────
    readonly property string activeName: root.devValue("GENERAL.CONNECTION")
    readonly property bool connected: root.link.ssid !== undefined && root.link.ssid !== ""
    readonly property string activeSsid: root.connected ? root.link.ssid : ""
    readonly property int dbm: root.link.signal !== undefined ? root.link.signal : -100
    readonly property int quality: Math.max(0, Math.min(100, Math.round((root.dbm + 90) / 60 * 100)))

    readonly property var activeAp: {
        const bssid = (root.link.bssid || "").toUpperCase();
        return root.aps.find(a => a.bssid === bssid) || null;
    }

    readonly property string phyGen: {
        const r = (root.link.txBitrate || "") + " " + (root.link.rxBitrate || "");
        if (r.indexOf("EHT") !== -1)
            return "Wi-Fi 7";
        if (r.indexOf("HE-") !== -1)
            return "Wi-Fi 6";
        if (r.indexOf("VHT") !== -1)
            return "Wi-Fi 5";
        if (r.indexOf("MCS") !== -1)
            return "Wi-Fi 4";
        return root.connected ? "Legacy" : "";
    }

    function phyDetail(rate) {
        if (!rate)
            return "";
        const mcs = rate.match(/(EHT|HE|VHT)?-?MCS (\d+)/);
        const nss = rate.match(/NSS (\d+)/);
        const width = rate.match(/(\d+)MHz/);
        const parts = [];
        if (mcs)
            parts.push("MCS " + mcs[2]);
        if (nss)
            parts.push(nss[1] + "×" + nss[1] + " SS");
        if (width)
            parts.push(width[1] + " MHz");
        if (rate.indexOf("short GI") !== -1)
            parts.push("SGI");
        const gi = rate.match(/HE-GI (\d)/);
        if (gi)
            parts.push(["0.8", "1.6", "3.2"][Number(gi[1])] + " µs GI");
        return parts.join(" · ");
    }

    function rateMbps(rate) {
        const m = (rate || "").match(/([\d.]+) MBit\/s/);
        return m ? Number(m[1]) : 0;
    }

    // One entry per SSID: strongest AP decides, all APs kept.
    readonly property var networks: {
        const groups = {};
        const order = [];
        for (const a of root.aps) {
            if (a.ssid === "")
                continue;
            let g = groups[a.ssid];
            if (!g) {
                g = groups[a.ssid] = { ssid: a.ssid, signal: 0, aps: [], bands: {}, security: a.security, cipher: a.cipher, secured: a.secured, enterprise: a.enterprise, sae: a.sae, active: false };
                order.push(a.ssid);
            }
            g.aps.push(a);
            g.bands[a.band] = true;
            if (a.signal > g.signal) {
                g.signal = a.signal;
                g.security = a.security;
                g.cipher = a.cipher;
            }
            if (a.inUse || a.ssid === root.activeSsid)
                g.active = true;
        }
        const list = order.map(s => {
            const g = groups[s];
            g.saved = root.profiles.indexOf(g.ssid) !== -1;
            g.aps.sort((x, y) => y.signal - x.signal);
            g.bandLabel = Object.keys(g.bands).sort().map(b => b + " GHz").join(" + ");
            return g;
        });
        list.sort((x, y) => (y.active - x.active) || (y.saved - x.saved) || (y.signal - x.signal));
        return list;
    }

    readonly property int savedCount: root.networks.filter(n => n.saved).length

    // Throughput sparkline scale
    readonly property real historyPeak: Math.max(12500, ...root.rxHistory, ...root.txHistory)

    // ── Processes ─────────────────────────────────────────────────────────
    Process {
        id: ifaceProc

        running: true
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE", "dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const p = root.splitLine(line);
                    if (p[1] === "wifi") {
                        root.iface = p[0];
                        break;
                    }
                }
            }
        }
    }

    Process {
        id: radioProc

        command: ["nmcli", "-t", "-f", "WIFI", "radio"]
        stdout: StdioCollector {
            onStreamFinished: root.radioOn = text.trim() === "enabled"
        }
    }

    Process {
        id: scanProc

        property bool rescan: false

        command: ["nmcli", "-t", "-f", "IN-USE,BSSID,SSID,MODE,CHAN,FREQ,RATE,BANDWIDTH,SIGNAL,SECURITY,WPA-FLAGS,RSN-FLAGS", "dev", "wifi", "list", "--rescan", scanProc.rescan ? "yes" : "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                root.lastScanAt = Date.now();
                const out = [];
                for (const line of text.split("\n")) {
                    if (line.trim() === "")
                        continue;
                    const p = root.splitLine(line);
                    if (p.length < 12)
                        continue;
                    const freq = parseInt(p[5]) || 0;
                    const sec = p[9];
                    out.push({
                        inUse: p[0].trim() === "*",
                        bssid: p[1].toUpperCase(),
                        ssid: p[2],
                        mode: p[3],
                        chan: parseInt(p[4]) || root.channelOf(freq),
                        freq: freq,
                        band: root.bandOf(freq),
                        rate: parseInt(p[6]) || 0,
                        width: parseInt(p[7]) || 20,
                        signal: parseInt(p[8]) || 0,
                        security: root.securityLabel(sec, p[11], p[10]),
                        cipher: root.cipherOf(p[11], p[10]),
                        secured: sec !== "" && sec !== "--",
                        enterprise: sec.indexOf("802.1X") !== -1,
                        sae: p[11].indexOf("sae") !== -1 && p[11].indexOf("psk") === -1
                    });
                }
                root.aps = out;
            }
        }
        onExited: root.scanning = false
    }

    Process {
        id: profilesProc

        command: ["nmcli", "-t", "-f", "NAME,TYPE", "con", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = [];
                for (const line of text.split("\n")) {
                    const p = root.splitLine(line);
                    if (p.length >= 2 && p[1] === "802-11-wireless")
                        names.push(p[0]);
                }
                root.profiles = names;
            }
        }
    }

    Process {
        id: devProc

        command: ["nmcli", "-t", "dev", "show", root.iface]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf(":");
                    if (i > 0)
                        map[line.substr(0, i)] = line.substr(i + 1);
                }
                root.dev = map;
            }
        }
    }

    Process {
        id: linkProc

        command: ["iw", "dev", root.iface, "link"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = {};
                const m = text.match(/Connected to ([0-9a-fA-F:]{17})/);
                if (m) {
                    l.bssid = m[1];
                    for (const line of text.split("\n")) {
                        const t = line.trim();
                        const i = t.indexOf(":");
                        if (i < 0)
                            continue;
                        const k = t.substr(0, i);
                        const v = t.substr(i + 1).trim();
                        if (k === "SSID")
                            l.ssid = v;
                        else if (k === "freq")
                            l.freq = parseFloat(v);
                        else if (k === "signal")
                            l.signal = parseInt(v);
                        else if (k === "rx bitrate")
                            l.rxBitrate = v;
                        else if (k === "tx bitrate")
                            l.txBitrate = v;
                        else if (k === "dtim period")
                            l.dtim = v;
                        else if (k === "beacon int")
                            l.beacon = v;
                        else if (k === "RX")
                            l.rx = v;
                        else if (k === "TX")
                            l.tx = v;
                    }
                }
                const wasSsid = root.link.ssid || "";
                root.link = l;
                if ((l.ssid || "") !== wasSsid) {
                    devProc.running = false;
                    devProc.running = true;
                }
            }
        }
    }

    Process {
        id: stationProc

        command: ["iw", "dev", root.iface, "station", "dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = {};
                for (const line of text.split("\n")) {
                    const t = line.trim();
                    const i = t.indexOf(":");
                    if (i < 0)
                        continue;
                    s[t.substr(0, i).trim()] = t.substr(i + 1).trim();
                }
                root.station = s;
            }
        }
    }

    Process {
        id: statsProc

        command: ["cat", "/sys/class/net/" + root.iface + "/statistics/rx_bytes", "/sys/class/net/" + root.iface + "/statistics/tx_bytes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("\n").map(Number);
                if (p.length < 2 || isNaN(p[0]))
                    return;
                const now = Date.now();
                if (root.lastRx >= 0 && now > root.lastSampleAt) {
                    const dt = (now - root.lastSampleAt) / 1000;
                    root.rxRate = Math.max(0, (p[0] - root.lastRx) / dt);
                    root.txRate = Math.max(0, (p[1] - root.lastTx) / dt);
                    root.rxHistory = root.rxHistory.concat([root.rxRate]).slice(-40);
                    root.txHistory = root.txHistory.concat([root.txRate]).slice(-40);
                }
                root.lastRx = p[0];
                root.lastTx = p[1];
                root.lastSampleAt = now;
            }
        }
    }

    function scan(force) {
        if (!root.radioOn)
            return;
        root.scanning = true;
        scanProc.running = false;
        scanProc.rescan = force === true;
        scanProc.running = true;
        profilesProc.running = false;
        profilesProc.running = true;
    }

    function refreshAll() {
        radioProc.running = false;
        radioProc.running = true;
        root.scan(false);
        linkProc.running = false;
        linkProc.running = true;
        devProc.running = false;
        devProc.running = true;
        stationProc.running = false;
        stationProc.running = true;
    }

    Timer {
        interval: 8000
        repeat: true
        running: root.visible
        onTriggered: root.scan(false)
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: {
            if (!statsProc.running)
                statsProc.running = true;
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.visible
        onTriggered: {
            if (!linkProc.running)
                linkProc.running = true;
            if (root.view === "connection" && !stationProc.running)
                stationProc.running = true;
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.visible && root.view === "connection"
        onTriggered: {
            if (!devProc.running)
                devProc.running = true;
        }
    }

    Timer {
        id: toastTimer

        interval: 2400
        onTriggered: root.toast = ""
    }

    // ── Actions ───────────────────────────────────────────────────────────
    // Runs nmcli steps one after another; each may feed text on stdin.
    property var steps: []
    property int stepIndex: 0
    property var stepsDone: null

    function runSteps(list, done) {
        root.steps = list;
        root.stepIndex = 0;
        root.stepsDone = done;
        root.nextStep();
    }

    function nextStep() {
        const s = root.steps[root.stepIndex];
        actionProc.feed = s.stdin || "";
        actionProc.stdinEnabled = s.stdin !== undefined;
        actionProc.exec(s.cmd);
    }

    Process {
        id: actionProc

        property string feed: ""

        stdout: StdioCollector { id: actionOut }
        stderr: StdioCollector { id: actionErr }
        onStarted: {
            if (actionProc.feed !== "") {
                actionProc.write(actionProc.feed);
                actionProc.feed = "";
            }
            if (actionProc.stdinEnabled)
                actionProc.stdinEnabled = false; // close stdin: nmcli reads to EOF
        }
        onExited: (code, status) => {
            const s = root.steps[root.stepIndex];
            if (code !== 0 && !(s && s.mayFail)) {
                const done = root.stepsDone;
                root.stepsDone = null;
                if (done)
                    done(false, (actionErr.text + " " + actionOut.text).trim());
                return;
            }
            root.stepIndex++;
            if (root.stepIndex < root.steps.length) {
                root.nextStep();
            } else {
                const done = root.stepsDone;
                root.stepsDone = null;
                if (done)
                    done(true, actionOut.text.trim());
            }
        }
    }

    function friendlyError(out) {
        const o = out.toLowerCase();
        if (o.indexOf("secrets were required") !== -1 || o.indexOf("802-11-wireless-security.psk") !== -1 || o.indexOf("no secrets") !== -1)
            return "Wrong password";
        if (o.indexOf("invalid") !== -1 && o.indexOf("psk") !== -1)
            return "That password isn't valid (8–63 characters)";
        if (o.indexOf("timeout") !== -1 || o.indexOf("timed out") !== -1)
            return "Timed out — the AP didn't answer";
        if (o.indexOf("no network with ssid") !== -1)
            return "Network is out of range";
        const line = out.split("\n").find(l => l.indexOf("Error") !== -1);
        return line ? line.replace(/^Error:\s*/, "").substr(0, 90) : "Couldn't connect";
    }

    function afterChange() {
        root.busySsid = "";
        root.busyLabel = "";
        root.refreshAll();
    }

    function connect(net) {
        if (root.busySsid !== "")
            return;
        root.errorSsid = "";
        root.errorText = "";
        const ssid = net.ssid;
        const needSecret = net.secured && !net.saved;

        if (net.saved && root.password === "") {
            root.busySsid = ssid;
            root.busyLabel = "Connecting";
            root.runSteps([{ cmd: ["nmcli", "con", "up", "id", ssid, "ifname", root.iface] }], (ok, out) => {
                root.afterChange();
                if (ok) {
                    root.expandedSsid = "";
                    root.showToast("Connected to " + ssid);
                } else {
                    root.errorSsid = ssid;
                    root.errorText = net.secured ? "Saved password didn't work — enter it again" : root.friendlyError(out);
                    root.expandedSsid = ssid;
                    root.focusPassword();
                }
            });
            return;
        }

        if (!net.secured) {
            root.busySsid = ssid;
            root.busyLabel = "Connecting";
            root.runSteps([{ cmd: ["nmcli", "dev", "wifi", "connect", ssid, "ifname", root.iface] }], (ok, out) => {
                root.afterChange();
                if (ok) {
                    root.expandedSsid = "";
                    root.showToast("Connected to " + ssid);
                } else {
                    root.errorSsid = ssid;
                    root.errorText = root.friendlyError(out);
                }
            });
            return;
        }

        if (needSecret || root.password !== "") {
            if (root.password === "" || (net.enterprise && root.identity === "")) {
                root.expandedSsid = ssid;
                root.focusPassword();
                return;
            }
            root.addAndConnect(ssid, net, false);
        }
    }

    // New profile → secret over stdin via `nmcli con edit` → bring it up.
    // A profile that never connected is removed again.
    function addAndConnect(ssid, net, hidden) {
        const secured = net ? net.secured : root.password !== "";
        const enterprise = net ? net.enterprise : false;
        const add = ["nmcli", "con", "add", "type", "wifi", "ifname", root.iface, "con-name", ssid, "ssid", ssid];
        let edit = "";
        if (hidden)
            add.push("802-11-wireless.hidden", "yes");
        if (enterprise) {
            add.push("wifi-sec.key-mgmt", "wpa-eap", "802-1x.eap", "peap", "802-1x.phase2-auth", "mschapv2", "802-1x.identity", root.identity);
            edit = "set 802-1x.password " + root.password + "\nsave\nquit\n";
        } else if (secured) {
            add.push("wifi-sec.key-mgmt", net && net.sae ? "sae" : "wpa-psk");
            edit = "set wifi-sec.psk " + root.password + "\nsave\nquit\n";
        }
        const list = [];
        if (root.profiles.indexOf(ssid) !== -1)
            list.push({ cmd: ["nmcli", "con", "delete", "id", ssid], mayFail: true });
        list.push({ cmd: add });
        if (edit !== "")
            list.push({ cmd: ["nmcli", "con", "edit", "id", ssid], stdin: edit });
        list.push({ cmd: ["nmcli", "con", "up", "id", ssid, "ifname", root.iface] });

        root.busySsid = ssid;
        root.busyLabel = "Authenticating";
        root.password = "";
        root.runSteps(list, (ok, out) => {
            if (ok) {
                root.afterChange();
                root.expandedSsid = "";
                root.hiddenOpen = false;
                root.hiddenSsid = "";
                root.identity = "";
                root.showToast("Connected to " + ssid + " · saved");
                return;
            }
            root.errorSsid = hidden ? "__hidden" : ssid;
            root.errorText = root.friendlyError(out);
            root.runSteps([{ cmd: ["nmcli", "con", "delete", "id", ssid], mayFail: true }], () => {
                root.afterChange();
                root.focusPassword();
            });
        });
    }

    function disconnect() {
        if (root.activeName === "" || root.busySsid !== "")
            return;
        const ssid = root.activeSsid;
        root.busySsid = ssid;
        root.busyLabel = "Disconnecting";
        root.runSteps([{ cmd: ["nmcli", "con", "down", "id", root.activeName] }], ok => {
            root.afterChange();
            root.showToast(ok ? "Disconnected from " + ssid : "Couldn't disconnect");
        });
    }

    function forget(ssid) {
        if (root.busySsid !== "")
            return;
        root.busySsid = ssid;
        root.busyLabel = "Forgetting";
        root.runSteps([{ cmd: ["nmcli", "con", "delete", "id", ssid] }], ok => {
            root.afterChange();
            root.expandedSsid = "";
            root.showToast(ok ? "Forgot " + ssid : "Couldn't forget " + ssid);
        });
    }

    function toggleRadio() {
        const next = !root.radioOn;
        root.radioOn = next;
        if (!next) {
            root.aps = [];
            root.link = ({});
        }
        radioToggleProc.exec(["nmcli", "radio", "wifi", next ? "on" : "off"]);
    }

    Process {
        id: radioToggleProc

        onExited: {
            radioProc.running = true;
            if (root.radioOn)
                rescanLater.restart();
        }
    }

    Timer {
        id: rescanLater

        interval: 1500
        onTriggered: root.scan(true)
    }

    // Share: the saved key, and a QR code phones can scan.
    function share(ssid) {
        if (root.shareSsid === ssid) {
            root.shareSsid = "";
            return;
        }
        root.shareSsid = ssid;
        root.sharePsk = "";
        root.shareQr = "";
        pskProc.exec(["nmcli", "-s", "-g", "802-11-wireless-security.psk", "con", "show", "id", ssid]);
    }

    function qrEscape(s) {
        return s.replace(/([\\;,:"])/g, "\\$1");
    }

    Process {
        id: pskProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.sharePsk = text.trim();
                const net = root.networks.find(n => n.ssid === root.shareSsid);
                const type = root.sharePsk === "" ? "nopass" : (net && net.sae ? "SAE" : "WPA");
                qrProc.exec(["qrencode", "-t", "SVG", "-m", "1", "--foreground=000000", "--background=ffffff", "-o", "-", "WIFI:T:" + type + ";S:" + root.qrEscape(root.shareSsid) + ";P:" + root.qrEscape(root.sharePsk) + ";;"]);
            }
        }
    }

    Process {
        id: qrProc

        stdout: StdioCollector {
            onStreamFinished: root.shareQr = text.indexOf("<svg") !== -1 ? "data:image/svg+xml;base64," + Qt.btoa(text) : ""
        }
    }

    // Diagnostics: gateway, internet, DNS, public address.
    function setDiag(key, state, value, detail) {
        const d = Object.assign({}, root.diag);
        d[key] = { state: state, value: value || "", detail: detail || "" };
        root.diag = d;
    }

    function runDiagnostics() {
        if (root.diagRunning)
            return;
        root.diagRunning = true;
        root.diag = ({});
        const gw = root.devValue("IP4.GATEWAY");
        root.diagQueue = [
            { key: "gw", cmd: gw ? ["ping", "-n", "-c", "5", "-i", "0.2", "-W", "1", gw] : null },
            { key: "net", cmd: ["ping", "-n", "-c", "5", "-i", "0.2", "-W", "1", "1.1.1.1"] },
            { key: "dns", cmd: ["sh", "-c", "s=$(date +%s%N); getent ahosts archlinux.org >/dev/null && echo $(( ($(date +%s%N) - s) / 1000000 ))"] },
            { key: "pub", cmd: ["curl", "-s", "--max-time", "5", "https://api.ipify.org"] }
        ];
        root.diagQueue.forEach(q => root.setDiag(q.key, "wait"));
        root.nextDiag();
    }

    property var diagQueue: []

    function nextDiag() {
        if (root.diagQueue.length === 0) {
            root.diagRunning = false;
            return;
        }
        const q = root.diagQueue[0];
        if (!q.cmd) {
            root.setDiag(q.key, "fail", "no gateway");
            root.diagQueue = root.diagQueue.slice(1);
            root.nextDiag();
            return;
        }
        root.setDiag(q.key, "run");
        diagProc.key = q.key;
        diagProc.exec(q.cmd);
    }

    Process {
        id: diagProc

        property string key: ""

        stdout: StdioCollector { id: diagOut }
        onExited: code => {
            const t = diagOut.text;
            const k = diagProc.key;
            if (k === "gw" || k === "net") {
                const loss = t.match(/(\d+(?:\.\d+)?)% packet loss/);
                const rtt = t.match(/= ([\d.]+)\/([\d.]+)\/([\d.]+)\/([\d.]+) ms/);
                if (rtt)
                    root.setDiag(k, "ok", Number(rtt[2]).toFixed(1) + " ms", "loss " + (loss ? loss[1] : "?") + "%  ·  jitter " + Number(rtt[4]).toFixed(1) + " ms");
                else
                    root.setDiag(k, "fail", "unreachable", loss ? loss[1] + "% loss" : "");
            } else if (k === "dns") {
                const ms = parseInt(t);
                root.setDiag(k, code === 0 && !isNaN(ms) ? "ok" : "fail", code === 0 && !isNaN(ms) ? ms + " ms" : "failed", "archlinux.org");
            } else if (k === "pub") {
                const ip = t.trim();
                root.setDiag(k, /^[\d.:a-fA-F]+$/.test(ip) ? "ok" : "fail", /^[\d.:a-fA-F]+$/.test(ip) ? ip : "unknown", "via ipify");
            }
            root.diagQueue = root.diagQueue.slice(1);
            root.nextDiag();
        }
    }

    // ── Opening ───────────────────────────────────────────────────────────
    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    property real intro: 1

    NumberAnimation {
        id: introAnim

        target: root
        property: "intro"
        from: 0
        to: 1
        duration: 850
    }

    function stage(i) {
        const t = Math.max(0, Math.min(1, (root.intro - i * 0.11) / 0.55));
        return 1 - Math.pow(1 - t, 3);
    }

    property bool settled: false

    Timer {
        id: settleTimer

        interval: 360
        onTriggered: {
            root.settled = true;
            if (root.passwordWanted)
                root.focusPassword();
        }
    }

    property bool passwordWanted: false

    // Focus waits until the island has finished opening (taking it mid-
    // morph stalls the animation).
    function focusPassword() {
        if (!root.settled) {
            root.passwordWanted = true;
            return;
        }
        root.passwordWanted = false;
        Qt.callLater(() => {
            const field = root.expandedField;
            if (field)
                field.forceActiveFocus();
        });
    }

    property Item expandedField: null

    onVisibleChanged: {
        if (root.visible) {
            root.settled = false;
            root.forceActiveFocus();
            settleTimer.restart();
            introAnim.restart();
            root.refreshAll();
            root.rxHistory = [];
            root.txHistory = [];
            root.lastRx = -1;
        } else {
            root.expandedSsid = "";
            root.password = "";
            root.identity = "";
            root.revealPassword = false;
            root.shareSsid = "";
            root.sharePsk = "";
            root.shareQr = "";
            root.hiddenOpen = false;
            root.errorSsid = "";
            root.selectedIndex = -1;
        }
    }

    onExpandedSsidChanged: {
        root.password = "";
        root.revealPassword = false;
        if (root.errorSsid !== root.expandedSsid) {
            root.errorSsid = "";
            root.errorText = "";
        }
        if (root.shareSsid !== root.expandedSsid) {
            root.shareSsid = "";
            root.sharePsk = "";
            root.shareQr = "";
        }
    }

    function stepView(step) {
        root.view = root.views[(root.viewIndex + step + root.views.length) % root.views.length].id;
    }

    function activateSelected() {
        const n = root.networks[root.selectedIndex];
        if (!n)
            return;
        if (root.expandedSsid !== n.ssid)
            root.expandedSsid = n.ssid;
        else if (!n.active)
            root.connect(n);
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Escape) {
            if (root.expandedSsid !== "")
                root.expandedSsid = "";
            else if (root.hiddenOpen)
                root.hiddenOpen = false;
            else
                root.closeRequested();
        } else if ((ctrl && event.key === Qt.Key_R) || event.key === Qt.Key_F5) {
            root.scan(true);
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.stepView(1);
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
            root.stepView(-1);
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
            root.view = root.views[event.key - Qt.Key_1].id;
        } else if (root.view === "networks" && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
            const n = root.networks.length;
            if (n > 0) {
                root.selectedIndex = root.selectedIndex < 0 ? 0 : (root.selectedIndex + (event.key === Qt.Key_Down ? 1 : -1) + n) % n;
                networkList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
            }
        } else if (root.view === "networks" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.activateSelected();
        } else if (root.view === "spectrum" && event.key === Qt.Key_B) {
            root.band = root.band === "5" ? "2.4" : "5";
        } else if (ctrl && event.key === Qt.Key_D && root.connected) {
            root.disconnect();
        } else {
            return;
        }
        event.accepted = true;
    }

    // ── Components ────────────────────────────────────────────────────────
    component IconButton: Rectangle {
        id: iconButton

        required property string icon
        property color tint: "#9a9a9a"
        property int iconSize: 14
        property string tip: ""
        property real spin: 0

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
            rotation: iconButton.spin
        }

        MouseArea {
            id: iconMouse

            anchors.fill: parent
            onClicked: iconButton.clicked()
        }
    }

    component ActionButton: Rectangle {
        id: action

        required property string text
        property string icon: ""
        property color tint: root.primaryText
        property bool primary: false
        property bool busy: false

        signal clicked

        implicitWidth: actionRow.implicitWidth + 20
        height: 28
        radius: 9
        color: action.primary ? (actionHover.hovered ? Qt.lighter(action.tint, 1.1) : action.tint) : (actionHover.hovered ? "#1d1d1d" : "#121212")
        border.width: action.primary ? 0 : 1
        border.color: actionHover.hovered ? root.withAlpha(action.tint, 0.5) : "#262626"
        scale: actionMouse.pressed ? 0.93 : 1
        opacity: enabled ? 1 : 0.4

        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
        Behavior on color { ColorAnimation { duration: 140 } }

        HoverHandler {
            id: actionHover

            cursorShape: Qt.PointingHandCursor
        }

        Row {
            id: actionRow

            anchors.centerIn: parent
            spacing: 5

            MIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: action.icon !== ""
                name: action.busy ? "progress_activity" : action.icon
                size: 13
                color: action.primary ? "#0b0b0b" : action.tint

                RotationAnimation on rotation {
                    running: action.busy
                    from: 0
                    to: 360
                    duration: 800
                    loops: Animation.Infinite
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: action.text
                color: action.primary ? "#0b0b0b" : action.tint
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            onClicked: action.clicked()
        }
    }

    // Four bars, lit by signal quality.
    component SignalBars: Item {
        id: bars

        property int signal: 0
        property color tint: root.primaryText
        property real grow: 1

        width: 18
        height: 14

        Repeater {
            model: 4

            Rectangle {
                required property int index

                readonly property bool lit: bars.signal >= [1, 30, 55, 75][index]

                x: index * 5
                anchors.bottom: parent.bottom
                width: 3
                height: (4 + index * 3.3) * bars.grow
                radius: 1.5
                color: lit ? bars.tint : "#2a2a2a"

                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    component Chip: Rectangle {
        id: chip

        required property string text
        property color tint: "#9a9a9a"

        implicitWidth: chipText.implicitWidth + 12
        height: 18
        radius: 6
        color: root.withAlpha(chip.tint, 0.1)
        border.width: 1
        border.color: root.withAlpha(chip.tint, 0.28)

        Text {
            id: chipText

            anchors.centerIn: parent
            text: chip.text
            color: chip.tint
            font.family: root.fontFamily
            font.pixelSize: 9
            font.weight: Font.Bold
        }
    }

    // A label/value line in the Connection view; click to copy.
    component InfoRow: Item {
        id: info

        required property string label
        property string value: ""
        property bool mono: true
        property color valueColor: root.primaryText

        width: parent ? parent.width : 0
        height: 20

        HoverHandler {
            id: infoHover

            cursorShape: info.value !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            onTapped: root.copy(info.label, info.value)
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -6
            anchors.rightMargin: -6
            radius: 6
            color: "#ffffff"
            opacity: infoHover.hovered && info.value !== "" ? 0.04 : 0

            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: info.label
            color: root.secondaryText
            font.family: root.fontFamily
            font.pixelSize: 10
        }

        Text {
            anchors.right: copyIcon.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, info.width - 120)
            horizontalAlignment: Text.AlignRight
            text: info.value !== "" ? info.value : "—"
            color: info.value !== "" ? info.valueColor : root.faintText
            elide: Text.ElideMiddle
            font.family: info.mono ? root.monoFamily : root.fontFamily
            font.pixelSize: 10
        }

        MIcon {
            id: copyIcon

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            name: "content_copy"
            size: 10
            width: infoHover.hovered && info.value !== "" ? 12 : 0
            opacity: infoHover.hovered && info.value !== "" ? 0.6 : 0
            color: root.secondaryText

            Behavior on width { NumberAnimation { duration: 120 } }
        }
    }

    component Section: Rectangle {
        id: section

        required property string title
        property string icon: ""
        default property alias rows: sectionColumn.data

        width: parent ? parent.width : 0
        height: sectionColumn.implicitHeight + 36
        radius: 14
        color: root.cardColor
        border.width: 1
        border.color: root.cardBorder

        Row {
            x: 12
            y: 10
            spacing: 5

            MIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: section.icon
                size: 12
                color: root.secondaryText
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: section.title
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 0.8
            }
        }

        Column {
            id: sectionColumn

            x: 14
            y: 28
            width: section.width - 28
        }
    }

    // A password field with show/hide.
    component SecretField: Rectangle {
        id: secret

        property alias text: secretInput.text
        property string placeholder: "Password"
        property bool masked: true
        property alias input: secretInput

        signal accepted

        height: 32
        radius: 10
        color: "#0c0c0c"
        border.width: 1
        border.color: secretInput.activeFocus ? "#3a3a3a" : "#222222"

        Behavior on border.color { ColorAnimation { duration: 160 } }

        TextInput {
            id: secretInput

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: eye.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            color: root.primaryText
            selectionColor: "#335a8f"
            echoMode: secret.masked ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            font.family: root.fontFamily
            font.pixelSize: 12
            clip: true
            onAccepted: secret.accepted()

            Keys.onEscapePressed: root.expandedSsid !== "" ? root.expandedSsid = "" : root.hiddenOpen = false

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: secretInput.text === ""
                text: secret.placeholder
                color: root.faintText
                font.family: root.fontFamily
                font.pixelSize: 12
            }
        }

        MIcon {
            id: eye

            visible: secret.masked !== undefined && secretInput.echoMode !== TextInput.Normal || secret.masked === false
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            name: root.revealPassword ? "visibility_off" : "visibility"
            size: 14
            color: eyeHover.hovered ? root.primaryText : root.secondaryText

            HoverHandler { id: eyeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.revealPassword = !root.revealPassword }
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panelPadding
        spacing: root.sectionSpacing

        // Header -------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 10

            // Icon with ripples while scanning
            Item {
                Layout.preferredWidth: root.headerHeight
                Layout.preferredHeight: root.headerHeight

                Repeater {
                    model: 2

                    Rectangle {
                        id: ripple

                        required property int index

                        anchors.centerIn: parent
                        width: parent.width
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1.5
                        border.color: root.accentColor
                        opacity: 0
                        visible: root.scanning

                        SequentialAnimation {
                            running: root.scanning && root.visible
                            loops: Animation.Infinite

                            PauseAnimation { duration: ripple.index * 600 }
                            ParallelAnimation {
                                NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.7; duration: 1200; easing.type: Easing.OutCubic }
                                NumberAnimation { target: ripple; property: "opacity"; from: 0.5; to: 0; duration: 1200; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#090909"
                    border.width: 1
                    border.color: root.connected ? root.withAlpha(root.accentColor, 0.4) : "#1f1f1f"

                    Behavior on border.color { ColorAnimation { duration: 300 } }
                }

                MIcon {
                    anchors.centerIn: parent
                    name: !root.radioOn ? "wifi_off" : (root.connected ? (root.quality >= 60 ? "wifi" : (root.quality >= 35 ? "wifi_2_bar" : "wifi_1_bar")) : "wifi_find")
                    size: 17
                    color: root.connected ? root.accentColor : (root.radioOn ? root.primaryText : "#555555")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "Wi-Fi"
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!root.radioOn)
                            return "Radio off";
                        if (root.busySsid !== "")
                            return root.busyLabel + " · " + root.busySsid + "…";
                        const n = root.networks.length;
                        const bits = [n + (n === 1 ? " network" : " networks"), root.aps.length + " APs"];
                        if (root.savedCount)
                            bits.push(root.savedCount + " saved");
                        return bits.join("  ·  ") + (root.scanning ? "  ·  scanning…" : "");
                    }
                    color: root.busySsid !== "" ? root.warnColor : root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            IconButton {
                id: rescanButton

                icon: "refresh"
                tip: "Rescan  (Ctrl+R)"
                enabled: root.radioOn
                onClicked: root.scan(true)

                RotationAnimation on spin {
                    running: root.scanning && root.visible
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) rescanButton.spin = 0
                }
            }

            // Radio switch
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 22
                radius: 11
                color: root.radioOn ? root.accentColor : "#141414"
                border.width: 1
                border.color: root.radioOn ? root.accentColor : "#2a2a2a"

                Behavior on color { ColorAnimation { duration: 220 } }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered)
                            root.hint = root.radioOn ? "Turn Wi-Fi off" : "Turn Wi-Fi on";
                        else if (root.hint.startsWith("Turn Wi-Fi"))
                            root.hint = "";
                    }
                }
                TapHandler { onTapped: root.toggleRadio() }

                Rectangle {
                    y: 3
                    x: root.radioOn ? parent.width - width - 3 : 3
                    width: 16
                    height: 16
                    radius: 8
                    color: root.radioOn ? "#0b0b0b" : "#4b4b4b"

                    Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    Behavior on color { ColorAnimation { duration: 220 } }
                }
            }

            IconButton {
                icon: "close"
                tip: "Close  (Esc)"
                onClicked: root.closeRequested()
            }
        }

        // Hero: the link ----------------------------------------------------------
        Rectangle {
            id: hero

            readonly property var di: root.dbmInfo(root.dbm)

            Layout.fillWidth: true
            Layout.preferredHeight: root.heroHeight
            radius: 18
            clip: true
            color: root.cardColor
            border.width: 1
            border.color: root.connected ? root.withAlpha(hero.di.color, 0.22) : root.cardBorder
            opacity: root.stage(0)
            transform: Translate { y: 14 * (1 - root.stage(0)) }

            Behavior on border.color { ColorAnimation { duration: 500 } }

            // A soft glow in the signal's colour
            Rectangle {
                x: -60
                y: -80
                width: 260
                height: 260
                radius: 130
                opacity: root.connected ? 0.13 : 0.05
                gradient: Gradient {
                    GradientStop { position: 0; color: root.connected ? hero.di.color : "#666666" }
                    GradientStop { position: 0.7; color: "transparent" }
                }

                Behavior on opacity { NumberAnimation { duration: 500 } }
            }

            // Signal gauge, -90 … -30 dBm
            Item {
                id: gauge

                property real shown: root.connected ? root.quality / 100 : 0

                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 92
                height: 92

                Behavior on shown { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: "#1c1c1c"
                        strokeWidth: 7
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"

                        PathAngleArc { centerX: 46; centerY: 46; radiusX: 40; radiusY: 40; startAngle: 135; sweepAngle: 270 }
                    }

                    ShapePath {
                        strokeColor: root.connected ? hero.di.color : "transparent"
                        strokeWidth: 7
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"

                        PathAngleArc { centerX: 46; centerY: 46; radiusX: 40; radiusY: 40; startAngle: 135; sweepAngle: Math.max(0.5, 270 * gauge.shown * root.stage(1)) }
                    }
                }

                // Tick marks at -67 (VoIP) and -50
                Repeater {
                    model: [-67, -50]

                    Rectangle {
                        required property var modelData

                        readonly property real a: (135 + 270 * (modelData + 90) / 60) * Math.PI / 180

                        x: 46 + Math.cos(a) * 49 - 1
                        y: 46 + Math.sin(a) * 49 - 1
                        width: 2
                        height: 2
                        radius: 1
                        color: "#444444"
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: -2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.connected ? String(root.dbm) : "—"
                        color: root.primaryText
                        font.family: root.fontFamily
                        font.features: { "tnum": 1 }
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "dBm"
                        color: root.secondaryText
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -2
                    text: root.connected ? hero.di.label : ""
                    color: hero.di.color
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }

            // Identity + PHY
            Column {
                x: 118
                y: 16
                width: parent.width - 118 - 150
                spacing: 4

                Text {
                    width: parent.width
                    text: !root.radioOn ? "Wi-Fi is off" : (root.connected ? root.activeSsid : (root.busySsid !== "" ? root.busySsid : "Not connected"))
                    color: root.primaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: {
                        if (!root.radioOn)
                            return "Flip the switch to scan";
                        if (!root.connected)
                            return root.busySsid !== "" ? root.busyLabel + "…" : "Pick a network below";
                        const bits = [root.devValue("IP4.ADDRESS[1]").split("/")[0] || "no IPv4"];
                        if (root.activeAp)
                            bits.push(root.activeAp.security);
                        return bits.join("  ·  ");
                    }
                    color: root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }

                Flow {
                    width: parent.width
                    spacing: 4
                    visible: root.connected

                    Chip { text: root.phyGen; tint: "#a78bfa"; visible: root.phyGen !== "" }
                    Chip { text: root.link.freq ? (root.bandOf(root.link.freq) + " GHz") : ""; tint: "#60a5fa"; visible: root.link.freq !== undefined }
                    Chip { text: root.link.freq ? "Ch " + root.channelOf(root.link.freq) : ""; tint: "#22d3ee"; visible: root.link.freq !== undefined }
                    Chip {
                        readonly property var w: (root.link.rxBitrate || "").match(/(\d+)MHz/)
                        text: w ? w[1] + " MHz" : ""
                        tint: "#34d399"
                        visible: w !== null
                    }
                    Chip {
                        readonly property var n: (root.link.txBitrate || "").match(/NSS (\d+)/)
                        text: n ? n[1] + "×" + n[1] + " MIMO" : ""
                        tint: "#fbbf24"
                        visible: n !== null
                    }
                }

                Row {
                    spacing: 12
                    visible: root.connected
                    topPadding: 2

                    Text {
                        text: "↓ " + root.rateMbps(root.link.rxBitrate).toFixed(0) + "  ↑ " + root.rateMbps(root.link.txBitrate).toFixed(0) + " Mb/s PHY"
                        color: "#9a9a9a"
                        font.family: root.monoFamily
                        font.pixelSize: 9
                    }
                }
            }

            // Live throughput
            Item {
                id: spark

                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 132
                height: 92
                visible: root.connected

                function path(values, close) {
                    const n = 40;
                    const w = spark.width;
                    const h = 58;
                    const top = 18;
                    if (values.length < 2)
                        return "M 0 " + (top + h);
                    let d = "";
                    const off = n - values.length;
                    for (let i = 0; i < values.length; i++) {
                        const x = (off + i) / (n - 1) * w;
                        const y = top + h - Math.min(1, values[i] / root.historyPeak) * h;
                        d += (i === 0 ? "M " : " L ") + x.toFixed(1) + " " + y.toFixed(1);
                    }
                    if (close)
                        d += " L " + w + " " + (top + h) + " L " + ((off) / (n - 1) * w).toFixed(1) + " " + (top + h) + " Z";
                    return d;
                }

                Row {
                    spacing: 10

                    Text {
                        text: "↓ " + root.formatRate(root.rxRate)
                        color: "#60a5fa"
                        font.family: root.monoFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }

                    Text {
                        text: "↑ " + root.formatRate(root.txRate)
                        color: "#f472b6"
                        font.family: root.monoFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                Rectangle {
                    y: 18
                    width: parent.width
                    height: 58
                    radius: 8
                    color: "#0b0b0b"
                    border.width: 1
                    border.color: "#161616"
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 0; y1: 18; x2: 0; y2: 76
                            GradientStop { position: 0; color: "#5560a5fa" }
                            GradientStop { position: 1; color: "#0060a5fa" }
                        }
                        PathSvg { path: spark.path(root.rxHistory, true) }
                    }

                    ShapePath {
                        strokeColor: "#60a5fa"
                        strokeWidth: 1.5
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: spark.path(root.rxHistory, false) }
                    }

                    ShapePath {
                        strokeColor: "#f472b6"
                        strokeWidth: 1.2
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: spark.path(root.txHistory, false) }
                    }
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: "peak " + root.formatRate(root.historyPeak)
                    color: root.faintText
                    font.family: root.monoFamily
                    font.pixelSize: 8
                }

                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: "40 s"
                    color: root.faintText
                    font.family: root.monoFamily
                    font.pixelSize: 8
                }
            }

            // Disconnected: a slow sonar
            Item {
                anchors.right: parent.right
                anchors.rightMargin: 40
                anchors.verticalCenter: parent.verticalCenter
                width: 60
                height: 60
                visible: !root.connected

                Repeater {
                    model: 3

                    Rectangle {
                        id: sonar

                        required property int index

                        anchors.centerIn: parent
                        width: 60
                        height: 60
                        radius: 30
                        color: "transparent"
                        border.width: 1
                        border.color: root.radioOn ? "#3a3a3a" : "#222222"
                        opacity: 0

                        SequentialAnimation {
                            running: !root.connected && root.visible && root.radioOn
                            loops: Animation.Infinite

                            PauseAnimation { duration: sonar.index * 700 }
                            ParallelAnimation {
                                NumberAnimation { target: sonar; property: "scale"; from: 0.2; to: 1.4; duration: 2100; easing.type: Easing.OutCubic }
                                NumberAnimation { target: sonar; property: "opacity"; from: 0.9; to: 0; duration: 2100 }
                            }
                        }
                    }
                }

                MIcon {
                    anchors.centerIn: parent
                    name: root.radioOn ? "wifi_find" : "wifi_off"
                    size: 22
                    color: "#555555"
                }
            }
        }

        // Tabs --------------------------------------------------------------------
        Rectangle {
            id: tabs

            readonly property real segment: (tabs.width - 6) / root.views.length

            Layout.fillWidth: true
            Layout.preferredHeight: root.tabsHeight
            radius: 11
            color: root.cardColor
            border.width: 1
            border.color: root.cardBorder
            opacity: root.stage(1)
            transform: Translate { y: 12 * (1 - root.stage(1)) }

            Rectangle {
                x: 3 + tabs.segment * root.viewIndex
                y: 3
                width: tabs.segment
                height: tabs.height - 6
                radius: 8
                color: "#1a1a1a"
                border.width: 1
                border.color: "#2a2a2a"

                Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
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
                        readonly property bool active: root.viewIndex === index

                        width: tabs.segment
                        height: tabs.height - 6

                        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.view = tab.modelData.id }

                        Row {
                            anchors.centerIn: parent
                            spacing: 5

                            MIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: tab.modelData.icon
                                size: 13
                                color: tab.active ? root.primaryText : (tabHover.hovered ? "#b0b0b0" : "#6a6a6a")

                                Behavior on color { ColorAnimation { duration: 180 } }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tab.modelData.label
                                color: tab.active ? root.primaryText : (tabHover.hovered ? "#b0b0b0" : "#6a6a6a")
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold

                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                        }
                    }
                }
            }
        }

        // Pages ---------------------------------------------------------------------
        Item {
            id: pages

            property real slide: root.viewIndex

            Layout.fillWidth: true
            Layout.preferredHeight: root.pageHeight
            clip: true
            opacity: root.stage(2)
            transform: Translate { y: 12 * (1 - root.stage(2)) }

            Behavior on slide { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

            function pageX(i) {
                return (i - pages.slide) * (pages.width + 24);
            }

            function pageOpacity(i) {
                return Math.max(0, 1 - Math.abs(i - pages.slide) * 1.4);
            }

            // ── Networks ──────────────────────────────────────────────
            Item {
                id: networksPage

                x: pages.pageX(0)
                width: pages.width
                height: pages.height
                opacity: pages.pageOpacity(0)
                visible: opacity > 0

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: !root.radioOn || (root.networks.length === 0 && !root.scanning)

                    MIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: root.radioOn ? "wifi_find" : "wifi_off"
                        size: 30
                        color: "#3a3a3a"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.radioOn ? "No networks in range" : "Wi-Fi is off"
                        color: root.secondaryText
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }

                ListView {
                    id: networkList

                    anchors.fill: parent
                    visible: root.radioOn
                    clip: true
                    spacing: 5
                    model: root.networks
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 400

                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic }
                    }

                    footer: Item {
                        width: networkList.width
                        height: hiddenCard.height + 5

                        // Connect to a network that doesn't broadcast its name.
                        Rectangle {
                            id: hiddenCard

                            y: 5
                            width: parent.width
                            height: root.hiddenOpen ? 128 : 36
                            radius: 12
                            color: root.cardColor
                            border.width: 1
                            border.color: root.hiddenOpen ? "#2a2a2a" : root.cardBorder
                            clip: true

                            Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                            Item {
                                width: parent.width
                                height: 36

                                HoverHandler { id: hiddenHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        root.hiddenOpen = !root.hiddenOpen;
                                        if (root.hiddenOpen)
                                            Qt.callLater(() => hiddenSsidInput.forceActiveFocus());
                                    }
                                }

                                MIcon {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "visibility_off"
                                    size: 14
                                    color: hiddenHover.hovered ? root.primaryText : root.secondaryText
                                }

                                Text {
                                    x: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Hidden network…"
                                    color: hiddenHover.hovered ? root.primaryText : root.secondaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }

                            Column {
                                x: 12
                                y: 38
                                width: parent.width - 24
                                spacing: 6
                                visible: root.hiddenOpen

                                Rectangle {
                                    width: parent.width
                                    height: 32
                                    radius: 10
                                    color: "#0c0c0c"
                                    border.width: 1
                                    border.color: hiddenSsidInput.activeFocus ? "#3a3a3a" : "#222222"

                                    TextInput {
                                        id: hiddenSsidInput

                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.primaryText
                                        font.family: root.fontFamily
                                        font.pixelSize: 12
                                        clip: true
                                        onTextEdited: root.hiddenSsid = text
                                        Keys.onEscapePressed: root.hiddenOpen = false
                                        Keys.onReturnPressed: hiddenPass.input.forceActiveFocus()

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: hiddenSsidInput.text === ""
                                            text: "SSID"
                                            color: root.faintText
                                            font.family: root.fontFamily
                                            font.pixelSize: 12
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 6

                                    SecretField {
                                        id: hiddenPass

                                        width: parent.width - hiddenGo.width - 6
                                        placeholder: "Password (empty if open)"
                                        masked: !root.revealPassword
                                        onTextChanged: root.password = text
                                        onAccepted: hiddenGo.clicked()
                                    }

                                    ActionButton {
                                        id: hiddenGo

                                        text: "Join"
                                        icon: "login"
                                        primary: true
                                        tint: root.accentColor
                                        height: 32
                                        enabled: root.hiddenSsid.trim() !== "" && root.busySsid === ""
                                        busy: root.busySsid === root.hiddenSsid && root.hiddenSsid !== ""
                                        onClicked: {
                                            if (root.hiddenSsid.trim() === "")
                                                return;
                                            root.addAndConnect(root.hiddenSsid.trim(), null, true);
                                            hiddenPass.text = "";
                                        }
                                    }
                                }

                                Text {
                                    visible: root.errorSsid === "__hidden"
                                    text: root.errorText
                                    color: root.errorColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property var net: modelData
                        readonly property bool expanded: root.expandedSsid === net.ssid
                        readonly property bool busy: root.busySsid === net.ssid
                        readonly property bool lit: rowHover.hovered || root.selectedIndex === index
                        readonly property bool hasError: root.errorSsid === net.ssid
                        readonly property real appear: Math.max(0, Math.min(1, (root.intro * 1.7 - 0.35 - Math.min(index, 8) * 0.06) / 0.5))

                        width: networkList.width
                        height: 46 + (expanded ? expandArea.implicitHeight + 8 : 0)
                        radius: 12
                        color: row.expanded ? "#0d0d0d" : (row.lit ? "#101010" : root.cardColor)
                        border.width: 1
                        border.color: row.net.active ? root.withAlpha(root.accentColor, 0.4) : (row.expanded ? "#2a2a2a" : (row.lit ? "#252525" : root.cardBorder))
                        clip: true
                        opacity: row.appear
                        transform: Translate { x: 16 * (1 - row.appear) }

                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 140 } }

                        // Shimmer while connecting
                        Rectangle {
                            id: shimmer

                            visible: row.busy
                            y: 0
                            width: 120
                            height: 46
                            opacity: 0.08
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 0.5; color: "#ffffff" }
                                GradientStop { position: 1; color: "transparent" }
                            }

                            NumberAnimation on x {
                                running: row.busy
                                from: -120
                                to: row.width
                                duration: 1100
                                loops: Animation.Infinite
                            }
                        }

                        // Wrong password: a little shake
                        SequentialAnimation {
                            id: shake

                            NumberAnimation { target: row; property: "x"; to: -6; duration: 50 }
                            NumberAnimation { target: row; property: "x"; to: 6; duration: 70 }
                            NumberAnimation { target: row; property: "x"; to: -3; duration: 60 }
                            NumberAnimation { target: row; property: "x"; to: 0; duration: 60 }
                        }

                        onHasErrorChanged: if (row.hasError) shake.restart()

                        Item {
                            id: rowHead

                            width: parent.width
                            height: 46

                            HoverHandler {
                                id: rowHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    root.selectedIndex = row.index;
                                    root.expandedSsid = row.expanded ? "" : row.net.ssid;
                                    if (!row.expanded && row.net.secured && !row.net.saved && !row.net.active)
                                        root.focusPassword();
                                }
                                onDoubleTapped: if (!row.net.active) root.connect(row.net)
                            }

                            SignalBars {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                signal: row.net.signal
                                tint: row.net.active ? root.accentColor : root.signalColor(row.net.signal)
                                grow: row.appear
                            }

                            Column {
                                x: 44
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 44 - rightInfo.width - 20
                                spacing: 1

                                Row {
                                    spacing: 6
                                    width: parent.width

                                    Text {
                                        id: ssidText

                                        width: Math.min(implicitWidth, parent.width - (activeBadge.visible ? activeBadge.width + 6 : 0))
                                        text: row.net.ssid
                                        color: root.primaryText
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: 12
                                        font.weight: row.net.active ? Font.Bold : Font.DemiBold
                                    }

                                    Chip {
                                        id: activeBadge

                                        anchors.verticalCenter: ssidText.verticalCenter
                                        visible: row.net.active || row.busy
                                        text: row.busy ? root.busyLabel.toUpperCase() : "CONNECTED"
                                        tint: row.busy ? root.warnColor : root.accentColor
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: [row.net.security, row.net.bandLabel, row.net.aps.length > 1 ? row.net.aps.length + " APs" : "ch " + row.net.aps[0].chan, row.net.saved && !row.net.active ? "saved" : ""].filter(s => s).join("  ·  ")
                                    color: row.hasError ? root.errorColor : root.secondaryText
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }
                            }

                            Row {
                                id: rightInfo

                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                MIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: row.net.saved
                                    name: "bookmark"
                                    size: 12
                                    color: "#6a6a6a"
                                }

                                MIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: row.net.enterprise ? "badge" : (row.net.secured ? "lock" : "lock_open")
                                    size: 12
                                    color: row.net.secured ? "#6a6a6a" : root.warnColor
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30
                                    horizontalAlignment: Text.AlignRight
                                    text: row.net.signal + "%"
                                    color: root.signalColor(row.net.signal)
                                    font.family: root.monoFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }

                                MIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "expand_more"
                                    size: 16
                                    color: "#5a5a5a"
                                    rotation: row.expanded ? 180 : 0

                                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                }
                            }
                        }

                        // Expanded: APs, password, actions, share
                        Column {
                            id: expandArea

                            x: 12
                            y: 46
                            width: parent.width - 24
                            spacing: 8
                            visible: row.expanded
                            opacity: row.expanded ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: 220 } }

                            // Access points
                            Rectangle {
                                width: parent.width
                                height: apColumn.implicitHeight + 12
                                radius: 9
                                color: "#070707"
                                border.width: 1
                                border.color: "#171717"

                                Column {
                                    id: apColumn

                                    x: 8
                                    y: 6
                                    width: parent.width - 16
                                    spacing: 2

                                    Row {
                                        width: parent.width
                                        height: 14

                                        Repeater {
                                            model: [["BSSID", 0.36], ["CH", 0.1], ["BAND", 0.13], ["WIDTH", 0.13], ["RATE", 0.15], ["SIG", 0.13]]

                                            Text {
                                                required property var modelData

                                                width: apColumn.width * modelData[1]
                                                text: modelData[0]
                                                color: root.faintText
                                                font.family: root.fontFamily
                                                font.pixelSize: 8
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0.6
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: row.net.aps

                                        Item {
                                            id: apRow

                                            required property var modelData
                                            readonly property bool current: modelData.bssid === (root.link.bssid || "").toUpperCase()

                                            width: apColumn.width
                                            height: 16

                                            HoverHandler { id: apHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: root.copy("BSSID", apRow.modelData.bssid) }

                                            Row {
                                                anchors.fill: parent

                                                Repeater {
                                                    model: [
                                                        [apRow.modelData.bssid, 0.36],
                                                        [String(apRow.modelData.chan), 0.1],
                                                        [apRow.modelData.band + " GHz", 0.13],
                                                        [apRow.modelData.width + " MHz", 0.13],
                                                        [apRow.modelData.rate + " Mb/s", 0.15],
                                                        [apRow.modelData.signal + "%", 0.13]
                                                    ]

                                                    Text {
                                                        required property var modelData
                                                        required property int index

                                                        width: apColumn.width * modelData[1]
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData[0]
                                                        color: apRow.current ? root.accentColor : (index === 5 ? root.signalColor(apRow.modelData.signal) : (apHover.hovered ? root.primaryText : "#a0a0a0"))
                                                        elide: Text.ElideRight
                                                        font.family: root.monoFamily
                                                        font.pixelSize: 9
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Credentials, when needed
                            Column {
                                width: parent.width
                                spacing: 6
                                visible: !row.net.active && row.net.secured && (!row.net.saved || row.hasError)

                                Text {
                                    visible: row.net.enterprise
                                    width: parent.width
                                    text: "802.1X · PEAP / MSCHAPv2"
                                    color: root.secondaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }

                                Rectangle {
                                    visible: row.net.enterprise
                                    width: parent.width
                                    height: 32
                                    radius: 10
                                    color: "#0c0c0c"
                                    border.width: 1
                                    border.color: identityInput.activeFocus ? "#3a3a3a" : "#222222"

                                    TextInput {
                                        id: identityInput

                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.primaryText
                                        font.family: root.fontFamily
                                        font.pixelSize: 12
                                        clip: true
                                        onTextEdited: root.identity = text
                                        Keys.onEscapePressed: root.expandedSsid = ""
                                        Keys.onReturnPressed: passField.input.forceActiveFocus()

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: identityInput.text === ""
                                            text: "Username / identity"
                                            color: root.faintText
                                            font.family: root.fontFamily
                                            font.pixelSize: 12
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 6

                                    SecretField {
                                        id: passField

                                        width: parent.width - joinButton.width - 6
                                        masked: !root.revealPassword
                                        placeholder: row.net.sae ? "WPA3 password" : "Password"
                                        onTextChanged: root.password = text
                                        onAccepted: joinButton.clicked()

                                        Component.onCompleted: if (row.expanded) root.expandedField = row.net.enterprise ? identityInput : passField.input
                                        Connections {
                                            target: row

                                            function onExpandedChanged() {
                                                if (row.expanded) {
                                                    passField.text = "";
                                                    root.expandedField = row.net.enterprise ? identityInput : passField.input;
                                                }
                                            }
                                        }
                                    }

                                    ActionButton {
                                        id: joinButton

                                        text: "Join"
                                        icon: "login"
                                        primary: true
                                        tint: root.accentColor
                                        height: 32
                                        busy: row.busy
                                        enabled: root.busySsid === "" && (!row.net.enterprise || root.identity !== "")
                                        onClicked: {
                                            if (root.password === "")
                                                return;
                                            root.addAndConnect(row.net.ssid, row.net, false);
                                            passField.text = "";
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: row.hasError
                                width: parent.width
                                text: root.errorText
                                color: root.errorColor
                                wrapMode: Text.Wrap
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            // Actions
                            Row {
                                spacing: 6

                                ActionButton {
                                    visible: !row.net.active && (row.net.saved || !row.net.secured) && !row.hasError
                                    text: "Connect"
                                    icon: "login"
                                    primary: true
                                    tint: root.accentColor
                                    busy: row.busy
                                    enabled: root.busySsid === ""
                                    onClicked: root.connect(row.net)
                                }

                                ActionButton {
                                    visible: row.net.active
                                    text: "Disconnect"
                                    icon: "link_off"
                                    tint: root.errorColor
                                    busy: row.busy
                                    enabled: root.busySsid === ""
                                    onClicked: root.disconnect()
                                }

                                ActionButton {
                                    visible: row.net.active
                                    text: "Details"
                                    icon: "lan"
                                    onClicked: root.view = "connection"
                                }

                                ActionButton {
                                    visible: row.net.saved && row.net.secured && !row.net.enterprise
                                    text: root.shareSsid === row.net.ssid ? "Hide" : "Share"
                                    icon: "qr_code_2"
                                    onClicked: root.share(row.net.ssid)
                                }

                                ActionButton {
                                    visible: row.net.saved
                                    text: "Forget"
                                    icon: "delete"
                                    tint: "#9a9a9a"
                                    enabled: root.busySsid === ""
                                    onClicked: root.forget(row.net.ssid)
                                }
                            }

                            // Share: key + QR
                            Rectangle {
                                visible: root.shareSsid === row.net.ssid
                                width: parent.width
                                height: 112
                                radius: 10
                                color: "#070707"
                                border.width: 1
                                border.color: "#171717"

                                Rectangle {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 96
                                    height: 96
                                    radius: 8
                                    color: "#ffffff"
                                    opacity: qr.opacity
                                    scale: qr.scale
                                }

                                Image {
                                    id: qr

                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 88
                                    height: 88
                                    source: root.shareQr
                                    sourceSize: Qt.size(184, 184)
                                    smooth: false
                                    opacity: status === Image.Ready ? 1 : 0
                                    scale: status === Image.Ready ? 1 : 0.8

                                    Behavior on opacity { NumberAnimation { duration: 260 } }
                                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                                }

                                Column {
                                    x: 116
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 126
                                    spacing: 4

                                    Text {
                                        text: "SCAN TO JOIN"
                                        color: root.secondaryText
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.8
                                    }

                                    Text {
                                        width: parent.width
                                        text: root.sharePsk !== "" ? root.sharePsk : "…"
                                        color: root.primaryText
                                        elide: Text.ElideRight
                                        font.family: root.monoFamily
                                        font.pixelSize: 13
                                        font.weight: Font.Bold

                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.copy("password", root.sharePsk) }
                                    }

                                    Text {
                                        text: "Click the key to copy it"
                                        color: root.faintText
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Connection ────────────────────────────────────────────
            Flickable {
                id: connectionPage

                x: pages.pageX(1)
                width: pages.width
                height: pages.height
                opacity: pages.pageOpacity(1)
                visible: opacity > 0
                clip: true
                contentHeight: connColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: connColumn

                    width: connectionPage.width
                    spacing: 8

                    // Diagnostics
                    Rectangle {
                        width: parent.width
                        height: 96
                        radius: 14
                        color: root.cardColor
                        border.width: 1
                        border.color: root.cardBorder

                        Row {
                            x: 12
                            y: 10
                            spacing: 5

                            MIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "network_ping"
                                size: 12
                                color: root.secondaryText
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "DIAGNOSTICS"
                                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                        }

                        ActionButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            y: 5
                            height: 24
                            text: root.diagRunning ? "Running" : "Run tests"
                            icon: "play_arrow"
                            busy: root.diagRunning
                            enabled: root.connected && !root.diagRunning
                            onClicked: root.runDiagnostics()
                        }

                        Row {
                            x: 10
                            y: 36
                            spacing: 6

                            Repeater {
                                model: [
                                    { key: "gw", label: "Gateway", icon: "router" },
                                    { key: "net", label: "1.1.1.1", icon: "public" },
                                    { key: "dns", label: "DNS", icon: "dns" },
                                    { key: "pub", label: "Public IP", icon: "language" }
                                ]

                                Rectangle {
                                    id: diagTile

                                    required property var modelData
                                    readonly property var d: root.diag[modelData.key] || { state: "idle", value: "", detail: "" }
                                    readonly property color tint: d.state === "ok" ? root.accentColor : (d.state === "fail" ? root.errorColor : (d.state === "run" ? root.warnColor : "#5a5a5a"))

                                    width: (connColumn.width - 20 - 18) / 4
                                    height: 50
                                    radius: 10
                                    color: "#0c0c0c"
                                    border.width: 1
                                    border.color: root.withAlpha(diagTile.tint, diagTile.d.state === "idle" ? 0.15 : 0.35)

                                    Behavior on border.color { ColorAnimation { duration: 300 } }

                                    HoverHandler {
                                        cursorShape: diagTile.d.value !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onHoveredChanged: {
                                            if (hovered && diagTile.d.detail)
                                                root.hint = diagTile.modelData.label + ": " + diagTile.d.detail;
                                            else if (!hovered && root.hint.startsWith(diagTile.modelData.label + ":"))
                                                root.hint = "";
                                        }
                                    }
                                    TapHandler { onTapped: root.copy(diagTile.modelData.label, diagTile.d.value) }

                                    Row {
                                        x: 8
                                        y: 7
                                        spacing: 4

                                        MIcon {
                                            id: diagIcon

                                            anchors.verticalCenter: parent.verticalCenter
                                            name: diagTile.modelData.icon
                                            size: 11
                                            color: diagTile.tint

                                            SequentialAnimation on opacity {
                                                running: diagTile.d.state === "run"
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.3; duration: 400 }
                                                NumberAnimation { to: 1; duration: 400 }
                                                onRunningChanged: if (!running) diagIcon.opacity = 1
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: diagTile.modelData.label
                                            color: root.secondaryText
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Text {
                                        x: 8
                                        y: 24
                                        width: parent.width - 14
                                        text: diagTile.d.state === "idle" ? "—" : (diagTile.d.state === "wait" ? "queued" : (diagTile.d.state === "run" ? "testing…" : diagTile.d.value))
                                        color: diagTile.d.state === "ok" ? root.primaryText : (diagTile.d.state === "fail" ? root.errorColor : root.faintText)
                                        elide: Text.ElideRight
                                        font.family: root.monoFamily
                                        font.pixelSize: diagTile.modelData.key === "pub" ? 9 : 12
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        title: "LINK · 802.11"
                        icon: "cell_tower"

                        InfoRow { label: "SSID"; value: root.activeSsid; mono: false }
                        InfoRow { label: "BSSID"; value: (root.link.bssid || "").toUpperCase() }
                        InfoRow { label: "Frequency / channel"; value: root.link.freq ? root.link.freq + " MHz · ch " + root.channelOf(root.link.freq) + " · " + root.bandOf(root.link.freq) + " GHz" : "" }
                        InfoRow { label: "Standard"; value: root.phyGen !== "" ? root.phyGen + " (" + ({ "Wi-Fi 7": "802.11be", "Wi-Fi 6": "802.11ax", "Wi-Fi 5": "802.11ac", "Wi-Fi 4": "802.11n", "Legacy": "802.11a/b/g" })[root.phyGen] + ")" : "" }
                        InfoRow { label: "Signal"; value: root.connected ? root.dbm + " dBm · avg " + (root.station["signal avg"] || "?") : ""; valueColor: root.dbmInfo(root.dbm).color }
                        InfoRow { label: "TX rate"; value: root.link.txBitrate ? root.rateMbps(root.link.txBitrate) + " Mb/s · " + root.phyDetail(root.link.txBitrate) : "" }
                        InfoRow { label: "RX rate"; value: root.link.rxBitrate ? root.rateMbps(root.link.rxBitrate) + " Mb/s · " + root.phyDetail(root.link.rxBitrate) : "" }
                        InfoRow {
                            readonly property real tx: Number(root.station["tx packets"] || 0)
                            readonly property real retries: Number(root.station["tx retries"] || 0)
                            label: "TX retries / failed"
                            value: tx > 0 ? retries + " (" + (retries / tx * 100).toFixed(1) + "%) / " + (root.station["tx failed"] || "0") : ""
                            valueColor: tx > 0 && retries / tx > 0.3 ? root.warnColor : root.primaryText
                        }
                        InfoRow { label: "Beacon int · DTIM · loss"; value: root.connected ? (root.link.beacon || "?") + " TU · " + (root.link.dtim || "?") + " · " + (root.station["beacon loss"] || "0") : "" }
                        InfoRow { label: "WMM · PMF (802.11w)"; value: root.station["WMM/WME"] !== undefined ? root.station["WMM/WME"] + " · " + (root.station["MFP"] || "?") : "" }
                        InfoRow { label: "Associated for"; value: root.station["connected time"] ? root.formatDuration(parseInt(root.station["connected time"])) : "" }
                        InfoRow { label: "Traffic RX / TX"; value: root.station["rx bytes"] ? root.formatBytes(Number(root.station["rx bytes"])) + " / " + root.formatBytes(Number(root.station["tx bytes"])) : "" }
                    }

                    Section {
                        title: "SECURITY"
                        icon: "shield"

                        InfoRow { label: "Mode"; value: root.activeAp ? root.activeAp.security : ""; mono: false }
                        InfoRow { label: "Pairwise cipher"; value: root.activeAp ? root.activeAp.cipher : "" }
                        InfoRow { label: "Profile"; value: root.activeName; mono: false }
                    }

                    Section {
                        title: "IPv4"
                        icon: "lan"

                        InfoRow {
                            readonly property string addr: root.devValue("IP4.ADDRESS[1]")
                            label: "Address / mask"
                            value: addr !== "" ? addr + "  (" + root.prefixToMask(parseInt(addr.split("/")[1])) + ")" : ""
                        }
                        InfoRow { label: "Default gateway"; value: root.devValue("IP4.GATEWAY") }
                        InfoRow { label: "DNS"; value: root.devList("IP4.DNS").join(", ") }
                        InfoRow { label: "Broadcast"; value: root.dhcpOption("broadcast_address") }
                        InfoRow { label: "Domain"; value: root.devList("IP4.DOMAIN").join(", ") }
                        InfoRow { label: "DHCP server"; value: root.dhcpOption("dhcp_server_identifier") }
                        InfoRow {
                            readonly property real expiry: Number(root.dhcpOption("expiry") || 0)
                            readonly property real lease: Number(root.dhcpOption("dhcp_lease_time") || 0)
                            label: "Lease"
                            value: lease > 0 ? root.formatDuration(lease) + (expiry > 0 ? " · renews in " + root.formatDuration(expiry - Date.now() / 1000) : "") : ""
                        }
                    }

                    Section {
                        title: "IPv6"
                        icon: "hub"

                        Repeater {
                            model: root.devList("IP6.ADDRESS")

                            InfoRow {
                                required property var modelData
                                label: modelData.startsWith("fe80") ? "Link-local" : "Global"
                                value: modelData
                            }
                        }
                        InfoRow { label: "Gateway"; value: root.devValue("IP6.GATEWAY") }
                        InfoRow { label: "DNS"; value: root.devList("IP6.DNS").join(", ") }
                    }

                    Section {
                        title: "ADAPTER"
                        icon: "memory"

                        InfoRow { label: "Interface"; value: root.iface }
                        InfoRow { label: "MAC"; value: root.devValue("GENERAL.HWADDR") }
                        InfoRow { label: "MTU"; value: root.devValue("GENERAL.MTU") }
                        InfoRow { label: "Chipset"; value: root.devValue("GENERAL.PRODUCT").replace(/\s*\(.*\)\s*/, " ").trim() || root.devValue("GENERAL.VENDOR"); mono: false }
                        InfoRow { label: "Driver · firmware"; value: root.devValue("GENERAL.DRIVER") ? root.devValue("GENERAL.DRIVER") + " · " + root.devValue("GENERAL.FIRMWARE-VERSION") : "" }
                    }
                }
            }

            // ── Spectrum ──────────────────────────────────────────────
            Item {
                id: spectrumPage

                readonly property var bandAps: root.aps.filter(a => a.band === root.band)
                readonly property real fMin: root.band === "2.4" ? 2392 : 5160
                readonly property real fMax: root.band === "2.4" ? 2492 : 5845
                readonly property var ticks: root.band === "2.4" ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] : [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157, 165]
                readonly property var candidates: root.band === "2.4" ? [1, 6, 11] : [36, 52, 100, 116, 132, 149]

                // How crowded a channel is: overlapping APs, weighted by signal.
                function load(ch) {
                    const f = root.band === "2.4" ? 2407 + ch * 5 : 5000 + ch * 5;
                    let sum = 0;
                    for (const a of spectrumPage.bandAps) {
                        const c = root.centerFreq(a.freq, a.width);
                        if (Math.abs(c - f) < a.width / 2 + 10)
                            sum += a.signal;
                    }
                    return sum;
                }

                readonly property var best: {
                    let bestCh = spectrumPage.candidates[0];
                    let bestLoad = Infinity;
                    for (const c of spectrumPage.candidates) {
                        const l = spectrumPage.load(c);
                        if (l < bestLoad) {
                            bestLoad = l;
                            bestCh = c;
                        }
                    }
                    return { ch: bestCh, load: bestLoad };
                }

                property real grow: 1

                NumberAnimation on grow {
                    id: specGrow

                    running: false
                    from: 0
                    to: 1
                    duration: 900
                    easing.type: Easing.OutCubic
                }

                Connections {
                    target: root

                    function onViewChanged() {
                        if (root.view === "spectrum")
                            specGrow.restart();
                    }

                    function onBandChanged() {
                        specGrow.restart();
                    }
                }

                x: pages.pageX(2)
                width: pages.width
                height: pages.height
                opacity: pages.pageOpacity(2)
                visible: opacity > 0

                Rectangle {
                    id: graph

                    readonly property real plotX: 30
                    readonly property real plotW: width - plotX - 10
                    readonly property real plotTop: 14
                    readonly property real plotH: height - plotTop - 30

                    function fx(f) {
                        return graph.plotX + (f - spectrumPage.fMin) / (spectrumPage.fMax - spectrumPage.fMin) * graph.plotW;
                    }

                    function sy(signal) {
                        return graph.plotTop + graph.plotH * (1 - signal / 100 * spectrumPage.grow);
                    }

                    width: parent.width
                    height: 240
                    radius: 14
                    color: root.cardColor
                    border.width: 1
                    border.color: root.cardBorder
                    clip: true

                    // Grid
                    Repeater {
                        model: [25, 50, 75, 100]

                        Item {
                            required property var modelData

                            y: graph.plotTop + graph.plotH * (1 - modelData / 100)
                            width: graph.width
                            height: 1

                            Rectangle {
                                x: graph.plotX
                                width: graph.plotW
                                height: 1
                                color: "#141414"
                            }

                            Text {
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData + "%"
                                color: root.faintText
                                font.family: root.monoFamily
                                font.pixelSize: 8
                            }
                        }
                    }

                    // Suggested channel band
                    Rectangle {
                        readonly property real f: root.band === "2.4" ? 2407 + spectrumPage.best.ch * 5 : 5000 + spectrumPage.best.ch * 5
                        x: graph.fx(f - 10)
                        y: graph.plotTop
                        width: graph.fx(f + 10) - graph.fx(f - 10)
                        height: graph.plotH
                        color: root.accentColor
                        opacity: 0.06
                        visible: spectrumPage.bandAps.length > 0

                        Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }

                    // Every AP as a hill across its channel width
                    Repeater {
                        model: spectrumPage.bandAps

                        Shape {
                            id: hill

                            required property var modelData
                            readonly property real c: root.centerFreq(modelData.freq, modelData.width)
                            readonly property real x0: graph.fx(c - modelData.width / 2)
                            readonly property real x1: graph.fx(c + modelData.width / 2)
                            readonly property real peak: graph.sy(modelData.signal)
                            readonly property real base: graph.plotTop + graph.plotH
                            readonly property bool mine: modelData.bssid === (root.link.bssid || "").toUpperCase()
                            readonly property color tint: hill.mine ? root.accentColor : root.ssidColor(modelData.ssid || modelData.bssid)

                            anchors.fill: parent
                            z: hill.mine ? 2 : 1
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: hill.tint
                                strokeWidth: hill.mine ? 2 : 1.2
                                fillColor: root.withAlpha(hill.tint, hill.mine ? 0.18 : 0.08)

                                PathSvg {
                                    path: {
                                        const w = hill.x1 - hill.x0;
                                        const r = Math.min(w * 0.22, 14);
                                        return "M " + hill.x0 + " " + hill.base
                                            + " C " + (hill.x0 + r * 0.6) + " " + hill.base + " " + (hill.x0 + r * 0.4) + " " + hill.peak + " " + (hill.x0 + r) + " " + hill.peak
                                            + " L " + (hill.x1 - r) + " " + hill.peak
                                            + " C " + (hill.x1 - r * 0.4) + " " + hill.peak + " " + (hill.x1 - r * 0.6) + " " + hill.base + " " + hill.x1 + " " + hill.base;
                                    }
                                }
                            }
                        }
                    }

                    // Labels on the strongest AP of each SSID, nudged up so
                    // networks sharing a channel don't print over each other.
                    Repeater {
                        model: {
                            const seen = {};
                            const picks = spectrumPage.bandAps.slice().sort((a, b) => b.signal - a.signal).filter(a => {
                                const k = a.ssid || a.bssid;
                                if (seen[k])
                                    return false;
                                seen[k] = true;
                                return true;
                            }).slice(0, 9);
                            const placed = [];
                            const out = [];
                            for (const a of picks) {
                                const name = a.ssid !== "" ? a.ssid : "(hidden)";
                                const w = name.length * 5.4 + 6;
                                const cx = graph.fx(root.centerFreq(a.freq, a.width));
                                const x = Math.max(graph.plotX, Math.min(graph.plotX + graph.plotW - w, cx - w / 2));
                                let y = graph.plotTop + graph.plotH * (1 - a.signal / 100) - 14;
                                let moved = true;
                                while (moved) {
                                    moved = false;
                                    for (const p of placed) {
                                        if (x < p.x + p.w && p.x < x + w && Math.abs(y - p.y) < 12) {
                                            y = p.y - 12;
                                            moved = true;
                                        }
                                    }
                                }
                                if (y < 0)
                                    continue;
                                placed.push({ x: x, y: y, w: w });
                                out.push({ name: name, x: x, y: y, mine: a.bssid === (root.link.bssid || "").toUpperCase(), tint: root.ssidColor(a.ssid || a.bssid) });
                            }
                            return out;
                        }

                        Text {
                            required property var modelData

                            x: modelData.x
                            y: graph.plotTop + graph.plotH - (graph.plotTop + graph.plotH - modelData.y) * spectrumPage.grow
                            z: 3
                            text: modelData.name
                            color: modelData.mine ? root.accentColor : modelData.tint
                            opacity: spectrumPage.grow
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: modelData.mine ? Font.Bold : Font.DemiBold
                            style: Text.Outline
                            styleColor: "#080808"
                        }
                    }

                    // Channel axis
                    Repeater {
                        model: spectrumPage.ticks

                        Text {
                            required property var modelData
                            readonly property real f: root.band === "2.4" ? 2407 + modelData * 5 : 5000 + modelData * 5

                            x: graph.fx(f) - width / 2
                            y: graph.plotTop + graph.plotH + 6
                            text: String(modelData)
                            color: modelData === spectrumPage.best.ch ? root.accentColor : root.secondaryText
                            font.family: root.monoFamily
                            font.pixelSize: 9
                            font.weight: modelData === spectrumPage.best.ch ? Font.Bold : Font.Normal
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        visible: spectrumPage.bandAps.length === 0
                        text: root.radioOn ? "Nothing on " + root.band + " GHz" : "Wi-Fi is off"
                        color: root.secondaryText
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }

                // Band switch + verdict
                Item {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 50

                    Rectangle {
                        id: bandSwitch

                        anchors.verticalCenter: parent.verticalCenter
                        width: 150
                        height: 30
                        radius: 10
                        color: root.cardColor
                        border.width: 1
                        border.color: root.cardBorder

                        Rectangle {
                            x: root.band === "2.4" ? 3 : bandSwitch.width / 2
                            y: 3
                            width: bandSwitch.width / 2 - 3
                            height: bandSwitch.height - 6
                            radius: 7
                            color: "#1a1a1a"
                            border.width: 1
                            border.color: "#2a2a2a"

                            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1 } }
                        }

                        Row {
                            anchors.fill: parent

                            Repeater {
                                model: ["2.4", "5"]

                                Item {
                                    required property var modelData

                                    width: bandSwitch.width / 2
                                    height: bandSwitch.height

                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.band = modelData }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData + " GHz  " + root.aps.filter(a => a.band === modelData).length
                                        color: root.band === modelData ? root.primaryText : "#6a6a6a"
                                        font.family: root.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        anchors.left: bandSwitch.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: spectrumPage.bandAps.length ? "Least crowded: channel " + spectrumPage.best.ch : ""
                            color: root.accentColor
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }

                        Text {
                            width: parent.width
                            text: {
                                if (!root.link.freq || root.bandOf(root.link.freq) !== root.band)
                                    return root.band === "2.4" ? "Non-overlapping: 1 · 6 · 11" : "UNII-1 · UNII-2 (DFS) · UNII-2e · UNII-3";
                                const ch = root.channelOf(root.link.freq);
                                const sharing = spectrumPage.bandAps.filter(a => a.bssid !== (root.link.bssid || "").toUpperCase() && Math.abs(root.centerFreq(a.freq, a.width) - root.centerFreq(root.link.freq, root.activeAp ? root.activeAp.width : 20)) < ((root.activeAp ? root.activeAp.width : 20) + a.width) / 2).length;
                                return "You're on ch " + ch + ", overlapping " + sharing + " other AP" + (sharing === 1 ? "" : "s");
                            }
                            color: root.secondaryText
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }

        // Hint / toast -------------------------------------------------------------
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: root.hintHeight
            horizontalAlignment: Text.AlignHCenter
            text: root.toast !== "" ? root.toast : (root.hint !== "" ? root.hint : ({
                networks: "↑↓ select  ·  Enter open / join  ·  ←→ views  ·  Ctrl+R rescan  ·  Ctrl+D disconnect",
                connection: "Click any value to copy it  ·  ←→ views",
                spectrum: "B switches band  ·  shaded channel is the least crowded  ·  ←→ views"
            })[root.view])
            color: root.toast !== "" ? root.accentColor : root.faintText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
