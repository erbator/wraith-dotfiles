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
    readonly property color accentColor: "#5eead4"
    readonly property color activeMarkColor: "#4ade80"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int searchRowHeight: 32
    readonly property int cardWidth: 104
    readonly property int cardHeight: 92
    readonly property int footerHeight: 16
    readonly property int sectionSpacing: 10
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.searchRowHeight + root.sectionSpacing + root.cardHeight + root.sectionSpacing + root.footerHeight

    signal closeRequested
    signal settingsRequested

    readonly property string themesPath: Quickshell.env("HOME") + "/.config/hypr/themes/themes.json"
    readonly property string currentThemePath: Quickshell.env("HOME") + "/.config/hypr/themes/current"
    readonly property string applyScriptPath: Quickshell.env("HOME") + "/.config/hypr/scripts/apply-theme.sh"

    property var themes: []
    property string currentThemeId: ""
    property string searchText: ""
    property int highlightIndex: 0
    property string statusText: ""

    readonly property var filteredThemes: root.themes.filter(theme => {
        if (root.searchText === "")
            return true;

        return theme.name.toLowerCase().indexOf(root.searchText.toLowerCase()) !== -1;
    })

    function applyThemeJson(text) {
        try {
            const parsed = JSON.parse(text);

            if (Array.isArray(parsed))
                root.themes = parsed;
        } catch (error) {
        // themes.json missing or invalid — panel just shows an empty list.
        }
    }

    function moveHighlight(delta) {
        if (root.filteredThemes.length === 0)
            return;

        root.highlightIndex = Math.max(0, Math.min(root.filteredThemes.length - 1, root.highlightIndex + delta));
    }

    function applyHighlighted() {
        const theme = root.filteredThemes[root.highlightIndex];

        if (!theme)
            return;

        // A bare `running = true` is a no-op if a previous apply is still in
        // flight (e.g. two themes picked in quick succession) — property
        // writes only trigger on an actual value change, so the second pick
        // would silently never launch. Stopping first forces a real restart.
        applyThemeProcess.running = false;
        applyThemeProcess.command = [root.applyScriptPath, theme.id];
        applyThemeProcess.running = true;
        root.currentThemeId = theme.id;
        root.statusText = "Applied " + theme.name;
        statusClearTimer.restart();
    }

    onSearchTextChanged: root.highlightIndex = 0

    Process {
        id: applyThemeProcess
    }

    Process {
        id: readCurrentThemeProcess

        command: ["cat", root.currentThemePath]
        stdout: StdioCollector {
            onStreamFinished: root.currentThemeId = text.trim()
        }
    }

    Timer {
        id: statusClearTimer

        interval: 2400
        repeat: false
        onTriggered: root.statusText = ""
    }

    FileView {
        id: themesFile

        path: root.themesPath
        preload: true
        printErrors: false
        onLoaded: root.applyThemeJson(themesFile.text())
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible) {
            readCurrentThemeProcess.running = false;
            readCurrentThemeProcess.running = true;
            themeSearchInput.forceActiveFocus();
        }
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
                    name: "palette"
                    size: 15
                    color: root.primaryText
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Theme"
                color: root.primaryText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            Text {
                text: (root.filteredThemes.length) + "/" + root.themes.length
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 11
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

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.searchRowHeight
            radius: 8
            color: "#0a0a0a"
            border.width: 1
            border.color: themeSearchInput.activeFocus ? root.accentColor : "#232323"

            MIcon {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 14
                color: "#5f5f5f"
            }

            TextInput {
                id: themeSearchInput

                anchors.fill: parent
                anchors.leftMargin: 32
                anchors.rightMargin: 10
                verticalAlignment: Text.AlignVCenter
                color: root.primaryText
                font.family: root.fontFamily
                font.pixelSize: 12
                clip: true
                selectByMouse: true

                onTextChanged: root.searchText = text

                Keys.onLeftPressed: root.moveHighlight(-1)
                Keys.onRightPressed: root.moveHighlight(1)
                Keys.onReturnPressed: root.applyHighlighted()
                Keys.onEnterPressed: root.applyHighlighted()
                Keys.onEscapePressed: {
                    if (themeSearchInput.text !== "")
                        themeSearchInput.text = "";
                    else
                        root.closeRequested();
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: themeSearchInput.text === ""
                    text: "Search themes…"
                    color: "#5f5f5f"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.cardHeight

            Text {
                anchors.centerIn: parent
                visible: root.filteredThemes.length === 0
                text: "No themes found"
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 12
            }

            ListView {
                id: themeList

                anchors.fill: parent
                visible: root.filteredThemes.length > 0
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: root.filteredThemes
                currentIndex: root.highlightIndex
                highlightMoveDuration: 120
                boundsBehavior: Flickable.StopAtBounds

                onCurrentIndexChanged: themeList.positionViewAtIndex(themeList.currentIndex, ListView.Contain)

                delegate: Item {
                    id: themeCard

                    required property var modelData
                    required property int index

                    readonly property bool selected: index === root.highlightIndex
                    readonly property bool isActive: modelData.id === root.currentThemeId

                    width: root.cardWidth
                    height: root.cardHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "#0a0a0a"
                        border.width: themeCard.selected ? 2 : 1
                        border.color: themeCard.selected ? root.accentColor : "#232323"

                        Rectangle {
                            visible: themeCard.isActive
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 6
                            height: 6
                            radius: 3
                            color: root.activeMarkColor
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Repeater {
                                        model: [themeCard.modelData.colors.red, themeCard.modelData.colors.yellow, themeCard.modelData.colors.green, themeCard.modelData.colors.cyan, themeCard.modelData.colors.blue, themeCard.modelData.colors.magenta]

                                        Rectangle {
                                            required property string modelData

                                            width: 9
                                            height: 9
                                            radius: 4.5
                                            color: modelData
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: themeCard.modelData.name
                                elide: Text.ElideRight
                                color: themeCard.selected ? root.primaryText : root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.highlightIndex = themeCard.index;
                                root.applyHighlighted();
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.footerHeight
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.statusText
                color: root.activeMarkColor
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            Text {
                horizontalAlignment: Text.AlignRight
                text: "Enter to apply"
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 10
            }
        }
    }
}
