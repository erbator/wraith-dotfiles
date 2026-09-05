import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var entries: []
    property int highlightIndex: 0
    property string statusText: ""
    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int footerHeight: 20
    readonly property int sectionSpacing: 10
    readonly property int rowHeight: 40
    readonly property int rowSpacing: 6
    // Capped in whole rows, same reasoning as WallpaperPanel: a mid-row clip
    // chops the last visible row instead of just scrolling it off.
    readonly property int maxVisibleRows: 6
    readonly property int visibleRows: Math.max(1, Math.min(root.maxVisibleRows, root.entries.length))
    readonly property int listHeight: root.visibleRows * root.rowHeight + Math.max(0, root.visibleRows - 1) * root.rowSpacing
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.listHeight + root.sectionSpacing + root.footerHeight
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    signal closeRequested
    signal refreshRequested
    signal clearRequested
    signal applyRequested(string raw)
    signal deleteRequested(string raw)
    signal highlightNavRequested(int delta)
    signal activateRequested

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    // Same reasoning as WallpaperPanel: instantiated once at startup, so
    // Component.onCompleted would fire long before this ever opens. Re-grab
    // focus (and pull a fresh list) on every open instead.
    onVisibleChanged: {
        if (root.visible) {
            clipboardFocusScope.forceActiveFocus();
            root.refreshRequested();
        }
    }

    FocusScope {
        id: clipboardFocusScope

        anchors.fill: parent
        focus: true

        Keys.onUpPressed: root.highlightNavRequested(-1)
        Keys.onDownPressed: root.highlightNavRequested(1)
        Keys.onReturnPressed: {
            console.log("CLIP_DEBUG: Return pressed, highlightIndex=" + root.highlightIndex + " entries=" + root.entries.length);
            root.activateRequested();
        }
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
                        name: "content_paste"
                        size: 15
                        color: root.primaryText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: "Clipboard"
                        color: root.primaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.statusText !== "" ? root.statusText : (root.entries.length + (root.entries.length === 1 ? " item" : " items"))
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
                    color: clearMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"
                    scale: clearMouse.pressed ? 0.86 : (clearMouse.containsMouse ? 1.1 : 1)

                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }

                    MIcon {
                        anchors.centerIn: parent
                        name: "delete_sweep"
                        size: 12
                        color: "#999999"
                    }

                    MouseArea {
                        id: clearMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearRequested()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 10
                    color: closeMouse.containsMouse ? "#1a1a1a" : "#0a0a0a"
                    border.width: 1
                    border.color: "#232323"
                    scale: closeMouse.pressed ? 0.86 : (closeMouse.containsMouse ? 1.1 : 1)

                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }

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
                Layout.preferredHeight: root.listHeight
                Layout.maximumHeight: root.listHeight
                clip: true

                Text {
                    anchors.centerIn: parent
                    text: "Nothing copied yet"
                    color: root.secondaryText
                    visible: root.entries.length === 0
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                ListView {
                    id: clipboardList

                    anchors.fill: parent
                    visible: root.entries.length > 0
                    model: root.entries
                    spacing: root.rowSpacing
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 400
                    currentIndex: root.highlightIndex

                    delegate: Rectangle {
                        id: clipRow

                        required property var modelData
                        required property int index

                        readonly property bool keyHighlighted: clipRow.ListView.isCurrentItem

                        width: ListView.view.width
                        height: root.rowHeight
                        radius: 10
                        color: clipRow.keyHighlighted ? "#141414" : (rowMouse.containsMouse ? "#101010" : "#0a0a0a")
                        border.width: 1
                        border.color: clipRow.keyHighlighted ? "#f0f0f0" : "#202020"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: clipRow.modelData.preview
                                color: clipRow.keyHighlighted ? root.primaryText : "#c8c8c8"
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: rowDeleteMouse.containsMouse ? "#241414" : "transparent"

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: 10
                                    color: rowDeleteMouse.containsMouse ? "#f0736a" : "#6f6f6f"
                                }

                                MouseArea {
                                    id: rowDeleteMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.deleteRequested(clipRow.modelData.raw)
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onClicked: {
                                console.log("CLIP_DEBUG: row clicked, raw=[" + clipRow.modelData.raw + "]");
                                root.applyRequested(clipRow.modelData.raw);
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
                    text: "Click an entry to copy it again"
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
