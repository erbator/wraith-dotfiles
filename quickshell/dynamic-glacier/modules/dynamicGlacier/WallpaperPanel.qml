import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var entries: []
    property string currentPath: ""
    property string statusText: ""
    property bool applying: false
    property int highlightIndex: 0
    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int footerHeight: 24
    readonly property int sectionSpacing: 10
    readonly property int gridColumns: 3
    readonly property int gridSpacing: 8
    readonly property int cellHeight: 88
    // Capped in whole rows, never a pixel height — a mid-row clip chops tile
    // borders in half at the bottom edge instead of just scrolling them off.
    readonly property int maxVisibleRows: 3
    readonly property int gridRows: Math.max(1, Math.ceil(root.entries.length / root.gridColumns))
    readonly property int visibleRows: Math.max(1, Math.min(root.maxVisibleRows, root.gridRows))
    readonly property int gridHeight: root.visibleRows * root.cellHeight + Math.max(0, root.visibleRows - 1) * root.gridSpacing
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.gridHeight + root.sectionSpacing + root.footerHeight
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    signal closeRequested
    signal settingsRequested
    signal refreshRequested
    signal applyRequested(string path)
    signal highlightNavRequested(int dx, int dy)
    signal activateRequested

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    // Unlike the Apps grid (which lives behind a Loader and gets a fresh
    // FocusScope — and a fresh Component.onCompleted — every time it opens),
    // this panel is instantiated once at startup like the other standalone
    // panels. Component.onCompleted would only ever fire that one time, long
    // before the panel is first opened, so arrow keys never had a focus
    // target to reach. Re-grab focus on every open instead, via the same
    // `visible` property already driven by panelProgress.
    onVisibleChanged: {
        if (root.visible)
            wallpaperFocusScope.forceActiveFocus();
    }

    FocusScope {
        id: wallpaperFocusScope

        anchors.fill: parent
        focus: true

        Keys.onUpPressed: root.highlightNavRequested(0, -1)
        Keys.onDownPressed: root.highlightNavRequested(0, 1)
        Keys.onLeftPressed: root.highlightNavRequested(-1, 0)
        Keys.onRightPressed: root.highlightNavRequested(1, 0)
        Keys.onReturnPressed: root.activateRequested()
        Keys.onEnterPressed: root.activateRequested()
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
                        name: "wallpaper"
                        size: 15
                        color: root.primaryText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: "Wallpaper"
                        color: root.primaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.statusText !== "" ? root.statusText : (root.entries.length + (root.entries.length === 1 ? " image" : " images"))
                        color: root.statusText !== "" ? "#f0736a" : root.secondaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
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
                        onClicked: root.refreshRequested()
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

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.gridHeight
                Layout.maximumHeight: root.gridHeight
                clip: true

                Text {
                    anchors.centerIn: parent
                    text: "No images in ~/Pictures/Wallpapers"
                    color: root.secondaryText
                    visible: root.entries.length === 0
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                GridView {
                    id: wallpaperGrid

                    anchors.fill: parent
                    visible: root.entries.length > 0
                    model: root.entries
                    cellWidth: width / root.gridColumns
                    cellHeight: root.cellHeight
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 400
                    currentIndex: root.highlightIndex

                    delegate: Item {
                        id: wallpaperTile

                        required property var modelData
                        required property int index

                        readonly property bool isCurrent: wallpaperTile.modelData.path === root.currentPath
                        readonly property bool keyHighlighted: wallpaperTile.GridView.isCurrentItem

                        width: wallpaperGrid.cellWidth
                        height: wallpaperGrid.cellHeight

                        Rectangle {
                            id: tileFrame

                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 12
                            color: "#0a0a0a"
                            border.width: wallpaperTile.keyHighlighted ? 2 : 1
                            border.color: wallpaperTile.keyHighlighted ? "#f0f0f0" : (wallpaperTile.isCurrent ? "#4ade80" : "#232323")
                            // clip lives on the inner Item below, not here: clipping a
                            // Rectangle that also draws a rounded border chops the
                            // border's corners (Qt Quick clips to the bounding rect,
                            // not the antialiased rounded path).

                            Item {
                                anchors.fill: parent
                                anchors.margins: 1
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    // Plain absolute paths coerce to file:// URLs correctly
                                    // (including spaces) via QML's url-property handling —
                                    // manual "file://" + path concatenation mangles spaces.
                                    source: wallpaperTile.modelData.path
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    sourceSize.width: 240
                                    sourceSize.height: 180
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 18
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "#00000000" }
                                        GradientStop { position: 1; color: "#c0000000" }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 5
                                        text: wallpaperTile.modelData.name
                                        color: "#f0f0f0"
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 4
                                width: 16
                                height: 16
                                radius: 8
                                color: "#4ade80"
                                visible: wallpaperTile.isCurrent

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "check"
                                    size: 11
                                    color: "#04140a"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyRequested(wallpaperTile.modelData.path)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.footerHeight

                Text {
                    Layout.fillWidth: true
                    text: "Drop images into ~/Pictures/Wallpapers"
                    color: "#606060"
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
