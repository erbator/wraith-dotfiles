import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color accentColor: "#5b9cf0"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int sectionSpacing: 8
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property int heroHeight: 148
    readonly property int hourlyHeight: 76
    readonly property int tilesHeight: 122
    readonly property int dailyRowHeight: 24
    readonly property int dailyMaxVisible: 5
    readonly property real dailyHeight: root.dailyRowHeight * root.dailyMaxVisible + (root.dailyMaxVisible - 1) * 2

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.heroHeight + root.sectionSpacing + root.hourlyHeight + root.sectionSpacing + root.tilesHeight + root.sectionSpacing + root.dailyHeight

    signal closeRequested
    signal settingsRequested

    // Fixed to a specific city rather than IP geolocation (unreliable — often
    // resolves to the ISP's regional hub, not the actual town).
    readonly property string locationName: "Kecskemét"
    readonly property string weatherUrl: "https://api.open-meteo.com/v1/forecast?latitude=46.90618&longitude=19.69128&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation,is_day,uv_index&hourly=temperature_2m,weather_code,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,sunrise,sunset&timezone=auto&forecast_days=7"

    property var weatherData: null
    property bool weatherLoaded: false
    property string weatherError: ""

    function refreshWeather() {
        weatherFetchProcess.running = false;
        weatherFetchProcess.running = true;
    }

    function applyWeatherJson(text) {
        try {
            const parsed = JSON.parse(text);

            if (parsed && parsed.current && parsed.hourly && parsed.daily) {
                root.weatherData = parsed;
                root.weatherError = "";
            } else {
                root.weatherError = "Couldn't load weather";
            }
        } catch (error) {
            root.weatherError = "Couldn't load weather";
        }

        root.weatherLoaded = true;
    }

    Process {
        id: weatherFetchProcess

        command: ["curl", "-s", "--max-time", "10", root.weatherUrl]
        stdout: StdioCollector {
            onStreamFinished: root.applyWeatherJson(text)
        }
    }

    Timer {
        interval: 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshWeather()
    }

    // WMO weather code -> {label, icon, effect}. `effect` drives which
    // animated background below is shown.
    function weatherInfo(code, isDay) {
        if (code === 0)
            return {
                label: "Clear",
                icon: isDay ? "sunny" : "clear_night",
                effect: isDay ? "sun" : "night"
            };
        if (code === 1)
            return {
                label: "Mostly Clear",
                icon: isDay ? "partly_cloudy_day" : "partly_cloudy_night",
                effect: isDay ? "sun" : "night"
            };
        if (code === 2)
            return {
                label: "Partly Cloudy",
                icon: isDay ? "partly_cloudy_day" : "partly_cloudy_night",
                effect: "cloudy"
            };
        if (code === 3)
            return {
                label: "Overcast",
                icon: "cloud",
                effect: "cloudy"
            };
        if (code === 45 || code === 48)
            return {
                label: "Fog",
                icon: "foggy",
                effect: "fog"
            };
        if ([51, 53, 55, 56, 57].includes(code))
            return {
                label: "Drizzle",
                icon: "rainy",
                effect: "rain"
            };
        if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code))
            return {
                label: "Rain",
                icon: "rainy",
                effect: "rain"
            };
        if ([71, 73, 75, 77, 85, 86].includes(code))
            return {
                label: "Snow",
                icon: "ac_unit",
                effect: "snow"
            };
        if ([95, 96, 99].includes(code))
            return {
                label: "Thunderstorm",
                icon: "thunderstorm",
                effect: "storm"
            };

        return {
            label: "Cloudy",
            icon: "cloud",
            effect: "cloudy"
        };
    }

    function gradientStops(effect, isDay) {
        if (effect === "sun")
            return ["#3f7fd6", "#8ec4ef"];
        if (effect === "night")
            return ["#0c1638", "#2a3466"];
        if (effect === "cloudy")
            return isDay ? ["#5c7188", "#8fa2b8"] : ["#1c2333", "#343c50"];
        if (effect === "rain")
            return isDay ? ["#455163", "#697990"] : ["#161b28", "#2a3140"];
        if (effect === "snow")
            return isDay ? ["#7f93a8", "#c6d5e3"] : ["#28324a", "#404c63"];
        if (effect === "fog")
            return isDay ? ["#7d828a", "#adb3ba"] : ["#292c31", "#454951"];
        if (effect === "storm")
            return ["#262838", "#3d3f52"];

        return ["#455163", "#697990"];
    }

    function windDirectionLabel(deg) {
        const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

        return dirs[Math.round(deg / 45) % 8];
    }

    function uvLabel(uv) {
        if (uv < 3)
            return "Low";
        if (uv < 6)
            return "Moderate";
        if (uv < 8)
            return "High";
        if (uv < 11)
            return "Very High";

        return "Extreme";
    }

    function dayName(isoDate) {
        const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

        return names[new Date(isoDate).getDay()];
    }

    readonly property var current: root.weatherData ? root.weatherData.current : null
    readonly property bool isDay: !root.current || root.current.is_day === 1
    readonly property int weatherCode: root.current ? root.current.weather_code : 0
    readonly property var info: root.weatherInfo(root.weatherCode, root.isDay)
    readonly property var stops: root.gradientStops(root.info.effect, root.isDay)

    readonly property var hourlyEntries: {
        if (!root.weatherData)
            return [];

        const hourly = root.weatherData.hourly;
        const now = new Date();
        const key = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0") + "T" + String(now.getHours()).padStart(2, "0") + ":00";
        let startIndex = hourly.time.indexOf(key);

        if (startIndex === -1)
            startIndex = 0;

        const entries = [];

        for (let i = startIndex; i < Math.min(startIndex + 12, hourly.time.length); i++) {
            entries.push({
                hourLabel: i === startIndex ? "Now" : String(new Date(hourly.time[i]).getHours()),
                temp: Math.round(hourly.temperature_2m[i]),
                icon: root.weatherInfo(hourly.weather_code[i], true).icon
            });
        }

        return entries;
    }

    readonly property var dailyEntries: {
        if (!root.weatherData)
            return [];

        const daily = root.weatherData.daily;
        const entries = [];

        for (let i = 0; i < Math.min(root.dailyMaxVisible, daily.time.length); i++) {
            entries.push({
                dayLabel: i === 0 ? "Today" : root.dayName(daily.time[i]),
                icon: root.weatherInfo(daily.weather_code[i], true).icon,
                max: Math.round(daily.temperature_2m_max[i]),
                min: Math.round(daily.temperature_2m_min[i])
            });
        }

        return entries;
    }

    readonly property real weekMinTemp: root.dailyEntries.length ? Math.min(...root.dailyEntries.map(d => d.min)) : 0
    readonly property real weekMaxTemp: root.dailyEntries.length ? Math.max(...root.dailyEntries.map(d => d.max)) : 1
    readonly property real weekTempSpan: Math.max(1, root.weekMaxTemp - root.weekMinTemp)

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            weatherFocusScope.forceActiveFocus();

            if (!root.weatherLoaded)
                root.refreshWeather();
        }
    }

    FocusScope {
        id: weatherFocusScope

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
                        name: root.weatherData ? root.info.icon : "cloud"
                        size: 15
                        color: root.primaryText
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Weather"
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
                    color: refreshMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"

                    MIcon {
                        anchors.centerIn: parent
                        name: "refresh"
                        size: 12
                        color: "#999999"
                    }

                    MouseArea {
                        id: refreshMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshWeather()
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

            // --- Hero: animated current-conditions card ---------------------
            Rectangle {
                id: hero

                Layout.fillWidth: true
                Layout.preferredHeight: root.heroHeight
                radius: 14
                clip: true
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop {
                        position: 0
                        color: root.stops[0]
                    }
                    GradientStop {
                        position: 1
                        color: root.stops[1]
                    }
                }

                // --- Sun (clear day): glow + slowly rotating rays -----------
                Item {
                    anchors.fill: parent
                    visible: root.info.effect === "sun"

                    Item {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        width: 70
                        height: 70

                        Repeater {
                            model: 8

                            Rectangle {
                                required property int index

                                anchors.centerIn: parent
                                width: 2
                                height: 44
                                radius: 1
                                color: "#ffffff"
                                opacity: 0.25

                                RotationAnimation on rotation {
                                    from: index * 45
                                    to: index * 45 + 360
                                    duration: 60000
                                    loops: Animation.Infinite
                                }
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 34
                            height: 34
                            radius: 17
                            color: "#fff2c2"

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 0.75
                                    duration: 2200
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 2200
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }

                // --- Night (clear): twinkling stars -------------------------
                Item {
                    anchors.fill: parent
                    visible: root.info.effect === "night"

                    Repeater {
                        model: 16

                        Rectangle {
                            required property int index

                            x: (index * 53) % Math.max(1, hero.width - 40) + 10
                            y: (index * 29) % Math.max(1, root.heroHeight - 70) + 8
                            width: 2
                            height: 2
                            radius: 1
                            color: "#ffffff"

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PropertyAction {
                                    value: 0.4
                                }
                                PauseAnimation {
                                    duration: (index * 240) % 1800
                                }
                                NumberAnimation {
                                    to: 0.15
                                    duration: 900 + (index % 5) * 150
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 0.9
                                    duration: 900 + (index % 5) * 150
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }

                // --- Cloudy: soft drifting cloud blobs ----------------------
                Item {
                    anchors.fill: parent
                    visible: root.info.effect === "cloudy" || root.info.effect === "fog"
                    clip: true

                    Repeater {
                        model: 3

                        Rectangle {
                            required property int index

                            width: 90 - index * 14
                            height: 26 - index * 4
                            radius: height / 2
                            color: "#ffffff"
                            opacity: root.info.effect === "fog" ? 0.16 : 0.14
                            y: 16 + index * 34

                            NumberAnimation on x {
                                from: -100
                                to: hero.width + 20
                                duration: 26000 + index * 9000
                                loops: Animation.Infinite
                            }
                        }
                    }
                }

                // --- Rain / storm: falling streaks ---------------------------
                Item {
                    anchors.fill: parent
                    visible: root.info.effect === "rain" || root.info.effect === "storm"
                    clip: true

                    Repeater {
                        model: 18

                        Rectangle {
                            required property int index

                            x: Math.random() * Math.max(1, hero.width)
                            width: 2
                            height: 14
                            radius: 1
                            color: "#dbe9ff"
                            opacity: 0.4
                            rotation: 12

                            NumberAnimation on y {
                                from: -20
                                to: root.heroHeight + 20
                                duration: 450 + Math.random() * 350
                                loops: Animation.Infinite
                            }
                        }
                    }

                    // Occasional lightning flash for storms.
                    Rectangle {
                        anchors.fill: parent
                        color: "#ffffff"
                        visible: root.info.effect === "storm"

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PropertyAction {
                                value: 0
                            }
                            PauseAnimation {
                                duration: 4000 + Math.random() * 5000
                            }
                            NumberAnimation {
                                to: 0.35
                                duration: 60
                            }
                            NumberAnimation {
                                to: 0
                                duration: 120
                            }
                        }
                    }
                }

                // --- Snow: drifting flakes -----------------------------------
                Item {
                    anchors.fill: parent
                    visible: root.info.effect === "snow"
                    clip: true

                    Repeater {
                        model: 16

                        Rectangle {
                            required property int index

                            // drift is animated (not x directly) so the
                            // sway target is a fixed number, not a binding
                            // that reads the very property being animated —
                            // `to: x + 14` would chase a moving target and
                            // never actually converge.
                            readonly property real baseX: Math.random() * Math.max(1, hero.width)
                            property real drift

                            x: baseX + drift
                            width: 3
                            height: 3
                            radius: 1.5
                            color: "#ffffff"
                            opacity: 0.7

                            NumberAnimation on y {
                                from: -10
                                to: root.heroHeight + 10
                                duration: 3500 + Math.random() * 2500
                                loops: Animation.Infinite
                            }

                            SequentialAnimation on drift {
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 14
                                    duration: 1400
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: -14
                                    duration: 1400
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }

                // --- Foreground content --------------------------------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 2

                    Text {
                        text: root.locationName
                        color: "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.current ? Math.round(root.current.temperature_2m) + "°" : (root.weatherError !== "" ? "—" : "…")
                            color: "#ffffff"
                            font.family: root.fontFamily
                            font.pixelSize: 46
                            font.weight: Font.Light
                        }

                        Column {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                anchors.right: parent.right
                                text: root.weatherData ? root.info.label : (root.weatherError !== "" ? root.weatherError : "Loading…")
                                color: "#ffffff"
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.right: parent.right
                                visible: root.current !== null
                                text: root.current ? "Feels like " + Math.round(root.current.apparent_temperature) + "°" : ""
                                color: "#ffffff"
                                opacity: 0.75
                                font.family: root.fontFamily
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // --- Hourly forecast strip ---------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.hourlyHeight
                radius: 12
                color: "#0a0a0a"
                border.width: 1
                border.color: "#1c1c1c"

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    orientation: ListView.Horizontal
                    spacing: 2
                    clip: true
                    interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.hourlyEntries

                    delegate: Column {
                        required property var modelData

                        width: 42
                        height: root.hourlyHeight - 12
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.hourLabel
                            color: modelData.hourLabel === "Now" ? root.accentColor : root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.weight: modelData.hourLabel === "Now" ? Font.Bold : Font.Normal
                        }

                        MIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: modelData.icon
                            size: 16
                            color: root.primaryText
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.temp + "°"
                            color: root.primaryText
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // --- Detail tiles: feels like / wind / humidity / UV -------------
            GridLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tilesHeight
                columns: 2
                columnSpacing: root.sectionSpacing
                rowSpacing: root.sectionSpacing

                Repeater {
                    model: [
                        {
                            icon: "thermostat",
                            label: "FEELS LIKE",
                            value: root.current ? Math.round(root.current.apparent_temperature) + "°" : "—"
                        },
                        {
                            icon: "air",
                            label: "WIND",
                            value: root.current ? Math.round(root.current.wind_speed_10m) + " km/h " + root.windDirectionLabel(root.current.wind_direction_10m) : "—"
                        },
                        {
                            icon: "water_drop",
                            label: "HUMIDITY",
                            value: root.current ? root.current.relative_humidity_2m + "%" : "—"
                        },
                        {
                            icon: "wb_sunny",
                            label: "UV INDEX",
                            value: root.current ? Math.round(root.current.uv_index) + " " + root.uvLabel(root.current.uv_index) : "—"
                        }
                    ]

                    Rectangle {
                        id: tile

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: "#0a0a0a"
                        border.width: 1
                        border.color: "#1c1c1c"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                spacing: 4

                                MIcon {
                                    name: tile.modelData.icon
                                    size: 12
                                    color: root.secondaryText
                                }

                                Text {
                                    text: tile.modelData.label
                                    color: root.secondaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                                text: tile.modelData.value
                                elide: Text.ElideRight
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            // --- Daily forecast ------------------------------------------------
            Column {
                Layout.fillWidth: true
                Layout.preferredHeight: root.dailyHeight
                spacing: 2

                Repeater {
                    model: root.dailyEntries

                    Item {
                        required property var modelData

                        width: parent.width
                        height: root.dailyRowHeight

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8

                            Text {
                                Layout.preferredWidth: 46
                                text: modelData.dayLabel
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            MIcon {
                                Layout.preferredWidth: 18
                                name: modelData.icon
                                size: 14
                                color: root.secondaryText
                            }

                            Text {
                                Layout.preferredWidth: 26
                                text: modelData.min + "°"
                                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 11
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 2
                                    color: "#232323"
                                }

                                Rectangle {
                                    readonly property real startFrac: (modelData.min - root.weekMinTemp) / root.weekTempSpan
                                    readonly property real endFrac: (modelData.max - root.weekMinTemp) / root.weekTempSpan

                                    anchors.verticalCenter: parent.verticalCenter
                                    x: startFrac * parent.width
                                    width: Math.max(4, (endFrac - startFrac) * parent.width)
                                    height: 4
                                    radius: 2
                                    color: root.accentColor
                                }
                            }

                            Text {
                                Layout.preferredWidth: 26
                                horizontalAlignment: Text.AlignRight
                                text: modelData.max + "°"
                                color: root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
        }
    }
}
