import QtQuick

// A row of dots standing in for the clock while a workspace switch is in
// flight. activeIndex is 1-based; 0 means nothing highlighted yet.
Row {
    id: root

    property int count: 4
    property int activeIndex: 0
    property color dotColor: "#4ade80"
    property color idleColor: "#3a3a3a"
    property int dotSize: 8

    height: root.dotSize
    spacing: root.dotSize * 0.85

    Repeater {
        model: root.count

        Rectangle {
            id: dot

            required property int index

            readonly property bool active: root.activeIndex === dot.index + 1

            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: dot.active ? root.dotColor : root.idleColor
            scale: dot.active ? 1.35 : 1

            Behavior on color {
                ColorAnimation { duration: 160 }
            }

            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 }
            }
        }
    }
}
