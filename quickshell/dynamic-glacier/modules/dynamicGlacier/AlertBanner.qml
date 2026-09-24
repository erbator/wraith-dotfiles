import QtQuick
import QtQuick.Layouts

// The banner a panel raises when something it owns goes off: a reminder,
// a Focus phase ending, a countdown running out. Replaces the plain "!"
// notification for those with:
//   - a glowing orb in the alert's colour, ripples while it rings
//   - kicker / title / details
//   - action buttons that talk back to the panel (Snooze, Start break, +1 min…)
//   - a countdown line along the bottom that freezes while hovered
//
// `alert` shape:
//   { source, kind, accent, icon, kicker, title, body, meta,
//     actions: [{ id, label, icon, primary }], timeout }
Item {
    id: root

    property var alert: null
    property bool active: false
    property bool paused: false
    property string feedback: ""
    property string fontFamily: "Noto Sans"

    signal actionTriggered(string id)

    readonly property color tint: root.alert && root.alert.accent ? root.alert.accent : "#ffffff"
    readonly property var actions: root.alert && root.alert.actions ? root.alert.actions : []
    property real progress: 1

    opacity: root.active ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity { NumberAnimation { duration: 220 } }

    onAlertChanged: if (root.alert && root.active) root.replay()
    onActiveChanged: if (root.active && root.alert) root.replay()
    onPausedChanged: {
        if (root.paused)
            countdown.pause();
        else
            countdown.resume();
    }

    function replay() {
        countdown.stop();
        root.progress = 1;
        countdown.duration = Math.max(1000, root.alert.timeout || 9000);
        countdown.start();
        if (root.paused)
            countdown.pause();
        entrance.restart();
    }

    NumberAnimation {
        id: countdown

        target: root
        property: "progress"
        from: 1
        to: 0
    }

    // Colour wash from the orb's side.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -12
        radius: 22
        opacity: 0.55
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.16) }
            GradientStop { position: 0.35; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.04) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    // Clicking the body opens the panel it came from.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.actionTriggered("open")
    }

    RowLayout {
        anchors.fill: parent
        anchors.bottomMargin: 6
        spacing: 14

        // Orb
        Item {
            id: orb

            Layout.preferredWidth: 58
            Layout.preferredHeight: 58
            Layout.alignment: Qt.AlignTop

            Repeater {
                model: 2

                Rectangle {
                    id: ripple

                    required property int index

                    anchors.centerIn: parent
                    width: 46
                    height: 46
                    radius: 23
                    color: "transparent"
                    border.width: 1.5
                    border.color: root.tint
                    opacity: 0

                    SequentialAnimation {
                        running: root.active && root.visible && !root.paused
                        loops: Animation.Infinite

                        PauseAnimation { duration: ripple.index * 800 }
                        ParallelAnimation {
                            NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.75; duration: 1600; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ripple; property: "opacity"; from: 0.55; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                        }
                        PauseAnimation { duration: (1 - ripple.index) * 800 }
                    }
                }
            }

            Rectangle {
                id: core

                anchors.centerIn: parent
                width: 46
                height: 46
                radius: 23
                border.width: 1
                border.color: Qt.lighter(root.tint, 1.35)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(root.tint, 1.15) }
                    GradientStop { position: 1; color: Qt.darker(root.tint, 1.55) }
                }

                // Glass highlight
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 3
                    width: parent.width - 14
                    height: parent.height / 2 - 4
                    radius: height / 2
                    opacity: 0.28
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#ffffff" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                MIcon {
                    id: orbIcon

                    anchors.centerIn: parent
                    name: root.alert && root.alert.icon ? root.alert.icon : "notifications"
                    size: 22
                    filled: true
                    color: "#0b0b0b"
                    transformOrigin: Item.Top
                }

                // A little ring-ring shake, every couple of seconds.
                SequentialAnimation {
                    running: root.active && root.visible && !root.paused
                    loops: Animation.Infinite

                    PauseAnimation { duration: 350 }
                    NumberAnimation { target: orbIcon; property: "rotation"; to: 16; duration: 60 }
                    NumberAnimation { target: orbIcon; property: "rotation"; to: -14; duration: 90 }
                    NumberAnimation { target: orbIcon; property: "rotation"; to: 10; duration: 80 }
                    NumberAnimation { target: orbIcon; property: "rotation"; to: -6; duration: 80 }
                    NumberAnimation { target: orbIcon; property: "rotation"; to: 0; duration: 120; easing.type: Easing.OutCubic }
                    PauseAnimation { duration: 1500 }
                }
            }
        }

        // Text + actions
        ColumnLayout {
            id: textColumn

            transform: Translate {
                id: textShift
            }

            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.alert && root.alert.kicker ? root.alert.kicker.toUpperCase() : ""
                color: root.tint
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.Black
                font.letterSpacing: 1.5
            }

            Text {
                id: titleText

                Layout.fillWidth: true
                text: root.alert ? root.alert.title : ""
                color: "#fafafa"
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 17
                font.weight: Font.Bold
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.alert && root.alert.body ? root.alert.body : ""
                color: "#8c8c8c"
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: root.fontFamily
                font.pixelSize: 11
            }

            Item {
                Layout.fillHeight: true
            }

            // Actions, or what the last action did.
            Item {
                id: actionArea

                transform: Translate {
                    id: actionShift
                }

                Layout.fillWidth: true
                Layout.preferredHeight: 26

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - actionRow.width - 10
                    text: root.alert && root.alert.meta ? root.alert.meta : ""
                    color: "#555555"
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    opacity: root.feedback === "" ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                Row {
                    id: actionRow

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    opacity: root.feedback === "" ? 1 : 0
                    visible: opacity > 0.01

                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    Repeater {
                        model: root.actions

                        Rectangle {
                            id: pill

                            required property var modelData
                            required property int index

                            readonly property bool primary: modelData.primary === true

                            width: pillRow.implicitWidth + 20
                            height: 26
                            radius: 9
                            color: pill.primary ? (pillHover.hovered ? Qt.lighter(root.tint, 1.12) : root.tint) : (pillHover.hovered ? "#1f1f1f" : "#121212")
                            border.width: pill.primary ? 0 : 1
                            border.color: pillHover.hovered ? "#3a3a3a" : "#242424"
                            scale: pillMouse.pressed ? 0.9 : (pillHover.hovered ? 1.06 : 1)

                            Behavior on color { ColorAnimation { duration: 140 } }
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }

                            Row {
                                id: pillRow

                                anchors.centerIn: parent
                                spacing: 4

                                MIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pill.modelData.icon !== undefined
                                    name: pill.modelData.icon || ""
                                    size: 13
                                    color: pill.primary ? "#0b0b0b" : "#cfcfcf"
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pill.modelData.label
                                    color: pill.primary ? "#0b0b0b" : "#e6e6e6"
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }

                            // HoverHandler, not MouseArea hover: the island's
                            // hitbox sits on top and takes MouseArea hover.
                            HoverHandler {
                                id: pillHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                id: pillMouse

                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.actionTriggered(pill.modelData.id)
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    opacity: root.feedback !== "" ? 1 : 0
                    visible: opacity > 0.01
                    scale: root.feedback !== "" ? 1 : 0.85

                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                    MIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check_circle"
                        size: 16
                        filled: true
                        color: root.tint
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.feedback
                        color: root.tint
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }

    // Time left before the banner goes away; stops while you hover it.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        radius: 1
        color: "#161616"

        Rectangle {
            width: parent.width * root.progress
            height: parent.height
            radius: 1
            color: root.tint
            opacity: root.paused ? 0.45 : 0.85

            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }

    // Entrance: the orb pops, the text slides in, the buttons rise.
    ParallelAnimation {
        id: entrance

        NumberAnimation { target: orb; property: "scale"; from: 0.35; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        NumberAnimation { target: orb; property: "rotation"; from: -40; to: 0; duration: 520; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PropertyAction { target: textColumn; property: "opacity"; value: 0 }
            PauseAnimation { duration: 80 }
            ParallelAnimation {
                NumberAnimation { target: textColumn; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: textShift; property: "x"; from: 18; to: 0; duration: 420; easing.type: Easing.OutCubic }
            }
        }
        SequentialAnimation {
            PropertyAction { target: actionArea; property: "opacity"; value: 0 }
            PauseAnimation { duration: 220 }
            ParallelAnimation {
                NumberAnimation { target: actionArea; property: "opacity"; to: 1; duration: 260 }
                NumberAnimation { target: actionShift; property: "y"; from: 8; to: 0; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
        }
    }
}
