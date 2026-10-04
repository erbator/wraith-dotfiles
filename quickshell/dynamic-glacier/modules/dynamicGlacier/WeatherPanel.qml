import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// Weather, from Open-Meteo (no key needed).
//   A live sky up top: the sun crosses it with the day, tonight's actual
//   moon phase, clouds, rain, snow, fog and lightning as they're forecast,
//   plus when the next rain starts or stops.
//   Hourly: a scrollable temperature curve with rain chances, a week of
//   days (click one to jump to its hours), and details: wind, sun, UV, air
//   quality and pollen, humidity, pressure.
//   Any number of saved places: just start typing a city name.
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color rainColor: "#60a5fa"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int heroHeight: 178
    readonly property int tabsHeight: 30
    readonly property int pageHeight: 262
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 10

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.heroHeight + root.tabsHeight + root.pageHeight + root.hintHeight + root.sectionSpacing * 4
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // ── State ─────────────────────────────────────────────────────────────
    // [{ name, region, country, lat, lon }]
    property var locations: [{ name: "Kecskemét", region: "Bács-Kiskun", country: "Hungary", lat: 46.90618, lon: 19.69128 }]
    property int activeIndex: 0
    readonly property var place: root.locations[Math.max(0, Math.min(root.activeIndex, root.locations.length - 1))]
    readonly property string placeKey: root.place.lat.toFixed(3) + "," + root.place.lon.toFixed(3)

    property var forecast: null
    property var air: null
    property real fetchedAt: 0
    property bool loading: false
    property string error: ""
    property bool storeLoaded: false

    property string view: "hourly" // hourly | daily | details
    readonly property var views: [
        { id: "hourly", label: "Hourly", icon: "schedule" },
        { id: "daily", label: "7 days", icon: "calendar_month" },
        { id: "details", label: "Details", icon: "dashboard" }
    ]
    readonly property int viewIndex: Math.max(0, root.views.findIndex(v => v.id === root.view))

    property real now: Date.now()
    property string hint: ""
    property string toast: ""

    // Locations drawer
    property bool drawerOpen: false
    property string query: ""
    property var results: []
    property bool searching: false
    property int drawerIndex: 0
    property var savedNow: ({}) // placeKey → { temp, code, isDay }

    readonly property int refreshIntervalMs: 15 * 60 * 1000

    // ── Weather codes ─────────────────────────────────────────────────────
    function weatherInfo(code, isDay) {
        const d = isDay !== false;
        const table = {
            0: ["Clear", d ? "sunny" : "clear_night", d ? "sun" : "night"],
            1: ["Mostly clear", d ? "partly_cloudy_day" : "partly_cloudy_night", d ? "sun" : "night"],
            2: ["Partly cloudy", d ? "partly_cloudy_day" : "partly_cloudy_night", "partly"],
            3: ["Overcast", "cloud", "cloudy"],
            45: ["Fog", "foggy", "fog"],
            48: ["Freezing fog", "foggy", "fog"],
            51: ["Light drizzle", "rainy", "drizzle"],
            53: ["Drizzle", "rainy", "drizzle"],
            55: ["Heavy drizzle", "rainy", "rain"],
            56: ["Freezing drizzle", "rainy", "drizzle"],
            57: ["Freezing drizzle", "rainy", "rain"],
            61: ["Light rain", "rainy", "drizzle"],
            63: ["Rain", "rainy", "rain"],
            65: ["Heavy rain", "rainy", "downpour"],
            66: ["Freezing rain", "rainy", "rain"],
            67: ["Freezing rain", "rainy", "downpour"],
            71: ["Light snow", "weather_snowy", "snow"],
            73: ["Snow", "weather_snowy", "snow"],
            75: ["Heavy snow", "weather_snowy", "snow"],
            77: ["Snow grains", "weather_snowy", "snow"],
            80: ["Showers", "rainy", "rain"],
            81: ["Rain showers", "rainy", "rain"],
            82: ["Violent showers", "rainy", "downpour"],
            85: ["Snow showers", "weather_snowy", "snow"],
            86: ["Snow showers", "weather_snowy", "snow"],
            95: ["Thunderstorm", "thunderstorm", "storm"],
            96: ["Storm with hail", "thunderstorm", "storm"],
            99: ["Storm with hail", "thunderstorm", "storm"]
        };
        const row = table[code] || ["Cloudy", "cloud", "cloudy"];
        return { label: row[0], icon: row[1], effect: row[2] };
    }

    function isSnowCode(code) {
        return [71, 73, 75, 77, 85, 86].indexOf(code) !== -1;
    }

    function isWetCode(code) {
        return code >= 51;
    }

    // Colour for a temperature, cold violet → blue → green → amber → red.
    readonly property var tempScale: [[-12, "#a78bfa"], [0, "#60a5fa"], [8, "#22d3ee"], [15, "#4ade80"], [21, "#facc15"], [27, "#fb923c"], [34, "#f87171"]]

    function tempColor(t) {
        const s = root.tempScale;
        if (t <= s[0][0])
            return s[0][1];
        for (let i = 1; i < s.length; i++) {
            if (t <= s[i][0]) {
                const f = (t - s[i - 1][0]) / (s[i][0] - s[i - 1][0]);
                const a = Qt.color(s[i - 1][1]);
                const b = Qt.color(s[i][1]);
                return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1);
            }
        }
        return s[s.length - 1][1];
    }

    function withAlpha(c, a) {
        const q = Qt.color(c);
        return Qt.rgba(q.r, q.g, q.b, a);
    }

    function windLabel(deg) {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(deg / 45) % 8];
    }

    function uvInfo(uv) {
        if (uv < 3)
            return { label: "Low", color: "#4ade80", tip: "no protection needed" };
        if (uv < 6)
            return { label: "Moderate", color: "#facc15", tip: "sunscreen at noon" };
        if (uv < 8)
            return { label: "High", color: "#fb923c", tip: "shade at noon" };
        if (uv < 11)
            return { label: "Very high", color: "#f87171", tip: "avoid noon sun" };
        return { label: "Extreme", color: "#c084fc", tip: "stay inside at noon" };
    }

    function aqiInfo(aqi) {
        if (aqi < 20)
            return { label: "Good", color: "#4ade80" };
        if (aqi < 40)
            return { label: "Fair", color: "#a3e635" };
        if (aqi < 60)
            return { label: "Moderate", color: "#facc15" };
        if (aqi < 80)
            return { label: "Poor", color: "#fb923c" };
        if (aqi < 100)
            return { label: "Very poor", color: "#f87171" };
        return { label: "Extremely poor", color: "#c084fc" };
    }

    // The pollen that matters most right now, against its own "high" level.
    function pollenSummary(a) {
        if (!a)
            return "";
        const kinds = [["ragweed_pollen", "Ragweed", 50], ["grass_pollen", "Grass", 50], ["birch_pollen", "Birch", 100], ["alder_pollen", "Alder", 100], ["mugwort_pollen", "Mugwort", 50], ["olive_pollen", "Olive", 100]];
        let best = null;
        for (const k of kinds) {
            const v = a[k[0]];
            if (typeof v === "number" && (best === null || v / k[2] > best.ratio))
                best = { name: k[1], ratio: v / k[2], value: v };
        }
        if (best === null)
            return "";
        if (best.value < 1)
            return "Pollen: none";
        const level = best.ratio >= 1 ? "high" : (best.ratio >= 0.2 ? "moderate" : "low");
        return best.name + " pollen " + level;
    }

    // Days since a known new moon → 0 new · 0.5 full · 1 new again.
    function moonPhase(ms) {
        const synodic = 29.530588853;
        const days = (ms - Date.UTC(2000, 0, 6, 18, 14)) / 86400000;
        return ((days % synodic) + synodic) % synodic / synodic;
    }

    function moonName(p) {
        if (p < 0.03 || p > 0.97)
            return "New moon";
        if (p < 0.22)
            return "Waxing crescent";
        if (p < 0.28)
            return "First quarter";
        if (p < 0.47)
            return "Waxing gibbous";
        if (p < 0.53)
            return "Full moon";
        if (p < 0.72)
            return "Waning gibbous";
        if (p < 0.78)
            return "Last quarter";
        return "Waning crescent";
    }

    // ── Time: every timestamp is the place's local wall time ──────────────
    readonly property int utcOffset: root.forecast ? root.forecast.utc_offset_seconds : 0

    function toMs(iso) {
        return Date.parse(iso.length === 10 ? iso + "T00:00Z" : iso + "Z") - root.utcOffset * 1000;
    }

    function hhmm(iso) {
        return iso.substr(11, 5);
    }

    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function dayName(iso) {
        return root.dayNames[new Date(Date.parse(iso.substr(0, 10) + "T00:00Z")).getUTCDay()];
    }

    function agoLabel(ms) {
        const min = Math.round((root.now - ms) / 60000);
        if (min < 1)
            return "just now";
        if (min < 60)
            return min + " min ago";
        const h = Math.floor(min / 60);
        return h < 24 ? h + " h ago" : Math.floor(h / 24) + " d ago";
    }

    function durationLabel(ms) {
        const min = Math.max(0, Math.round(ms / 60000));
        const h = Math.floor(min / 60);
        const m = min % 60;
        return h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + " min";
    }

    // ── Derived data ──────────────────────────────────────────────────────
    readonly property var cur: root.forecast ? root.forecast.current : null
    readonly property bool isDay: !root.cur || root.cur.is_day === 1
    readonly property int code: root.cur ? root.cur.weather_code : 0
    readonly property var info: root.weatherInfo(root.code, root.isDay)
    readonly property real temp: root.cur ? root.cur.temperature_2m : 0

    readonly property var daily: {
        if (!root.forecast || !root.forecast.daily)
            return [];
        const d = root.forecast.daily;
        const out = [];
        for (let i = 0; i < Math.min(7, d.time.length); i++) {
            out.push({
                iso: d.time[i],
                label: i === 0 ? "Today" : (i === 1 ? "Tomorrow" : root.dayName(d.time[i])),
                short: i === 0 ? "Today" : root.dayName(d.time[i]),
                date: String(Number(d.time[i].substr(8, 2))),
                code: d.weather_code[i],
                icon: root.weatherInfo(d.weather_code[i], true).icon,
                condition: root.weatherInfo(d.weather_code[i], true).label,
                max: d.temperature_2m_max[i],
                min: d.temperature_2m_min[i],
                pop: d.precipitation_probability_max ? (d.precipitation_probability_max[i] || 0) : 0,
                rain: d.precipitation_sum ? (d.precipitation_sum[i] || 0) : 0,
                sunrise: d.sunrise ? d.sunrise[i] : "",
                sunset: d.sunset ? d.sunset[i] : "",
                uvMax: d.uv_index_max ? (d.uv_index_max[i] || 0) : 0
            });
        }
        return out;
    }

    readonly property var today: root.daily.length ? root.daily[0] : null
    readonly property real weekMin: root.daily.length ? Math.min(...root.daily.map(d => d.min)) : 0
    readonly property real weekMax: root.daily.length ? Math.max(...root.daily.map(d => d.max)) : 1

    // Every hour from this one to the end of the week.
    readonly property var hours: {
        if (!root.forecast || !root.forecast.hourly)
            return [];
        const h = root.forecast.hourly;
        const out = [];
        const nowMs = Date.now();
        let start = 0;
        while (start < h.time.length - 1 && root.toMs(h.time[start + 1]) <= nowMs)
            start++;
        const end = Math.min(h.time.length, start + 7 * 24);
        for (let i = start; i < end; i++) {
            const iso = h.time[i];
            const hr = Number(iso.substr(11, 2));
            const dayOf = h.is_day ? h.is_day[i] === 1 : (hr >= 6 && hr < 20);
            out.push({
                iso: iso,
                now: i === start,
                hour: i === start ? "Now" : iso.substr(11, 2),
                midnight: hr === 0 && i !== start,
                day: root.dayName(iso),
                temp: h.temperature_2m[i],
                feels: h.apparent_temperature ? h.apparent_temperature[i] : h.temperature_2m[i],
                code: h.weather_code[i],
                icon: root.weatherInfo(h.weather_code[i], dayOf).icon,
                condition: root.weatherInfo(h.weather_code[i], dayOf).label,
                pop: h.precipitation_probability ? (h.precipitation_probability[i] || 0) : 0,
                rain: h.precipitation ? (h.precipitation[i] || 0) : 0,
                wind: h.wind_speed_10m ? h.wind_speed_10m[i] : 0,
                pressure: h.pressure_msl ? h.pressure_msl[i] : 0
            });
        }
        return out;
    }

    readonly property real hoursMin: root.hours.length ? Math.min(...root.hours.map(e => e.temp)) : 0
    readonly property real hoursMax: root.hours.length ? Math.max(...root.hours.map(e => e.temp)) : 1

    // Sun position through today's daylight, 0 at sunrise, 1 at sunset.
    readonly property real sunriseMs: root.today && root.today.sunrise ? root.toMs(root.today.sunrise) : 0
    readonly property real sunsetMs: root.today && root.today.sunset ? root.toMs(root.today.sunset) : 0
    readonly property real sunProgress: root.sunsetMs > root.sunriseMs ? Math.max(0, Math.min(1, (root.now - root.sunriseMs) / (root.sunsetMs - root.sunriseMs))) : 0.5
    readonly property bool goldenHour: root.isDay && root.sunsetMs > 0 && (Math.abs(root.now - root.sunriseMs) < 50 * 60000 || Math.abs(root.now - root.sunsetMs) < 50 * 60000)
    readonly property real moon: root.moonPhase(root.now)

    readonly property real pressureTrend: {
        const hs = root.hours;
        if (hs.length < 4 || !hs[0].pressure)
            return 0;
        return hs[3].pressure - hs[0].pressure;
    }

    // What the rain is about to do, from the 15-minute nowcast, then the
    // hourly chances.
    readonly property var nowcast: {
        if (!root.cur)
            return null;
        const snow = root.isSnowCode(root.code);
        const word = snow ? "Snow" : "Rain";
        const m = root.forecast.minutely_15;
        const bars = [];
        let startIdx = -1;
        let stopIdx = -1;
        if (m && m.precipitation) {
            const nowMs = Date.now();
            for (let i = 0; i < m.time.length && bars.length < 12; i++) {
                if (root.toMs(m.time[i]) + 15 * 60000 <= nowMs)
                    continue;
                bars.push(m.precipitation[i] || 0);
            }
        }
        const wetNow = (root.cur.precipitation || 0) > 0 || (bars.length && bars[0] > 0.05);
        for (let i = 0; i < bars.length; i++) {
            if (!wetNow && startIdx < 0 && bars[i] > 0.05)
                startIdx = i;
            if (wetNow && stopIdx < 0 && bars[i] <= 0.02 && (i + 1 >= bars.length || bars[i + 1] <= 0.02))
                stopIdx = i;
        }
        const peak = Math.max(0.1, ...bars);
        if (wetNow) {
            if (stopIdx > 0)
                return { icon: "umbrella", text: word + " easing off in ~" + stopIdx * 15 + " min", tint: root.rainColor, bars: bars, peak: peak };
            return { icon: "umbrella", text: word + " for at least the next " + (bars.length >= 12 ? "3 hours" : "while"), tint: root.rainColor, bars: bars, peak: peak };
        }
        if (startIdx >= 0)
            return { icon: "umbrella", text: startIdx === 0 ? word + " starting any minute" : word + " starting in ~" + startIdx * 15 + " min", tint: root.rainColor, bars: bars, peak: peak };
        for (let i = 1; i < Math.min(13, root.hours.length); i++) {
            const e = root.hours[i];
            if (e.pop >= 50)
                return { icon: "umbrella", text: (root.isSnowCode(e.code) ? "Snow" : "Rain") + " likely around " + e.iso.substr(11, 5) + " (" + e.pop + "%)", tint: root.rainColor, bars: [], peak: 1 };
        }
        if (root.daily.length > 1) {
            const diff = Math.round(root.daily[1].max - root.daily[0].max);
            const tail = diff >= 2 ? "  ·  tomorrow " + diff + "° warmer" : (diff <= -2 ? "  ·  tomorrow " + (-diff) + "° cooler" : "");
            return { icon: "check_circle", text: "Dry for the next 12 hours" + tail, tint: root.accentColor, bars: [], peak: 1 };
        }
        return { icon: "check_circle", text: "Dry for the next 12 hours", tint: root.accentColor, bars: [], peak: 1 };
    }

    // ── Fetching ──────────────────────────────────────────────────────────
    readonly property string forecastUrl: "https://api.open-meteo.com/v1/forecast?latitude=" + root.place.lat + "&longitude=" + root.place.lon
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation,is_day,uv_index,pressure_msl,cloud_cover,visibility,dew_point_2m"
        + "&minutely_15=precipitation&forecast_minutely_15=16"
        + "&hourly=temperature_2m,apparent_temperature,weather_code,is_day,precipitation_probability,precipitation,wind_speed_10m,pressure_msl"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,precipitation_sum,uv_index_max"
        + "&timezone=auto&forecast_days=8"
    readonly property string airUrl: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" + root.place.lat + "&longitude=" + root.place.lon
        + "&current=european_aqi,pm2_5,pm10,ozone,birch_pollen,grass_pollen,ragweed_pollen,alder_pollen,mugwort_pollen,olive_pollen&timezone=auto"

    function refresh() {
        root.loading = true;
        forecastProc.running = false;
        forecastProc.running = true;
        airProc.running = false;
        airProc.running = true;
    }

    function applyForecast(text, key) {
        root.loading = false;
        if (key !== root.placeKey)
            return;
        try {
            const parsed = JSON.parse(text);
            if (parsed && parsed.current && parsed.hourly && parsed.daily) {
                root.forecast = parsed;
                root.fetchedAt = Date.now();
                root.error = "";
                root.now = Date.now();
                root.saveCache();
                return;
            }
            root.error = parsed && parsed.reason ? parsed.reason : "Unexpected answer from Open-Meteo";
        } catch (e) {
            root.error = "Couldn't reach Open-Meteo";
        }
    }

    Process {
        id: forecastProc

        property string key: ""

        command: ["curl", "-s", "--max-time", "12", root.forecastUrl]
        onStarted: forecastProc.key = root.placeKey
        stdout: StdioCollector {
            onStreamFinished: root.applyForecast(text, forecastProc.key)
        }
        onExited: code => {
            if (code !== 0) {
                root.loading = false;
                root.error = "Couldn't reach Open-Meteo";
            }
        }
    }

    Process {
        id: airProc

        property string key: ""

        command: ["curl", "-s", "--max-time", "12", root.airUrl]
        onStarted: airProc.key = root.placeKey
        stdout: StdioCollector {
            onStreamFinished: {
                if (airProc.key !== root.placeKey)
                    return;
                try {
                    const parsed = JSON.parse(text);
                    if (parsed && parsed.current) {
                        root.air = parsed.current;
                        root.saveCache();
                    }
                } catch (e) {}
            }
        }
    }

    // Current conditions for every saved place, in one request.
    Process {
        id: savedProc

        property var keys: []

        command: ["curl", "-s", "--max-time", "10", "https://api.open-meteo.com/v1/forecast?latitude=" + root.locations.map(l => l.lat).join(",") + "&longitude=" + root.locations.map(l => l.lon).join(",") + "&current=temperature_2m,weather_code,is_day&timezone=auto"]
        onStarted: savedProc.keys = root.locations.map(l => l.lat.toFixed(3) + "," + l.lon.toFixed(3))
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(text);
                    if (!Array.isArray(parsed))
                        parsed = [parsed];
                    const map = {};
                    parsed.forEach((p, i) => {
                        if (p && p.current && savedProc.keys[i])
                            map[savedProc.keys[i]] = { temp: p.current.temperature_2m, code: p.current.weather_code, isDay: p.current.is_day === 1 };
                    });
                    root.savedNow = map;
                } catch (e) {}
            }
        }
    }

    Process {
        id: searchProc

        property string forQuery: ""

        command: ["curl", "-s", "--max-time", "8", "https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&format=json&name=" + encodeURIComponent(searchProc.forQuery)]
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false;
                if (searchProc.forQuery !== root.query.trim())
                    return;
                try {
                    const parsed = JSON.parse(text);
                    root.results = (parsed.results || []).map(r => ({ name: r.name, region: r.admin1 || "", country: r.country || "", lat: r.latitude, lon: r.longitude }));
                } catch (e) {
                    root.results = [];
                }
                root.drawerIndex = 0;
            }
        }
    }

    Timer {
        id: searchDebounce

        interval: 280
        onTriggered: {
            const q = root.query.trim();
            if (q.length < 2) {
                root.results = [];
                root.searching = false;
                return;
            }
            searchProc.running = false;
            searchProc.forQuery = q;
            root.searching = true;
            searchProc.running = true;
        }
    }

    onQueryChanged: {
        root.drawerIndex = 0;
        searchDebounce.restart();
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: root.storeLoaded
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.now = Date.now()
    }

    Timer {
        id: toastTimer

        interval: 2400
        onTriggered: root.toast = ""
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    // ── Places ────────────────────────────────────────────────────────────
    function selectPlace(index) {
        if (index < 0 || index >= root.locations.length)
            return;
        const changed = index !== root.activeIndex;
        root.activeIndex = index;
        root.closeDrawer();
        if (changed) {
            root.forecast = null;
            root.air = null;
            root.error = "";
            cacheFile.reload();
            root.refresh();
            root.save();
            root.playIntro();
        }
    }

    function addPlace(p) {
        const key = p.lat.toFixed(3) + "," + p.lon.toFixed(3);
        const existing = root.locations.findIndex(l => l.lat.toFixed(3) + "," + l.lon.toFixed(3) === key);
        if (existing >= 0) {
            root.selectPlace(existing);
            return;
        }
        root.locations = root.locations.concat([p]);
        root.showToast("Saved " + p.name);
        root.selectPlace(root.locations.length - 1);
    }

    function removePlace(index) {
        if (root.locations.length <= 1 || index < 0 || index >= root.locations.length)
            return;
        const name = root.locations[index].name;
        const list = root.locations.slice();
        list.splice(index, 1);
        const wasActive = index === root.activeIndex;
        root.locations = list;
        if (index < root.activeIndex || root.activeIndex >= list.length)
            root.activeIndex = Math.max(0, root.activeIndex - 1);
        root.drawerIndex = Math.min(root.drawerIndex, list.length - 1);
        root.showToast("Removed " + name);
        root.save();
        if (wasActive) {
            root.forecast = null;
            root.air = null;
            cacheFile.reload();
            root.refresh();
        }
    }

    function cyclePlace(step) {
        if (root.locations.length > 1)
            root.selectPlace((root.activeIndex + step + root.locations.length) % root.locations.length);
    }

    function openDrawer(text) {
        root.query = text || "";
        root.results = [];
        root.drawerIndex = text ? 0 : root.activeIndex;
        root.drawerOpen = true;
        if (root.locations.length > 0) {
            savedProc.running = false;
            savedProc.running = true;
        }
        searchField.forceActiveFocus();
        searchField.cursorPosition = searchField.text.length;
        if (text)
            searchDebounce.restart();
    }

    function closeDrawer() {
        root.drawerOpen = false;
        root.query = "";
        root.results = [];
        root.forceActiveFocus();
    }

    readonly property var drawerRows: root.query.trim().length >= 2 ? root.results : root.locations
    readonly property bool drawerSearching: root.query.trim().length >= 2

    function chooseDrawerRow(index) {
        const rows = root.drawerRows;
        if (index < 0 || index >= rows.length)
            return;
        if (root.drawerSearching)
            root.addPlace(rows[index]);
        else
            root.selectPlace(index);
    }

    // ── Persistence ───────────────────────────────────────────────────────
    readonly property string storePath: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/weather.json"
    readonly property string cachePath: Quickshell.env("HOME") + "/.cache/dynamic-glacier/weather.json"

    function save() {
        if (root.storeLoaded)
            saveTimer.restart();
    }

    function saveCache() {
        if (root.forecast)
            cacheTimer.restart();
    }

    function applyStore(text) {
        try {
            const data = JSON.parse(text);
            if (data && Array.isArray(data.locations)) {
                const list = data.locations.filter(l => l && typeof l.name === "string" && typeof l.lat === "number" && typeof l.lon === "number");
                if (list.length)
                    root.locations = list.map(l => ({ name: l.name, region: l.region || "", country: l.country || "", lat: l.lat, lon: l.lon }));
            }
            if (data && typeof data.active === "number")
                root.activeIndex = Math.max(0, Math.min(root.locations.length - 1, data.active));
            if (data && root.views.some(v => v.id === data.view))
                root.view = data.view;
        } catch (e) {
            // First run: the defaults above.
        }
        root.storeLoaded = true;
        cacheFile.reload();
        root.refresh();
    }

    FileView {
        id: storeFile

        path: root.storePath
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyStore(storeFile.text())
        onLoadFailed: root.applyStore("")
    }

    // The last answer, so the panel has something to show the moment it
    // opens, before the network does.
    FileView {
        id: cacheFile

        path: root.cachePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(cacheFile.text());
                if (data && data.key === root.placeKey && data.forecast && !root.forecast) {
                    root.forecast = data.forecast;
                    root.air = data.air || null;
                    root.fetchedAt = data.fetchedAt || 0;
                }
            } catch (e) {}
        }
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: storeFile.setText(JSON.stringify({ active: root.activeIndex, view: root.view, locations: root.locations }, null, 2) + "\n")
    }

    Timer {
        id: cacheTimer

        interval: 800
        onTriggered: cacheFile.setText(JSON.stringify({ key: root.placeKey, fetchedAt: root.fetchedAt, forecast: root.forecast, air: root.air }))
    }

    onViewChanged: root.save()

    // ── Opening ───────────────────────────────────────────────────────────
    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    // Sections rise in one after another; the temperature counts up.
    property real intro: 1
    property real shownTemp: 0

    NumberAnimation {
        id: introAnim

        target: root
        property: "intro"
        from: 0
        to: 1
        duration: 900
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: tempAnim

        target: root
        property: "shownTemp"
        duration: 1100
        easing.type: Easing.OutExpo
    }

    function stage(i) {
        const t = Math.max(0, Math.min(1, (root.intro - i * 0.11) / 0.55));
        return 1 - Math.pow(1 - t, 3);
    }

    function playIntro() {
        introAnim.restart();
        if (root.cur) {
            tempAnim.from = root.temp - 6;
            tempAnim.to = root.temp;
            tempAnim.restart();
        }
    }

    onTempChanged: {
        if (!root.visible) {
            root.shownTemp = root.temp;
            return;
        }
        tempAnim.from = root.shownTemp;
        tempAnim.to = root.temp;
        tempAnim.restart();
    }

    // What's typed while the island is still opening goes into the search
    // once it has settled (focusing a field mid-morph stalls the animation).
    property bool settled: false
    property string typedEarly: ""

    Timer {
        id: focusAfterOpen

        interval: 360
        onTriggered: {
            root.settled = true;
            if (root.visible && root.typedEarly !== "") {
                root.openDrawer(root.typedEarly);
                root.typedEarly = "";
            }
        }
    }

    onVisibleChanged: {
        if (root.visible) {
            root.now = Date.now();
            root.settled = false;
            root.typedEarly = "";
            root.forceActiveFocus();
            focusAfterOpen.restart();
            root.playIntro();
            hourlyList.positionViewAtBeginning();
            if (root.error !== "" || !root.forecast || Date.now() - root.fetchedAt > root.refreshIntervalMs)
                root.refresh();
        } else {
            root.drawerOpen = false;
            root.query = "";
            root.hoverHour = -1;
            root.selectedDay = -1;
        }
    }

    function setView(id) {
        root.view = id;
    }

    function stepView(step) {
        const i = (root.viewIndex + step + root.views.length) % root.views.length;
        root.view = root.views[i].id;
    }

    // Hourly ⇄ daily hand-off.
    property int hoverHour: -1
    property int selectedDay: -1

    function showDay(dayIndex) {
        const d = root.daily[dayIndex];
        if (!d)
            return;
        let idx = root.hours.findIndex(h => h.iso.substr(0, 10) === d.iso && Number(h.iso.substr(11, 2)) >= 7);
        if (idx < 0)
            idx = root.hours.findIndex(h => h.iso.substr(0, 10) === d.iso);
        root.view = "hourly";
        if (idx >= 0)
            hourlyList.glideTo(idx);
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
        } else if ((ctrl && event.key === Qt.Key_R) || event.key === Qt.Key_F5) {
            root.refresh();
        } else if (ctrl && event.key === Qt.Key_L) {
            root.openDrawer("");
        } else if (event.key === Qt.Key_PageDown || (ctrl && event.key === Qt.Key_Right)) {
            root.cyclePlace(1);
        } else if (event.key === Qt.Key_PageUp || (ctrl && event.key === Qt.Key_Left)) {
            root.cyclePlace(-1);
        } else if (event.key === Qt.Key_Right || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
            root.stepView(1);
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
            root.stepView(-1);
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
            root.setView(root.views[event.key - Qt.Key_1].id);
        } else if (root.view === "daily" && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
            const n = root.daily.length;
            root.selectedDay = root.selectedDay < 0 ? 0 : (root.selectedDay + (event.key === Qt.Key_Down ? 1 : -1) + n) % n;
        } else if (root.view === "daily" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.selectedDay >= 0) {
            root.showDay(root.selectedDay);
        } else if (root.view === "hourly" && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
            hourlyList.glideBy(event.key === Qt.Key_Down ? 6 : -6);
        } else if (event.text !== "" && (event.text === " " || event.text.toLowerCase() !== event.text.toUpperCase()) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            if (event.text === " " && !root.drawerOpen) {
                event.accepted = true;
                return;
            }
            if (root.settled)
                root.openDrawer(event.text);
            else
                root.typedEarly += event.text;
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

    // A cloud: overlapping puffs drawn as one shape, so it has a single
    // clean outline and even transparency.
    component Cloud: Shape {
        id: cloud

        property real puff: 1
        property color tint: "#ffffff"
        property color belly: "#c9d4e2"
        property real speed: 60000
        property real start: 0
        property real travel: 400
        property bool running: false

        width: 120 * cloud.puff
        height: 54 * cloud.puff
        x: cloud.start * (cloud.travel + cloud.width) - cloud.width
        preferredRendererType: Shape.CurveRenderer

        function circle(cx, cy, r) {
            const s = cloud.puff;
            cx *= s;
            cy *= s;
            r *= s;
            return "M " + (cx - r) + " " + cy + " A " + r + " " + r + " 0 1 1 " + (cx + r) + " " + cy + " A " + r + " " + r + " 0 1 1 " + (cx - r) + " " + cy + " Z ";
        }

        // Driven straight by the animation (no per-frame bindings): first
        // from where it starts to the edge, then round and round.
        SequentialAnimation {
            running: cloud.running

            NumberAnimation { target: cloud; property: "x"; from: cloud.start * (cloud.travel + cloud.width) - cloud.width; to: cloud.travel; duration: cloud.speed * (1 - cloud.start) }
            NumberAnimation { target: cloud; property: "x"; from: -cloud.width; to: cloud.travel; duration: cloud.speed; loops: Animation.Infinite }
        }

        ShapePath {
            strokeColor: "transparent"
            fillRule: ShapePath.WindingFill
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: cloud.height
                GradientStop { position: 0.2; color: cloud.tint }
                GradientStop { position: 1; color: cloud.belly }
            }

            PathSvg {
                path: cloud.circle(26, 38, 16) + cloud.circle(50, 28, 21) + cloud.circle(78, 24, 18) + cloud.circle(98, 38, 16)
                    + "M " + 26 * cloud.puff + " " + 30 * cloud.puff + " H " + 98 * cloud.puff + " V " + 54 * cloud.puff + " H " + 26 * cloud.puff + " Z"
            }
        }
    }

    component Tile: Rectangle {
        id: tile

        property string icon: ""
        property string title: ""
        property string value: ""
        property string sub: ""
        property color valueColor: root.primaryText
        default property alias viz: vizSlot.data

        radius: 14
        color: tileHover.hovered ? "#0d0d0d" : root.cardColor
        border.width: 1
        border.color: tileHover.hovered ? "#262626" : root.cardBorder

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        HoverHandler {
            id: tileHover
        }

        Row {
            x: 10
            y: 9
            spacing: 4

            MIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: tile.icon
                size: 11
                color: root.secondaryText
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.title
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 0.6
            }
        }

        Item {
            id: vizSlot

            x: 0
            y: 24
            width: tile.width
            height: tile.height - 24 - 40
        }

        Text {
            x: 10
            anchors.bottom: subText.top
            width: tile.width - 20
            text: tile.value
            color: tile.valueColor
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.features: { "tnum": 1 }
            font.pixelSize: 15
            font.weight: Font.DemiBold

            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Text {
            id: subText

            x: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: tile.width - 20
            text: tile.sub
            color: root.secondaryText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 9
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panelPadding
        spacing: root.sectionSpacing

        // Header ------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 10

            Rectangle {
                Layout.preferredWidth: root.headerHeight
                Layout.preferredHeight: root.headerHeight
                radius: width / 2
                color: "#090909"
                border.width: 1
                border.color: "#1f1f1f"

                MIcon {
                    anchors.centerIn: parent
                    name: root.cur ? root.info.icon : "cloud"
                    size: 17
                    color: root.cur ? root.tempColor(root.temp) : root.primaryText

                    Behavior on color { ColorAnimation { duration: 400 } }
                }
            }

            // The place: click (or just type) to switch.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.headerHeight

                HoverHandler {
                    id: placeHover

                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered)
                            root.hint = "Change place  ·  or just start typing a city";
                        else if (root.hint.startsWith("Change place"))
                            root.hint = "";
                    }
                }

                TapHandler {
                    onTapped: root.drawerOpen ? root.closeDrawer() : root.openDrawer("")
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 0

                    Row {
                        spacing: 3

                        Text {
                            id: placeName

                            text: root.place.name
                            color: root.primaryText
                            font.family: root.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }

                        MIcon {
                            anchors.verticalCenter: placeName.verticalCenter
                            name: "expand_more"
                            size: 16
                            color: placeHover.hovered ? root.primaryText : root.secondaryText
                            rotation: root.drawerOpen ? 180 : 0

                            Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        }

                        // Which of the saved places this is.
                        Row {
                            anchors.verticalCenter: placeName.verticalCenter
                            visible: root.locations.length > 1
                            spacing: 3
                            leftPadding: 2

                            Repeater {
                                model: root.locations.length

                                Rectangle {
                                    required property int index

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: index === root.activeIndex ? 10 : 4
                                    height: 4
                                    radius: 2
                                    color: index === root.activeIndex ? root.primaryText : "#3a3a3a"

                                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: {
                            if (root.loading && !root.forecast)
                                return "Fetching the forecast…";
                            if (root.error !== "" && root.forecast)
                                return "Offline  ·  from " + root.agoLabel(root.fetchedAt);
                            if (root.error !== "")
                                return root.error;
                            if (!root.forecast)
                                return "…";
                            const bits = [];
                            if (root.place.region || root.place.country)
                                bits.push(root.place.region || root.place.country);
                            bits.push(root.loading ? "updating…" : "updated " + root.agoLabel(root.fetchedAt));
                            return bits.join("  ·  ");
                        }
                        color: root.error !== "" ? "#fbbf24" : root.secondaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            IconButton {
                icon: "add_location_alt"
                tip: "Places  (Ctrl+L)  ·  PgUp/PgDn switches"
                onClicked: root.drawerOpen ? root.closeDrawer() : root.openDrawer("")
            }

            IconButton {
                id: refreshButton

                icon: "refresh"
                tip: "Refresh  (Ctrl+R)"
                onClicked: root.refresh()

                RotationAnimation on spin {
                    running: root.loading && root.visible
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) refreshButton.spin = 0
                }
            }

            IconButton {
                icon: "close"
                tip: "Close  (Esc)"
                onClicked: root.closeRequested()
            }
        }

        // Everything under the header; the places drawer slides over it.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.heroHeight + root.tabsHeight + root.pageHeight + root.sectionSpacing * 2

            ColumnLayout {
                anchors.fill: parent
                spacing: root.sectionSpacing
                opacity: 1 - drawer.shown * 0.85
                scale: 1 - drawer.shown * 0.03
                transformOrigin: Item.Top

                // Hero: the sky ------------------------------------------------
                Rectangle {
                    id: hero

                    readonly property bool live: root.visible && drawer.shown < 1
                    readonly property string fx: root.cur ? root.info.effect : "cloudy"
                    readonly property var sky: {
                        const day = root.isDay;
                        if (root.goldenHour && (hero.fx === "sun" || hero.fx === "partly"))
                            return ["#2c3a78", "#e98a5f"];
                        switch (hero.fx) {
                        case "sun":
                            return ["#2a66c9", "#86c2ef"];
                        case "night":
                            return ["#050a1f", "#1d2858"];
                        case "partly":
                            return day ? ["#3a6db8", "#9cc0e2"] : ["#0a1128", "#27315a"];
                        case "fog":
                            return day ? ["#6c737c", "#aab1b9"] : ["#1f2227", "#3d4148"];
                        case "snow":
                            return day ? ["#6a7f9c", "#c5d3e3"] : ["#1b2439", "#39445d"];
                        case "storm":
                            return ["#14151f", "#30314a"];
                        case "drizzle":
                        case "rain":
                        case "downpour":
                            return day ? ["#323d4c", "#5e6d80"] : ["#0c1018", "#222a37"];
                        }
                        return day ? ["#4b5f77", "#8a9db2"] : ["#131926", "#2b3345"];
                    }
                    readonly property bool dark: !root.isDay || ["storm", "rain", "downpour", "drizzle"].indexOf(hero.fx) !== -1

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.heroHeight
                    radius: 18
                    clip: true
                    opacity: root.stage(0)
                    transform: Translate { y: 14 * (1 - root.stage(0)) }

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: hero.sky[0]

                            Behavior on color { ColorAnimation { duration: 900 } }
                        }
                        GradientStop {
                            position: 1
                            color: hero.sky[1]

                            Behavior on color { ColorAnimation { duration: 900 } }
                        }
                    }

                    // Stars and the odd shooting star ------------------------
                    Item {
                        id: starField

                        readonly property bool on: hero.live && !root.isDay && ["night", "partly"].indexOf(hero.fx) !== -1

                        anchors.fill: parent
                        visible: starField.on
                        opacity: hero.fx === "partly" ? 0.55 : 1

                        Repeater {
                            model: 26

                            Rectangle {
                                required property int index

                                readonly property real seed: Math.abs(Math.sin(index * 12.9898) * 43758.5453) % 1

                                x: 8 + ((index * 97.3) % (hero.width - 16))
                                y: 6 + ((index * 53.7 + seed * 40) % (hero.height * 0.62))
                                width: seed > 0.8 ? 2.4 : 1.6
                                height: width
                                radius: width / 2
                                color: seed > 0.7 ? "#fff7d6" : "#ffffff"

                                SequentialAnimation on opacity {
                                    running: starField.on
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.15 + seed * 0.2; duration: 1100 + seed * 1600; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.95; duration: 1100 + seed * 1600; easing.type: Easing.InOutSine }
                                }
                            }
                        }

                        Rectangle {
                            id: meteor

                            width: 70
                            height: 1.5
                            radius: 1
                            rotation: 24
                            opacity: 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: "#ffffff" }
                            }
                        }

                        ParallelAnimation {
                            id: meteorAnim

                            NumberAnimation { target: meteor; property: "x"; from: 40 + Math.random() * 120; to: 200 + Math.random() * 120; duration: 700; easing.type: Easing.InQuad }
                            NumberAnimation { target: meteor; property: "y"; from: 6; to: 70; duration: 700; easing.type: Easing.InQuad }
                            SequentialAnimation {
                                NumberAnimation { target: meteor; property: "opacity"; to: 0.9; duration: 120 }
                                NumberAnimation { target: meteor; property: "opacity"; to: 0; duration: 580 }
                            }
                        }

                        Timer {
                            running: starField.on
                            repeat: true
                            interval: 7000
                            onTriggered: {
                                interval = 5000 + Math.random() * 9000;
                                meteorAnim.restart();
                            }
                        }
                    }

                    // The sun, crossing the sky as the day goes -----------------
                    Item {
                        id: sun

                        readonly property bool on: root.isDay && ["sun", "partly"].indexOf(hero.fx) !== -1

                        width: 150
                        height: 150
                        x: 250 + 110 * root.sunProgress - width / 2
                        y: 118 - 82 * Math.sin(Math.PI * root.sunProgress) - height / 2
                        visible: opacity > 0.01
                        opacity: sun.on ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: 700 } }
                        Behavior on x { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }

                        // Halo
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer

                            SequentialAnimation on scale {
                                running: hero.live && sun.on
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.1; duration: 2600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0.94; duration: 2600; easing.type: Easing.InOutSine }
                            }

                            ShapePath {
                                strokeColor: "transparent"
                                fillGradient: RadialGradient {
                                    centerX: 75
                                    centerY: 75
                                    centerRadius: 75
                                    focalX: 75
                                    focalY: 75
                                    GradientStop { position: 0; color: root.goldenHour ? "#99ffc28a" : "#80fff4c2" }
                                    GradientStop { position: 0.35; color: root.goldenHour ? "#33ff9b5e" : "#2efff1b8" }
                                    GradientStop { position: 1; color: "#00ffffff" }
                                }

                                PathAngleArc { centerX: 75; centerY: 75; radiusX: 75; radiusY: 75; startAngle: 0; sweepAngle: 360 }
                            }
                        }

                        // Rays
                        Shape {
                            anchors.centerIn: parent
                            width: 110
                            height: 110
                            opacity: 0.22
                            preferredRendererType: Shape.CurveRenderer

                            RotationAnimation on rotation {
                                running: hero.live && sun.on
                                from: 0
                                to: 360
                                duration: 90000
                                loops: Animation.Infinite
                            }

                            ShapePath {
                                strokeColor: "transparent"
                                fillColor: "#ffffff"

                                PathSvg {
                                    path: {
                                        let p = "";
                                        for (let i = 0; i < 12; i++) {
                                            const a = i * Math.PI / 6;
                                            const b = a + 0.07;
                                            const c = a - 0.07;
                                            p += "M " + (55 + Math.cos(c) * 26) + " " + (55 + Math.sin(c) * 26) + " L " + (55 + Math.cos(a) * 55) + " " + (55 + Math.sin(a) * 55) + " L " + (55 + Math.cos(b) * 26) + " " + (55 + Math.sin(b) * 26) + " Z ";
                                        }
                                        return p;
                                    }
                                }
                            }
                        }

                        // Disc
                        Shape {
                            anchors.centerIn: parent
                            width: 44
                            height: 44
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: "transparent"
                                fillGradient: RadialGradient {
                                    centerX: 18
                                    centerY: 17
                                    centerRadius: 26
                                    focalX: 18
                                    focalY: 17
                                    GradientStop { position: 0; color: "#fffdf2" }
                                    GradientStop { position: 0.6; color: root.goldenHour ? "#ffcf8a" : "#ffe9a3" }
                                    GradientStop { position: 1; color: root.goldenHour ? "#ff9d5c" : "#ffd36b" }
                                }

                                PathAngleArc { centerX: 22; centerY: 22; radiusX: 22; radiusY: 22; startAngle: 0; sweepAngle: 360 }
                            }
                        }
                    }

                    // Tonight's moon, in its real phase --------------------------
                    Item {
                        id: moonItem

                        readonly property bool on: !root.isDay && ["night", "partly"].indexOf(hero.fx) !== -1
                        readonly property real r: 17
                        readonly property real k: Math.cos(2 * Math.PI * root.moon)
                        readonly property bool waxing: root.moon < 0.5

                        x: 322
                        y: 26
                        width: 2 * moonItem.r
                        height: 2 * moonItem.r
                        visible: opacity > 0.01
                        opacity: moonItem.on ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: 700 } }

                        SequentialAnimation on y {
                            running: hero.live && moonItem.on
                            loops: Animation.Infinite
                            NumberAnimation { to: 22; duration: 4200; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 28; duration: 4200; easing.type: Easing.InOutSine }
                        }

                        Shape {
                            anchors.centerIn: parent
                            width: 110
                            height: 110
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: "transparent"
                                fillGradient: RadialGradient {
                                    centerX: 55
                                    centerY: 55
                                    centerRadius: 55
                                    focalX: 55
                                    focalY: 55
                                    GradientStop { position: 0; color: "#40e8eeff" }
                                    GradientStop { position: 0.4; color: "#14c8d4ff" }
                                    GradientStop { position: 1; color: "#00ffffff" }
                                }

                                PathAngleArc { centerX: 55; centerY: 55; radiusX: 55; radiusY: 55; startAngle: 0; sweepAngle: 360 }
                            }
                        }

                        // The dark side, faintly
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "#ffffff"
                            opacity: 0.07
                        }

                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: "transparent"
                                fillGradient: LinearGradient {
                                    x1: 0
                                    y1: 0
                                    x2: moonItem.width
                                    y2: moonItem.height
                                    GradientStop { position: 0; color: "#fffbef" }
                                    GradientStop { position: 1; color: "#d8dbe8" }
                                }

                                PathSvg {
                                    path: {
                                        const r = moonItem.r;
                                        const rx = Math.max(0.01, Math.abs(moonItem.k) * r);
                                        const limb = moonItem.waxing ? 1 : 0;
                                        const crescent = moonItem.k > 0;
                                        const term = moonItem.waxing ? (crescent ? 0 : 1) : (crescent ? 1 : 0);
                                        return "M " + r + " 0 A " + r + " " + r + " 0 0 " + limb + " " + r + " " + 2 * r + " A " + rx + " " + r + " 0 0 " + term + " " + r + " 0 Z";
                                    }
                                }
                            }
                        }

                        // A couple of craters on the lit side
                        Repeater {
                            model: [[0.62, 0.3, 4], [0.7, 0.62, 3], [0.46, 0.7, 2.4], [0.3, 0.38, 3.2]]

                            Rectangle {
                                required property var modelData

                                readonly property bool lit: moonItem.waxing ? modelData[0] > 0.5 - moonItem.k * 0.5 : modelData[0] < 0.5 + moonItem.k * 0.5

                                x: modelData[0] * moonItem.width - modelData[2]
                                y: modelData[1] * moonItem.height - modelData[2]
                                width: modelData[2] * 2
                                height: width
                                radius: width / 2
                                color: "#b9bdcc"
                                opacity: lit ? 0.45 : 0
                            }
                        }
                    }

                    // Clouds, two layers drifting at different speeds -----------
                    Item {
                        id: cloudField

                        readonly property int count: {
                            switch (hero.fx) {
                            case "sun":
                            case "night":
                                return root.cur && root.cur.cloud_cover > 15 ? 1 : 0;
                            case "partly":
                                return 3;
                            case "fog":
                                return 2;
                            }
                            return 5;
                        }
                        readonly property bool heavy: ["rain", "downpour", "storm", "drizzle", "cloudy", "snow"].indexOf(hero.fx) !== -1
                        readonly property color tint: hero.fx === "storm" ? "#5b6173" : (heavy ? (root.isDay ? "#a9b3c2" : "#4a5264") : (root.isDay ? "#ffffff" : "#5d6780"))
                        readonly property color belly: hero.fx === "storm" ? "#2c2f3d" : (heavy ? (root.isDay ? "#6c7788" : "#2c3240") : (root.isDay ? "#d7e2ef" : "#3a4258"))

                        anchors.fill: parent

                        Repeater {
                            model: [
                                { puff: 1.25, y: 6, speed: 110000, start: 0.1, alpha: 0.55 },
                                { puff: 0.95, y: 44, speed: 140000, start: 0.55, alpha: 0.5 },
                                { puff: 1.45, y: -12, speed: 80000, start: 0.72, alpha: 0.9 },
                                { puff: 1.1, y: 30, speed: 70000, start: 0.3, alpha: 0.85 },
                                { puff: 0.8, y: 70, speed: 95000, start: 0.9, alpha: 0.7 }
                            ]

                            Cloud {
                                required property var modelData
                                required property int index

                                visible: index < cloudField.count
                                puff: modelData.puff
                                y: modelData.y
                                speed: modelData.speed
                                start: modelData.start
                                travel: hero.width
                                opacity: modelData.alpha * (hero.fx === "fog" ? 0.5 : 1)
                                tint: cloudField.tint
                                belly: cloudField.belly
                                running: hero.live && visible
                            }
                        }
                    }

                    // Fog banks ----------------------------------------------------
                    Item {
                        id: fogField

                        readonly property bool on: hero.fx === "fog"

                        anchors.fill: parent
                        visible: fogField.on

                        Repeater {
                            model: 4

                            Rectangle {
                                required property int index

                                width: hero.width * 1.6
                                height: 56 + index * 10
                                y: 10 + index * 34
                                opacity: 0.2
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "#00ffffff" }
                                    GradientStop { position: 0.5; color: "#ffffff" }
                                    GradientStop { position: 1; color: "#00ffffff" }
                                }

                                SequentialAnimation on x {
                                    running: hero.live && fogField.on
                                    loops: Animation.Infinite
                                    NumberAnimation { from: -hero.width * (0.2 + index * 0.1); to: -hero.width * 0.4 + index * 12; duration: 9000 + index * 2500; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: -hero.width * (0.2 + index * 0.1); duration: 9000 + index * 2500; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }

                    // Rain: near drops are longer, faster and brighter ------------
                    Item {
                        id: rainField

                        readonly property bool on: ["drizzle", "rain", "downpour", "storm"].indexOf(hero.fx) !== -1
                        readonly property int count: hero.fx === "drizzle" ? 18 : (hero.fx === "downpour" ? 54 : 36)

                        anchors.fill: parent
                        visible: rainField.on

                        Repeater {
                            model: 54

                            Rectangle {
                                id: drop

                                required property int index

                                readonly property real seed: Math.abs(Math.sin(index * 78.233) * 43758.5453) % 1
                                readonly property bool near: index % 3 === 0
                                readonly property real fall: hero.height + 40
                                readonly property real x0: seed * (hero.width + 60) - 10
                                readonly property int period: (near ? 520 : 820) + seed * 260

                                visible: index < rainField.count
                                width: near ? 1.6 : 1.1
                                height: near ? 20 : 12
                                radius: 1
                                rotation: 14
                                opacity: near ? 0.55 : 0.3
                                x: x0
                                y: -24
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 1; color: "#d6e6ff" }
                                }

                                SequentialAnimation {
                                    running: rainField.on && hero.live && drop.visible

                                    PauseAnimation { duration: drop.seed * 900 }
                                    ParallelAnimation {
                                        loops: Animation.Infinite

                                        NumberAnimation { target: drop; property: "y"; from: -24; to: -24 + drop.fall; duration: drop.period }
                                        NumberAnimation { target: drop; property: "x"; from: drop.x0; to: drop.x0 - drop.fall * 0.25; duration: drop.period }
                                    }
                                }
                            }
                        }
                    }

                    // Lightning --------------------------------------------------------
                    Item {
                        id: stormField

                        readonly property bool on: hero.fx === "storm"

                        anchors.fill: parent
                        visible: stormField.on

                        Rectangle {
                            id: flash

                            anchors.fill: parent
                            color: "#dfe6ff"
                            opacity: 0
                        }

                        Shape {
                            id: bolt

                            x: 240
                            y: 0
                            width: 40
                            height: 110
                            opacity: 0
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: "transparent"
                                fillColor: "#fffbe0"

                                PathSvg { path: "M 22 0 L 6 52 L 18 52 L 8 110 L 36 40 L 23 40 L 32 0 Z" }
                            }
                        }

                        SequentialAnimation {
                            id: strike

                            NumberAnimation { target: flash; property: "opacity"; to: 0.5; duration: 50 }
                            NumberAnimation { target: bolt; property: "opacity"; to: 1; duration: 20 }
                            NumberAnimation { target: flash; property: "opacity"; to: 0.1; duration: 90 }
                            NumberAnimation { target: flash; property: "opacity"; to: 0.38; duration: 60 }
                            ParallelAnimation {
                                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 420; easing.type: Easing.OutQuad }
                                NumberAnimation { target: bolt; property: "opacity"; to: 0; duration: 300 }
                            }
                        }

                        Timer {
                            running: stormField.on && hero.live
                            repeat: true
                            interval: 3500
                            onTriggered: {
                                interval = 3000 + Math.random() * 6000;
                                bolt.x = 150 + Math.random() * 220;
                                bolt.scale = 0.7 + Math.random() * 0.5;
                                strike.restart();
                            }
                        }
                    }

                    // Snow: big near flakes, small far ones, all swaying ----------
                    Item {
                        id: snowField

                        readonly property bool on: hero.fx === "snow"

                        anchors.fill: parent
                        visible: snowField.on

                        Repeater {
                            model: 34

                            Rectangle {
                                id: flake

                                required property int index

                                readonly property real seed: Math.abs(Math.sin(index * 39.425) * 43758.5453) % 1
                                readonly property real size: 1.6 + seed * 3.4

                                width: size
                                height: size
                                radius: size / 2
                                color: "#ffffff"
                                opacity: 0.35 + seed * 0.55
                                x: (index * 61.7) % hero.width
                                y: -8
                                transform: Translate {
                                    SequentialAnimation on x {
                                        running: snowField.on && hero.live
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 8 + flake.seed * 8; duration: 1500 + flake.seed * 900; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: -8 - flake.seed * 8; duration: 1500 + flake.seed * 900; easing.type: Easing.InOutSine }
                                    }
                                }

                                SequentialAnimation {
                                    running: snowField.on && hero.live

                                    PauseAnimation { duration: flake.seed * 3000 }
                                    NumberAnimation { target: flake; property: "y"; from: -8; to: hero.height + 8; duration: 7000 - flake.seed * 3500; loops: Animation.Infinite }
                                }
                            }
                        }
                    }

                    // Legibility: darken behind the text a little
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#59000000" }
                            GradientStop { position: 0.6; color: "#00000000" }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: hero.radius
                        color: "transparent"
                        border.width: 1
                        border.color: "#1affffff"
                    }

                    // Readout ---------------------------------------------------------
                    Column {
                        x: 16
                        y: 12
                        spacing: 0

                        Text {
                            text: root.cur ? root.info.label : (root.error !== "" ? "No connection" : "Loading")
                            color: "#ffffff"
                            opacity: 0.92
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }

                        Row {
                            spacing: 2

                            Text {
                                id: bigTemp

                                text: root.cur ? String(Math.round(root.shownTemp)) : "--"
                                color: "#ffffff"
                                font.family: root.fontFamily
                                font.features: { "tnum": 1 }
                                font.pixelSize: 62
                                font.weight: Font.Light
                            }

                            Text {
                                y: 10
                                text: "°"
                                color: "#ffffff"
                                opacity: 0.8
                                font.family: root.fontFamily
                                font.pixelSize: 34
                                font.weight: Font.Light
                            }
                        }

                        Text {
                            visible: root.cur !== null
                            text: root.cur ? "Feels like " + Math.round(root.cur.apparent_temperature) + "°" : ""
                            color: "#ffffff"
                            opacity: 0.8
                            font.family: root.fontFamily
                            font.features: { "tnum": 1 }
                            font.pixelSize: 11
                        }

                        Row {
                            visible: root.today !== null
                            spacing: 8
                            topPadding: 2

                            Row {
                                spacing: 1

                                MIcon { name: "arrow_upward"; size: 11; color: "#ffffff"; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: root.today ? Math.round(root.today.max) + "°" : ""
                                    color: "#ffffff"
                                    font.family: root.fontFamily
                                    font.features: { "tnum": 1 }
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            Row {
                                spacing: 1

                                MIcon { name: "arrow_downward"; size: 11; color: "#ffffff"; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: root.today ? Math.round(root.today.min) + "°" : ""
                                    color: "#ffffff"
                                    opacity: 0.8
                                    font.family: root.fontFamily
                                    font.features: { "tnum": 1 }
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    // Retry, when there's nothing to show
                    Rectangle {
                        visible: !root.cur && root.error !== "" && !root.loading
                        anchors.centerIn: parent
                        width: retryRow.implicitWidth + 24
                        height: 30
                        radius: 15
                        color: retryHover.hovered ? "#40ffffff" : "#26ffffff"

                        HoverHandler { id: retryHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.refresh() }

                        Row {
                            id: retryRow

                            anchors.centerIn: parent
                            spacing: 6

                            MIcon { name: "refresh"; size: 14; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Try again"
                                color: "#ffffff"
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }
                    }

                    // The next few hours of rain -------------------------------------
                    Rectangle {
                        id: nowcastBar

                        visible: root.nowcast !== null
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        height: 30
                        radius: 11
                        color: "#47000000"
                        border.width: 1
                        border.color: "#14ffffff"

                        MIcon {
                            id: nowcastIcon

                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.nowcast ? root.nowcast.icon : ""
                            size: 14
                            color: root.nowcast ? root.nowcast.tint : "white"
                        }

                        Text {
                            anchors.left: nowcastIcon.right
                            anchors.leftMargin: 6
                            anchors.right: sparkline.visible ? sparkline.left : parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.nowcast ? root.nowcast.text : ""
                            color: "#ffffff"
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        // 3 hours, in 15-minute bars
                        Row {
                            id: sparkline

                            visible: root.nowcast !== null && root.nowcast.bars.length > 0 && Math.max(...root.nowcast.bars) > 0
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: 16
                            spacing: 2

                            Repeater {
                                model: root.nowcast ? root.nowcast.bars : []

                                Rectangle {
                                    required property var modelData
                                    required property int index

                                    anchors.bottom: parent.bottom
                                    width: 4
                                    radius: 2
                                    height: Math.max(2, 16 * Math.min(1, modelData / root.nowcast.peak) * root.stage(1.5 + index * 0.08))
                                    color: modelData > 0.02 ? root.rainColor : "#40ffffff"
                                }
                            }
                        }
                    }
                }

                // Tabs ---------------------------------------------------------------
                Rectangle {
                    id: tabs

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tabsHeight
                    radius: 11
                    color: root.cardColor
                    border.width: 1
                    border.color: root.cardBorder
                    opacity: root.stage(1)
                    transform: Translate { y: 12 * (1 - root.stage(1)) }

                    readonly property real segment: (tabs.width - 6) / root.views.length

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
                                TapHandler { onTapped: root.setView(tab.modelData.id) }

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

                // Pages ----------------------------------------------------------------
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

                    // ── Hourly ─────────────────────────────────────────────────
                    Item {
                        id: hourlyPage

                        readonly property int colW: 46
                        readonly property real curveTop: 60
                        readonly property real curveBottom: 146
                        readonly property int barBase: 180
                        readonly property int focusIndex: root.hoverHour >= 0 ? root.hoverHour : 0

                        function tempY(t) {
                            const span = Math.max(1, root.hoursMax - root.hoursMin);
                            return hourlyPage.curveBottom - (t - root.hoursMin) / span * (hourlyPage.curveBottom - hourlyPage.curveTop);
                        }

                        x: pages.pageX(0)
                        width: pages.width
                        height: pages.height
                        opacity: pages.pageOpacity(0)
                        visible: opacity > 0

                        Rectangle {
                            id: chartCard

                            width: parent.width
                            height: 204
                            radius: 14
                            color: root.cardColor
                            border.width: 1
                            border.color: root.cardBorder
                            clip: true

                            // The curve, drawn behind the list and moved with its scroll
                            // position (originX included: ListView shifts it when the
                            // model is replaced, so content x 0 isn't always hour 0).
                            Item {
                                readonly property real scrolled: hourlyList.contentX - hourlyList.originX

                                x: 1 - scrolled
                                y: 1
                                height: hourlyList.height
                                width: hourlyList.reveal < 1 ? scrolled + hourlyList.width * hourlyList.reveal : hourlyList.contentWidth
                                clip: true

                                Shape {
                                    id: curve

                                    readonly property var pts: root.hours.map((e, i) => [i * hourlyPage.colW + hourlyPage.colW / 2, hourlyPage.tempY(e.temp)])
                                    readonly property string line: {
                                        const p = curve.pts;
                                        if (p.length < 2)
                                            return "M 0 0";
                                        let d = "M " + p[0][0] + " " + p[0][1];
                                        for (let i = 0; i < p.length - 1; i++) {
                                            const p0 = p[Math.max(0, i - 1)];
                                            const p1 = p[i];
                                            const p2 = p[i + 1];
                                            const p3 = p[Math.min(p.length - 1, i + 2)];
                                            d += " C " + (p1[0] + (p2[0] - p0[0]) / 6) + " " + (p1[1] + (p2[1] - p0[1]) / 6) + " " + (p2[0] - (p3[0] - p1[0]) / 6) + " " + (p2[1] - (p3[1] - p1[1]) / 6) + " " + p2[0] + " " + p2[1];
                                        }
                                        return d;
                                    }
                                    readonly property color hot: root.tempColor(root.hoursMax)
                                    readonly property color cold: root.tempColor(root.hoursMin)

                                    width: hourlyList.contentWidth
                                    height: hourlyList.height
                                    preferredRendererType: Shape.CurveRenderer

                                    ShapePath {
                                        strokeColor: "transparent"
                                        fillGradient: LinearGradient {
                                            x1: 0
                                            y1: hourlyPage.curveTop
                                            x2: 0
                                            y2: hourlyPage.barBase - 24
                                            GradientStop { position: 0; color: root.withAlpha(curve.hot, 0.2) }
                                            GradientStop { position: 1; color: root.withAlpha(curve.cold, 0) }
                                        }

                                        PathSvg {
                                            path: curve.pts.length < 2 ? "M 0 0" : curve.line + " L " + curve.pts[curve.pts.length - 1][0] + " " + (hourlyPage.barBase - 24) + " L " + curve.pts[0][0] + " " + (hourlyPage.barBase - 24) + " Z"
                                        }
                                    }

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeWidth: 2.2
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin
                                        strokeColor: curve.hot

                                        PathSvg { path: curve.line }
                                    }
                                }
                            }

                            ListView {
                                id: hourlyList

                                // Draws itself in, left to right, when the panel opens.
                                property real reveal: 1

                                function glideTo(index) {
                                    glide.to = originX + Math.max(0, Math.min(contentWidth - width, index * hourlyPage.colW - 4));
                                    glide.restart();
                                }

                                function glideBy(n) {
                                    glide.to = originX + Math.max(0, Math.min(contentWidth - width, contentX - originX + n * hourlyPage.colW));
                                    glide.restart();
                                }

                                anchors.fill: parent
                                anchors.margins: 1
                                orientation: ListView.Horizontal
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.hours
                                cacheBuffer: 200
                                flickDeceleration: 2400

                                NumberAnimation {
                                    id: glide

                                    target: hourlyList
                                    property: "contentX"
                                    duration: 560
                                    easing.type: Easing.OutCubic
                                }

                                NumberAnimation on reveal {
                                    id: revealAnim

                                    running: false
                                    from: 0
                                    to: 1
                                    duration: 1000
                                    easing.type: Easing.OutCubic
                                }

                                Connections {
                                    target: root

                                    function onVisibleChanged() {
                                        if (root.visible)
                                            revealAnim.restart();
                                    }

                                    function onForecastChanged() {
                                        hourlyList.positionViewAtBeginning();
                                        if (root.visible)
                                            revealAnim.restart();
                                    }
                                }

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse
                                    onWheel: event => hourlyList.glideBy(event.angleDelta.y > 0 ? -3 : 3)
                                }

                                delegate: Item {
                                    id: hourCell

                                    required property var modelData
                                    required property int index
                                    readonly property bool focused: hourlyPage.focusIndex === index
                                    readonly property real py: hourlyPage.tempY(modelData.temp)

                                    width: hourlyPage.colW
                                    height: hourlyList.height

                                    HoverHandler {
                                        onHoveredChanged: {
                                            if (hovered)
                                                root.hoverHour = hourCell.index;
                                            else if (root.hoverHour === hourCell.index)
                                                root.hoverHour = -1;
                                        }
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 4
                                        width: hourlyPage.colW - 6
                                        height: parent.height - 8
                                        radius: 10
                                        color: "#ffffff"
                                        opacity: hourCell.focused ? 0.05 : 0

                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }

                                    // A new day starts here
                                    Rectangle {
                                        visible: hourCell.modelData.midnight
                                        x: 0
                                        y: 10
                                        width: 1
                                        height: parent.height - 20
                                        color: "#262626"
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 10
                                        text: hourCell.modelData.midnight ? hourCell.modelData.day : hourCell.modelData.hour
                                        color: hourCell.modelData.now ? root.accentColor : (hourCell.modelData.midnight ? root.primaryText : (hourCell.focused ? "#cfcfcf" : root.secondaryText))
                                        font.family: root.fontFamily
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: 10
                                        font.weight: hourCell.modelData.now || hourCell.modelData.midnight ? Font.Bold : Font.DemiBold
                                    }

                                    MIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 26
                                        name: hourCell.modelData.icon
                                        size: 17
                                        color: root.primaryText
                                        scale: hourCell.focused ? 1.15 : 1

                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: hourCell.py - 19
                                        text: Math.round(hourCell.modelData.temp) + "°"
                                        color: hourCell.focused ? root.tempColor(hourCell.modelData.temp) : root.primaryText
                                        font.family: root.fontFamily
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: 11
                                        font.weight: Font.Bold

                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: hourCell.py - height / 2
                                        width: hourCell.focused ? 9 : 5
                                        height: width
                                        radius: width / 2
                                        color: hourCell.focused ? root.tempColor(hourCell.modelData.temp) : "#0b0b0b"
                                        border.width: 1.5
                                        border.color: root.tempColor(hourCell.modelData.temp)
                                        opacity: hourCell.focused || hourCell.modelData.now ? 1 : 0

                                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                    }

                                    // Chance of rain
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: hourlyPage.barBase - 20
                                        width: 12
                                        height: 20
                                        radius: 4
                                        color: hourCell.modelData.pop > 0 ? "#111111" : "#0c0c0c"

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.max(0, parent.height * hourCell.modelData.pop / 100 * root.stage(2.5))
                                            radius: 4
                                            color: root.rainColor
                                            opacity: 0.35 + hourCell.modelData.pop / 160
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: hourlyPage.barBase + 4
                                        text: hourCell.modelData.pop > 0 ? hourCell.modelData.pop + "%" : ""
                                        color: hourCell.modelData.pop >= 40 ? root.rainColor : "#555555"
                                        font.family: root.fontFamily
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            // Soft fade at both ends
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 1
                                width: 18
                                radius: 14
                                visible: hourlyList.contentX - hourlyList.originX > 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: root.cardColor }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 1
                                width: 24
                                radius: 14
                                visible: hourlyList.contentX - hourlyList.originX < hourlyList.contentWidth - hourlyList.width - 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 1; color: root.cardColor }
                                }
                            }

                            // Back to now
                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                radius: 12
                                color: nowHover.hovered ? "#2a2a2a" : "#1a1a1a"
                                border.width: 1
                                border.color: "#333333"
                                opacity: hourlyList.contentX - hourlyList.originX > hourlyPage.colW * 6 ? 1 : 0
                                visible: opacity > 0
                                scale: opacity

                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                HoverHandler { id: nowHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: hourlyList.glideTo(0) }

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "first_page"
                                    size: 14
                                    color: root.primaryText
                                }
                            }
                        }

                        // The hour under the pointer, in full
                        Rectangle {
                            id: hourDetail

                            readonly property var e: root.hours.length ? root.hours[Math.min(hourlyPage.focusIndex, root.hours.length - 1)] : null

                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 48
                            radius: 14
                            color: root.cardColor
                            border.width: 1
                            border.color: root.cardBorder

                            Rectangle {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 10
                                color: hourDetail.e ? root.withAlpha(root.tempColor(hourDetail.e.temp), 0.13) : "transparent"

                                Behavior on color { ColorAnimation { duration: 250 } }

                                MIcon {
                                    anchors.centerIn: parent
                                    name: hourDetail.e ? hourDetail.e.icon : ""
                                    size: 18
                                    color: hourDetail.e ? root.tempColor(hourDetail.e.temp) : "white"
                                }
                            }

                            Column {
                                x: 50
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: hourDetail.e ? (hourDetail.e.now ? "Now" : hourDetail.e.day + " " + hourDetail.e.iso.substr(11, 5)) + "  ·  " + hourDetail.e.condition : ""
                                    color: root.primaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                Text {
                                    text: hourDetail.e ? Math.round(hourDetail.e.temp) + "°, feels " + Math.round(hourDetail.e.feels) + "°" : ""
                                    color: root.secondaryText
                                    font.family: root.fontFamily
                                    font.features: { "tnum": 1 }
                                    font.pixelSize: 10
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                Repeater {
                                    model: hourDetail.e ? [
                                        { icon: "water_drop", text: hourDetail.e.pop + "%", tint: hourDetail.e.pop >= 40 ? root.rainColor : "#9a9a9a" },
                                        { icon: "umbrella", text: hourDetail.e.rain.toFixed(1) + " mm", tint: hourDetail.e.rain > 0 ? root.rainColor : "#9a9a9a" },
                                        { icon: "air", text: Math.round(hourDetail.e.wind) + " km/h", tint: "#9a9a9a" }
                                    ] : []

                                    Row {
                                        required property var modelData

                                        spacing: 3

                                        MIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: modelData.icon
                                            size: 12
                                            color: modelData.tint
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.text
                                            color: root.primaryText
                                            font.family: root.fontFamily
                                            font.features: { "tnum": 1 }
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── 7 days ─────────────────────────────────────────────────
                    Item {
                        id: dailyPage

                        x: pages.pageX(1)
                        width: pages.width
                        height: pages.height
                        opacity: pages.pageOpacity(1)
                        visible: opacity > 0

                        // Rows arrive one by one each time the page is shown.
                        property real arrive: 1

                        NumberAnimation on arrive {
                            id: arriveAnim

                            running: false
                            from: 0
                            to: 1
                            duration: 700
                        }

                        Connections {
                            target: root

                            function onViewChanged() {
                                if (root.view === "daily")
                                    arriveAnim.restart();
                            }
                        }

                        Column {
                            anchors.fill: parent
                            spacing: 4

                            Repeater {
                                model: root.daily

                                Rectangle {
                                    id: dayRow

                                    required property var modelData
                                    required property int index
                                    readonly property bool lit: dayHover.hovered || root.selectedDay === index
                                    readonly property real t: Math.max(0, Math.min(1, (dailyPage.arrive * 1.6 - index * 0.09) / 0.6))
                                    readonly property real span: Math.max(1, root.weekMax - root.weekMin)

                                    width: dailyPage.width
                                    height: (dailyPage.height - 6 * 4) / 7
                                    radius: 11
                                    color: dayRow.lit ? "#111111" : root.cardColor
                                    border.width: 1
                                    border.color: dayRow.lit ? "#2a2a2a" : root.cardBorder
                                    opacity: dayRow.t
                                    transform: Translate { x: 18 * (1 - dayRow.t) }

                                    Behavior on color { ColorAnimation { duration: 140 } }

                                    HoverHandler {
                                        id: dayHover

                                        cursorShape: Qt.PointingHandCursor
                                        onHoveredChanged: {
                                            if (hovered)
                                                root.hint = dayRow.modelData.label + ": " + dayRow.modelData.condition + (dayRow.modelData.rain > 0 ? ", " + dayRow.modelData.rain.toFixed(1) + " mm" : "") + "  ·  click for its hours";
                                            else if (root.hint.startsWith(dayRow.modelData.label + ":"))
                                                root.hint = "";
                                        }
                                    }

                                    TapHandler { onTapped: root.showDay(dayRow.index) }

                                    Row {
                                        x: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Text {
                                            width: 38
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: dayRow.modelData.short
                                            color: dayRow.index === 0 ? root.accentColor : root.primaryText
                                            font.family: root.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                        }

                                        Text {
                                            width: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: dayRow.index === 0 ? "" : dayRow.modelData.date
                                            color: root.faintText
                                            font.family: root.fontFamily
                                            font.features: { "tnum": 1 }
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    MIcon {
                                        x: 84
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: dayRow.modelData.icon
                                        size: 18
                                        color: root.primaryText
                                        scale: dayRow.lit ? 1.15 : 1

                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                    }

                                    Text {
                                        x: 108
                                        width: 34
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: dayRow.modelData.pop >= 10 ? dayRow.modelData.pop + "%" : ""
                                        color: root.rainColor
                                        font.family: root.fontFamily
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        x: 144
                                        width: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: Math.round(dayRow.modelData.min) + "°"
                                        color: root.secondaryText
                                        font.family: root.fontFamily
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    // The day's range, on the week's scale
                                    Item {
                                        id: range

                                        x: 180
                                        width: dayRow.width - 180 - 46
                                        height: 6
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 3
                                            color: "#181818"
                                        }

                                        Rectangle {
                                            readonly property real a: (dayRow.modelData.min - root.weekMin) / dayRow.span
                                            readonly property real b: (dayRow.modelData.max - root.weekMin) / dayRow.span

                                            x: a * range.width
                                            width: Math.max(6, (b - a) * range.width * dayRow.t)
                                            height: parent.height
                                            radius: 3
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0; color: root.tempColor(dayRow.modelData.min) }
                                                GradientStop { position: 1; color: root.tempColor(dayRow.modelData.max) }
                                            }
                                        }

                                        // Where it is right now
                                        Rectangle {
                                            visible: dayRow.index === 0 && root.cur !== null
                                            x: Math.max(0, Math.min(1, (root.temp - root.weekMin) / dayRow.span)) * range.width - width / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: "#ffffff"
                                            border.width: 2
                                            border.color: "#0b0b0b"
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        width: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: Math.round(dayRow.modelData.max) + "°"
                                        color: root.primaryText
                                        font.family: root.fontFamily
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }

                    // ── Details ────────────────────────────────────────────────
                    Item {
                        id: detailsPage

                        readonly property real tileW: (width - 16) / 3
                        readonly property real tileH: (height - 8) / 2
                        readonly property bool live: root.visible && pages.pageOpacity(2) > 0

                        property real grow: 1

                        NumberAnimation on grow {
                            id: growAnim

                            running: false
                            from: 0
                            to: 1
                            duration: 1100
                            easing.type: Easing.OutCubic
                        }

                        Connections {
                            target: root

                            function onViewChanged() {
                                if (root.view === "details")
                                    growAnim.restart();
                            }
                        }

                        x: pages.pageX(2)
                        width: pages.width
                        height: pages.height
                        opacity: pages.pageOpacity(2)
                        visible: opacity > 0

                        Grid {
                            columns: 3
                            spacing: 8

                            // Wind: a compass whose needle leans with the gusts.
                            Tile {
                                width: detailsPage.tileW
                                height: detailsPage.tileH
                                icon: "air"
                                title: "WIND"
                                value: root.cur ? Math.round(root.cur.wind_speed_10m) + " km/h" : "—"
                                sub: root.cur ? "Gusts " + Math.round(root.cur.wind_gusts_10m) + "  ·  from " + root.windLabel(root.cur.wind_direction_10m) : ""

                                Item {
                                    anchors.centerIn: parent
                                    width: 58
                                    height: 58

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: "#262626"
                                    }

                                    Repeater {
                                        model: 24

                                        Rectangle {
                                            required property int index

                                            x: 29 - width / 2
                                            y: 2
                                            width: 1
                                            height: index % 6 === 0 ? 5 : 3
                                            color: index % 6 === 0 ? "#5a5a5a" : "#303030"
                                            transform: Rotation { origin.x: 0.5; origin.y: 27; angle: index * 15 }
                                        }
                                    }

                                    Repeater {
                                        model: [["N", 29, 12], ["E", 46, 29], ["S", 29, 46], ["W", 12, 29]]

                                        Text {
                                            required property var modelData

                                            x: modelData[1] - width / 2
                                            y: modelData[2] - height / 2
                                            text: modelData[0]
                                            color: modelData[0] === "N" ? "#9a9a9a" : "#4a4a4a"
                                            font.family: root.fontFamily
                                            font.pixelSize: 7
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Item {
                                        id: needle

                                        property real wobble: 0

                                        anchors.fill: parent
                                        // Points where the wind blows to.
                                        rotation: (root.cur ? root.cur.wind_direction_10m + 180 : 0) * detailsPage.grow + wobble

                                        SequentialAnimation on wobble {
                                            running: detailsPage.live
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 5; duration: 900; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: -3; duration: 1300; easing.type: Easing.InOutSine }
                                        }

                                        Shape {
                                            anchors.fill: parent
                                            preferredRendererType: Shape.CurveRenderer

                                            ShapePath {
                                                strokeColor: "transparent"
                                                fillColor: "#e8e8e8"

                                                PathSvg { path: "M 29 9 L 34 24 L 29 21 L 24 24 Z" }
                                            }

                                            ShapePath {
                                                strokeColor: "transparent"
                                                fillColor: "#3a3a3a"

                                                PathSvg { path: "M 29 49 L 32 36 L 29 38 L 26 36 Z" }
                                            }
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 7
                                            height: 7
                                            radius: 3.5
                                            color: "#0b0b0b"
                                            border.width: 1.5
                                            border.color: "#e8e8e8"
                                        }
                                    }
                                }
                            }

                            // Sun: today's arc and where it is on it.
                            Tile {
                                width: detailsPage.tileW
                                height: detailsPage.tileH
                                icon: root.isDay ? "wb_twilight" : "bedtime"
                                title: root.isDay ? "SUN" : "NIGHT"
                                value: root.today ? (root.isDay ? "↓ " + root.hhmm(root.today.sunset) : "↑ " + (root.daily.length > 1 && root.now > root.sunsetMs ? root.hhmm(root.daily[1].sunrise) : root.hhmm(root.today.sunrise))) : "—"
                                sub: {
                                    if (!root.today)
                                        return "";
                                    if (root.isDay)
                                        return root.durationLabel(root.sunsetMs - root.now) + " of daylight left";
                                    return root.moonName(root.moon) + "  ·  " + Math.round((1 - Math.cos(2 * Math.PI * root.moon)) * 50) + "% lit";
                                }

                                Shape {
                                    id: sunArc

                                    readonly property real cx: width / 2
                                    readonly property real base: height - 8
                                    readonly property real rx: width / 2 - 16
                                    readonly property real ry: height - 16
                                    readonly property real p: root.isDay ? root.sunProgress * detailsPage.grow : 0

                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer

                                    ShapePath {
                                        strokeColor: "#2a2a2a"
                                        strokeWidth: 1
                                        fillColor: "transparent"

                                        PathMove { x: 8; y: sunArc.base }
                                        PathLine { x: sunArc.width - 8; y: sunArc.base }
                                    }

                                    ShapePath {
                                        strokeColor: "#3a3a3a"
                                        strokeWidth: 1.5
                                        strokeStyle: ShapePath.DashLine
                                        dashPattern: [2, 3]
                                        fillColor: "transparent"

                                        PathAngleArc { centerX: sunArc.cx; centerY: sunArc.base; radiusX: sunArc.rx; radiusY: sunArc.ry; startAngle: 180; sweepAngle: 180 }
                                    }

                                    ShapePath {
                                        strokeColor: "#fbbf24"
                                        strokeWidth: 2
                                        capStyle: ShapePath.RoundCap
                                        fillColor: "transparent"

                                        PathAngleArc { centerX: sunArc.cx; centerY: sunArc.base; radiusX: sunArc.rx; radiusY: sunArc.ry; startAngle: 180; sweepAngle: 180 * Math.max(0.001, sunArc.p) }
                                    }

                                    Rectangle {
                                        visible: root.isDay
                                        x: sunArc.cx - sunArc.rx * Math.cos(Math.PI * sunArc.p) - width / 2
                                        y: sunArc.base - sunArc.ry * Math.sin(Math.PI * sunArc.p) - height / 2
                                        width: 12
                                        height: 12
                                        radius: 6
                                        color: "#fde68a"
                                        border.width: 2
                                        border.color: "#fbbf24"

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: "#fbbf24"
                                            opacity: 0.18
                                            z: -1
                                        }
                                    }
                                }
                            }

                            // UV: where today sits on the scale.
                            Tile {
                                id: uvTile

                                readonly property real uv: root.cur ? root.cur.uv_index : 0
                                readonly property var uvi: root.uvInfo(uv)

                                width: detailsPage.tileW
                                height: detailsPage.tileH
                                icon: "wb_sunny"
                                title: "UV INDEX"
                                value: root.cur ? Math.round(uv) + "  " + uvi.label : "—"
                                valueColor: root.cur ? uvi.color : root.primaryText
                                sub: root.today ? "Max " + root.today.uvMax.toFixed(1) + " · " + root.uvInfo(root.today.uvMax).tip : ""

                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 12
                                    width: parent.width - 24
                                    height: 8

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 4
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: "#4ade80" }
                                            GradientStop { position: 0.27; color: "#facc15" }
                                            GradientStop { position: 0.55; color: "#fb923c" }
                                            GradientStop { position: 0.8; color: "#f87171" }
                                            GradientStop { position: 1; color: "#c084fc" }
                                        }
                                    }

                                    Rectangle {
                                        x: Math.min(1, uvTile.uv / 11) * parent.width * detailsPage.grow - width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 14
                                        height: 14
                                        radius: 7
                                        color: "#ffffff"
                                        border.width: 3
                                        border.color: "#0b0b0b"
                                    }
                                }
                            }

                            // Air: the European AQI on a ring, plus pollen.
                            Tile {
                                id: aqiTile

                                readonly property real aqi: root.air && typeof root.air.european_aqi === "number" ? root.air.european_aqi : -1
                                readonly property var aq: root.aqiInfo(Math.max(0, aqi))

                                width: detailsPage.tileW
                                height: detailsPage.tileH
                                icon: "eco"
                                title: "AIR QUALITY"
                                value: aqi >= 0 ? aq.label : "—"
                                valueColor: aqi >= 0 ? aq.color : root.primaryText
                                sub: aqi >= 0 ? root.pollenSummary(root.air) : "No data here"

                                Shape {
                                    id: aqiRing

                                    anchors.centerIn: parent
                                    width: 54
                                    height: 54
                                    preferredRendererType: Shape.CurveRenderer

                                    ShapePath {
                                        strokeColor: "#1f1f1f"
                                        strokeWidth: 5
                                        capStyle: ShapePath.RoundCap
                                        fillColor: "transparent"

                                        PathAngleArc { centerX: 27; centerY: 27; radiusX: 24; radiusY: 24; startAngle: 135; sweepAngle: 270 }
                                    }

                                    ShapePath {
                                        strokeColor: aqiTile.aqi >= 0 ? aqiTile.aq.color : "transparent"
                                        strokeWidth: 5
                                        capStyle: ShapePath.RoundCap
                                        fillColor: "transparent"

                                        PathAngleArc { centerX: 27; centerY: 27; radiusX: 24; radiusY: 24; startAngle: 135; sweepAngle: Math.max(1, 270 * Math.min(1, aqiTile.aqi / 100) * detailsPage.grow) }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: aqiTile.aqi >= 0 ? Math.round(aqiTile.aqi * detailsPage.grow) : "–"
                                        color: root.primaryText
                                        font.family: root.fontFamily
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            // Humidity: a little tank with a moving surface.
                            Tile {
                                id: humidityTile

                                readonly property real rh: root.cur ? root.cur.relative_humidity_2m : 0

                                width: detailsPage.tileW
                                height: detailsPage.tileH
                                icon: "water_drop"
                                title: "HUMIDITY"
                                value: root.cur ? Math.round(rh) + "%" : "—"
                                sub: root.cur ? "Dew point " + Math.round(root.cur.dew_point_2m) + "°" + (root.cur.dew_point_2m >= 18 ? "  ·  muggy" : (root.cur.dew_point_2m <= 0 ? "  ·  dry" : "")) : ""

                                Rectangle {
                                    id: tank

                                    anchors.centerIn: parent
                                    width: 46
                                    height: 52
                                    radius: 14
                                    color: "#0e0e0e"
                                    border.width: 1
                                    border.color: "#262626"
                                    clip: true

                                    Shape {
                                        id: wave

                                        readonly property real level: tank.height * (1 - humidityTile.rh / 100 * detailsPage.grow)

                                        x: 0
                                        y: wave.level - 4
                                        width: 92
                                        height: tank.height + 8
                                        preferredRendererType: Shape.CurveRenderer

                                        NumberAnimation on x {
                                            running: detailsPage.live
                                            from: 0
                                            to: -46
                                            duration: 2400
                                            loops: Animation.Infinite
                                        }

                                        ShapePath {
                                            strokeColor: "transparent"
                                            fillGradient: LinearGradient {
                                                x1: 0
                                                y1: 0
                                                x2: 0
                                                y2: 60
                                                GradientStop { position: 0; color: "#7dd3fc" }
                                                GradientStop { position: 1; color: "#2563eb" }
                                            }

                                            PathSvg { path: "M 0 4 Q 11.5 0 23 4 T 46 4 T 69 4 T 92 4 L 92 70 L 0 70 Z" }
                                        }
                                    }
                                }
                            }

                            // Pressure: a gauge, and which way it's heading.
                            Tile {
                                id: pressureTile

                                readonly property real hpa: root.cur ? root.cur.pressure_msl : 1013

                                width: detailsPage.tileW
                                height: detailsPage.tileH
                                icon: "speed"
                                title: "PRESSURE"
                                value: root.cur ? Math.round(hpa) + " hPa" : "—"
                                sub: {
                                    if (!root.cur)
                                        return "";
                                    const t = root.pressureTrend;
                                    const trend = t > 1 ? "Rising" : (t < -1 ? "Falling" : "Steady");
                                    return trend + "  ·  " + (root.cur.visibility >= 1000 ? Math.round(root.cur.visibility / 1000) + " km" : Math.round(root.cur.visibility) + " m") + " visibility";
                                }

                                Item {
                                    id: gauge

                                    readonly property real f: Math.max(0, Math.min(1, (pressureTile.hpa - 980) / 65))

                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    width: 70
                                    height: 40

                                    Shape {
                                        anchors.fill: parent
                                        preferredRendererType: Shape.CurveRenderer

                                        ShapePath {
                                            strokeWidth: 5
                                            capStyle: ShapePath.RoundCap
                                            fillColor: "transparent"
                                            strokeColor: "#1f1f1f"

                                            PathAngleArc { centerX: 35; centerY: 36; radiusX: 30; radiusY: 30; startAngle: 180; sweepAngle: 180 }
                                        }

                                        ShapePath {
                                            strokeWidth: 5
                                            capStyle: ShapePath.RoundCap
                                            fillColor: "transparent"
                                            strokeColor: "#a78bfa"

                                            PathAngleArc { centerX: 35; centerY: 36; radiusX: 30; radiusY: 30; startAngle: 180; sweepAngle: Math.max(1, 180 * gauge.f * detailsPage.grow) }
                                        }
                                    }

                                    Rectangle {
                                        x: 35 - width / 2
                                        y: 36 - height + 2
                                        width: 2
                                        height: 22
                                        radius: 1
                                        color: "#e8e8e8"
                                        transformOrigin: Item.Bottom
                                        rotation: -90 + 180 * gauge.f * detailsPage.grow
                                    }

                                    Rectangle {
                                        x: 35 - 4
                                        y: 36 - 4
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: "#e8e8e8"
                                    }

                                    MIcon {
                                        anchors.right: parent.right
                                        anchors.rightMargin: -14
                                        y: 22
                                        name: root.pressureTrend > 1 ? "trending_up" : (root.pressureTrend < -1 ? "trending_down" : "trending_flat")
                                        size: 13
                                        color: root.pressureTrend > 1 ? root.accentColor : (root.pressureTrend < -1 ? "#fbbf24" : "#5a5a5a")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Places drawer ─────────────────────────────────────────────
            Rectangle {
                id: drawer

                property real shown: root.drawerOpen ? 1 : 0

                Behavior on shown { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height
                radius: 18
                color: "#f2070707"
                border.width: 1
                border.color: "#232323"
                visible: drawer.shown > 0.001
                opacity: drawer.shown
                transform: Translate { y: -16 * (1 - drawer.shown) }

                // Clicks don't fall through to the pages underneath.
                MouseArea {
                    anchors.fill: parent
                    onClicked: {}
                    onWheel: wheel => wheel.accepted = true
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 13
                        color: "#0c0c0c"
                        border.width: 1
                        border.color: searchField.activeFocus ? "#3a3a3a" : "#222222"

                        Behavior on border.color { ColorAnimation { duration: 160 } }

                        MIcon {
                            id: searchIcon

                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            name: "search"
                            size: 16
                            color: root.secondaryText

                            RotationAnimation on rotation {
                                running: root.searching
                                from: -12
                                to: 12
                                duration: 380
                                loops: Animation.Infinite
                                easing.type: Easing.InOutSine
                                onRunningChanged: if (!running) searchIcon.rotation = 0
                            }
                        }

                        TextInput {
                            id: searchField

                            anchors.left: searchIcon.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.query
                            color: root.primaryText
                            selectionColor: "#335a8f"
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            clip: true
                            onTextEdited: root.query = searchField.text

                            Keys.onPressed: event => {
                                const rows = root.drawerRows.length;
                                if (event.key === Qt.Key_Escape) {
                                    root.closeDrawer();
                                } else if (event.key === Qt.Key_Down) {
                                    if (rows)
                                        root.drawerIndex = (root.drawerIndex + 1) % rows;
                                } else if (event.key === Qt.Key_Up) {
                                    if (rows)
                                        root.drawerIndex = (root.drawerIndex - 1 + rows) % rows;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.chooseDrawerRow(root.drawerIndex);
                                } else if (event.key === Qt.Key_Delete && !root.drawerSearching) {
                                    root.removePlace(root.drawerIndex);
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchField.text === ""
                                text: "Search a city…"
                                color: root.faintText
                                font: searchField.font
                            }
                        }
                    }

                    Text {
                        text: root.drawerSearching ? (root.searching ? "SEARCHING" : (root.results.length ? "RESULTS  ·  ENTER TO ADD" : "NOTHING FOUND")) : "SAVED PLACES"
                        color: root.secondaryText
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        leftPadding: 4
                    }

                    ListView {
                        id: drawerList

                        width: parent.width
                        height: parent.height - 40 - 10 - 14 - 10
                        clip: true
                        spacing: 4
                        model: root.drawerRows
                        currentIndex: root.drawerIndex
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: false

                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                        }

                        delegate: Rectangle {
                            id: placeRow

                            required property var modelData
                            required property int index
                            readonly property string key: modelData.lat.toFixed(3) + "," + modelData.lon.toFixed(3)
                            readonly property var snap: root.savedNow[placeRow.key]
                            readonly property bool isActive: !root.drawerSearching && index === root.activeIndex
                            readonly property bool lit: root.drawerIndex === index || rowHover.hovered

                            width: drawerList.width
                            height: 44
                            radius: 12
                            color: placeRow.lit ? "#161616" : "#0b0b0b"
                            border.width: 1
                            border.color: placeRow.isActive ? root.withAlpha(root.accentColor, 0.45) : (placeRow.lit ? "#2c2c2c" : "#1a1a1a")

                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler {
                                id: rowHover

                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: if (hovered) root.drawerIndex = placeRow.index
                            }

                            TapHandler { onTapped: root.chooseDrawerRow(placeRow.index) }

                            MIcon {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                name: root.drawerSearching ? "add_location" : (placeRow.isActive ? "my_location" : "location_on")
                                size: 16
                                color: placeRow.isActive ? root.accentColor : root.secondaryText
                            }

                            Column {
                                x: 38
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 38 - 110

                                Text {
                                    width: parent.width
                                    text: placeRow.modelData.name
                                    color: root.primaryText
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                Text {
                                    width: parent.width
                                    text: [placeRow.modelData.region, placeRow.modelData.country].filter(s => s).join(", ")
                                    color: root.secondaryText
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }
                            }

                            Row {
                                anchors.right: removeButton.visible ? removeButton.left : parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                visible: placeRow.snap !== undefined

                                MIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: placeRow.snap ? root.weatherInfo(placeRow.snap.code, placeRow.snap.isDay).icon : ""
                                    size: 16
                                    color: root.primaryText
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: placeRow.snap ? Math.round(placeRow.snap.temp) + "°" : ""
                                    color: placeRow.snap ? root.tempColor(placeRow.snap.temp) : "white"
                                    font.family: root.fontFamily
                                    font.features: { "tnum": 1 }
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                id: removeButton

                                visible: !root.drawerSearching && root.locations.length > 1
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                radius: 8
                                color: removeHover.hovered ? "#2a1414" : "transparent"
                                opacity: placeRow.lit ? 1 : 0

                                Behavior on opacity { NumberAnimation { duration: 140 } }

                                HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.removePlace(placeRow.index) }

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: 13
                                    color: removeHover.hovered ? "#f87171" : "#6a6a6a"
                                }
                            }
                        }
                    }
                }
            }
        }

        // Hint / toast ---------------------------------------------------------
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: root.hintHeight
            horizontalAlignment: Text.AlignHCenter
            text: root.toast !== "" ? root.toast : (root.hint !== "" ? root.hint : (root.drawerOpen ? "↑↓ choose  ·  Enter open  ·  Del remove  ·  Esc back" : "←→ views  ·  type a city to search  ·  PgUp/PgDn places  ·  Ctrl+R refresh"))
            color: root.toast !== "" ? root.accentColor : root.faintText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
