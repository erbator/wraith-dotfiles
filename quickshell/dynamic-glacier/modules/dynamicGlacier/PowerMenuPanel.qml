import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int tileRowHeight: 98
    readonly property int sectionSpacing: 10
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.tileRowHeight
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))
    // How long a tile must be held before it fires, in ms.
    readonly property int holdDuration: 650
    // Index of the tile currently held down via its number key, or -1.
    // Repeater delegates read this to drive the same hold-to-confirm
    // animation the mouse gesture uses.
    property int heldIndex: -1

    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "lock", tint: "#4ade80" },
        { id: "logout", label: "Logout", icon: "logout", tint: "#f0b429" },
        { id: "suspend", label: "Sleep", icon: "bedtime", tint: "#4ade80" },
        { id: "reboot", label: "Reboot", icon: "restart_alt", tint: "#f0736a" },
        { id: "shutdown", label: "Shutdown", icon: "power_settings_new", tint: "#f0736a" }
    ]

    signal closeRequested
    signal powerActionRequested(string action)

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    // Same reasoning as the other standalone panels: instantiated once at
    // startup, so grab focus fresh on every open rather than relying on
    // Component.onCompleted.
    onVisibleChanged: {
        if (root.visible)
            powerFocusScope.forceActiveFocus();
    }

    FocusScope {
        id: powerFocusScope

        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.closeRequested()

        // 1-5 mirror the tiles left to right. A real key-up always fires
        // exactly once even under OS key-repeat, so a single onPressed is
        // enough to start the hold — the animation runs on its own timeline
        // from there, same as the mouse gesture.
        Keys.onPressed: event => {
            if (event.isAutoRepeat)
                return;

            const index = event.key - Qt.Key_1;

            if (index >= 0 && index < root.actions.length) {
                root.heldIndex = index;
                event.accepted = true;
            }
        }

        Keys.onReleased: event => {
            if (event.isAutoRepeat)
                return;

            const index = event.key - Qt.Key_1;

            if (index === root.heldIndex) {
                root.heldIndex = -1;
                event.accepted = true;
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
                        name: "power_settings_new"
                        size: 15
                        color: root.primaryText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: "Power"
                        color: root.primaryText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Hold a tile, or its number key, to confirm"
                        color: root.secondaryText
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

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tileRowHeight
                spacing: 8

                Repeater {
                    model: root.actions

                    delegate: Rectangle {
                        id: actionTile

                        required property var modelData
                        required property int index

                        property real holdProgress: 0
                        readonly property color tintColor: actionTile.modelData.tint
                        readonly property bool keyHeld: actionTile.index === root.heldIndex

                        // Guards against resetAnim (still running from a
                        // quick prior release) and holdAnim both driving
                        // holdProgress at once on a fast re-press — shared
                        // by both the mouse gesture and the number-key one.
                        function beginHold() {
                            resetAnim.stop();
                            holdAnim.restart();
                        }

                        function endHold() {
                            holdAnim.stop();
                        }

                        onKeyHeldChanged: {
                            if (actionTile.keyHeld)
                                actionTile.beginHold();
                            else
                                actionTile.endHold();
                        }

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        color: "#080808"
                        border.width: 1
                        border.color: Qt.tint("#202020", Qt.rgba(actionTile.tintColor.r, actionTile.tintColor.g, actionTile.tintColor.b, actionTile.holdProgress * 0.7))
                        clip: true

                        // The charge bar: fills from the bottom while held,
                        // firing the action only once it's completely full —
                        // a fat-fingered tap alone can never trigger anything.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: parent.height * actionTile.holdProgress
                            color: actionTile.tintColor
                            opacity: 0.16
                        }

                        NumberAnimation {
                            id: holdAnim

                            target: actionTile
                            property: "holdProgress"
                            from: actionTile.holdProgress
                            to: 1
                            duration: root.holdDuration * (1 - actionTile.holdProgress)
                            easing.type: Easing.Linear

                            onStopped: {
                                if (actionTile.holdProgress < 0.999) {
                                    resetAnim.restart();
                                    return;
                                }

                                tilePop.restart();
                                root.powerActionRequested(actionTile.modelData.id);
                                clearTimer.restart();
                            }
                        }

                        NumberAnimation {
                            id: resetAnim

                            target: actionTile
                            property: "holdProgress"
                            to: 0
                            duration: 180
                            easing.type: Easing.OutCubic
                        }

                        Timer {
                            id: clearTimer

                            interval: 260
                            repeat: false
                            onTriggered: resetAnim.restart()
                        }

                        SequentialAnimation {
                            id: tilePop

                            NumberAnimation { target: tileIcon; property: "scale"; to: 1.35; duration: 110; easing.type: Easing.OutCubic }
                            NumberAnimation { target: tileIcon; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MIcon {
                                id: tileIcon

                                Layout.alignment: Qt.AlignHCenter
                                name: actionTile.modelData.icon
                                size: 20
                                color: Qt.tint(root.primaryText, Qt.rgba(actionTile.tintColor.r, actionTile.tintColor.g, actionTile.tintColor.b, actionTile.holdProgress * 0.85))
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: actionTile.modelData.label
                                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: keyBadgeText.implicitWidth + 10
                                height: 14
                                radius: 7
                                color: "#141414"
                                border.width: 1
                                border.color: "#292929"

                                Text {
                                    id: keyBadgeText

                                    anchors.centerIn: parent
                                    text: String(actionTile.index + 1)
                                    color: "#8d8d8d"
                                    font.family: root.fontFamily
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: actionTile.beginHold()
                            onReleased: actionTile.endHold()
                            onCanceled: actionTile.endHold()
                        }
                    }
                }
            }
        }
    }
}
