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
    readonly property color accentColor: "#4ade80"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int inputRowHeight: 32
    readonly property int itemRowHeight: 30
    readonly property int maxVisibleItems: 5
    readonly property int footerHeight: 16
    readonly property int sectionSpacing: 10
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.inputRowHeight + root.sectionSpacing + root.itemRowHeight * root.maxVisibleItems + root.sectionSpacing + root.footerHeight

    signal closeRequested
    signal settingsRequested

    // Persisted task list: [{ id, text, done }, ...]. Loaded once from
    // todosFile below and rewritten on every add/toggle/delete.
    property var items: []
    property bool todosLoaded: false
    property int idCounter: 0

    readonly property int completedCount: root.items.filter(item => item.done).length

    function nextId() {
        root.idCounter += 1;
        return Date.now() + "-" + root.idCounter;
    }

    function addItem(text) {
        const trimmed = (text || "").trim();

        if (trimmed === "")
            return;

        root.items = root.items.concat([{
            id: root.nextId(),
            text: trimmed,
            done: false
        }]);
        root.saveTodos();
    }

    function toggleItem(id) {
        root.items = root.items.map(item => item.id === id ? Object.assign({}, item, {
            done: !item.done
        }) : item);
        root.saveTodos();
    }

    function removeItem(id) {
        root.items = root.items.filter(item => item.id !== id);
        root.saveTodos();
    }

    function applyTodosJson(text) {
        try {
            const parsed = JSON.parse(text);

            if (Array.isArray(parsed)) {
                root.items = parsed.filter(entry => entry && typeof entry.text === "string").map(entry => ({
                    id: entry.id !== undefined ? entry.id : root.nextId(),
                    text: entry.text,
                    done: entry.done === true
                }));
            }
        } catch (error) {
        // No saved tasks yet, or the file was hand-edited into something
        // unparseable — either way, start from an empty list.
        }

        root.todosLoaded = true;
    }

    function saveTodos() {
        if (!root.todosLoaded)
            return;

        todosFile.setText(JSON.stringify(root.items, null, 2) + "\n");
    }

    readonly property string todosPath: Quickshell.statePath("todos.json")
    readonly property string todosDir: root.todosPath.slice(0, Math.max(0, root.todosPath.lastIndexOf("/"))) || "."

    // The shell state dir usually exists already, but setText() will not
    // create it on a first run, so make sure of it before anything saves.
    Process {
        running: true
        command: ["mkdir", "-p", root.todosDir]
    }

    FileView {
        id: todosFile

        path: root.todosPath
        preload: true
        printErrors: false
        onLoaded: root.applyTodosJson(todosFile.text())
        onLoadFailed: root.todosLoaded = true
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    onVisibleChanged: {
        if (root.visible)
            todoFocusScope.forceActiveFocus();
    }

    FocusScope {
        id: todoFocusScope

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
                        name: "checklist"
                        size: 15
                        color: root.primaryText
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "To-Do"
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
                Layout.preferredHeight: root.inputRowHeight
                radius: 8
                color: "#0a0a0a"
                border.width: 1
                border.color: taskInput.activeFocus ? root.accentColor : "#232323"

                TextInput {
                    id: taskInput

                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 34
                    verticalAlignment: Text.AlignVCenter
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    clip: true
                    selectByMouse: true

                    onAccepted: {
                        root.addItem(taskInput.text);
                        taskInput.text = "";
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: taskInput.text === "" && !taskInput.activeFocus
                        text: "Add a task…"
                        color: "#5f5f5f"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: 7
                    color: addMouse.containsMouse ? "#1a1a1a" : "transparent"

                    MIcon {
                        anchors.centerIn: parent
                        name: "add"
                        size: 15
                        color: root.secondaryText
                    }

                    MouseArea {
                        id: addMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.addItem(taskInput.text);
                            taskInput.text = "";
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.itemRowHeight * root.maxVisibleItems
                clip: true

                Text {
                    anchors.centerIn: parent
                    visible: root.items.length === 0
                    text: "No tasks yet"
                    color: root.secondaryText
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }

                ListView {
                    anchors.fill: parent
                    visible: root.items.length > 0
                    model: root.items
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: taskRow

                        required property var modelData
                        required property int index

                        width: ListView.view ? ListView.view.width : 0
                        height: root.itemRowHeight

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: "transparent"
                                border.width: 1
                                border.color: taskRow.modelData.done ? root.accentColor : "#333333"

                                MIcon {
                                    anchors.centerIn: parent
                                    visible: taskRow.modelData.done
                                    name: "check"
                                    size: 12
                                    color: root.accentColor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleItem(taskRow.modelData.id)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: taskRow.modelData.text
                                elide: Text.ElideRight
                                color: taskRow.modelData.done ? root.secondaryText : root.primaryText
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                font.strikeout: taskRow.modelData.done

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleItem(taskRow.modelData.id)
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                radius: 10
                                color: deleteMouse.containsMouse ? "#1a1a1a" : "transparent"

                                MIcon {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: 11
                                    color: "#666666"
                                }

                                MouseArea {
                                    id: deleteMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeItem(taskRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: root.footerHeight
                horizontalAlignment: Text.AlignRight
                text: root.items.length === 0 ? "" : root.completedCount + " of " + root.items.length + " done"
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
            }
        }
    }
}
