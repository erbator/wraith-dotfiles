import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color accentColor: "#4ade80"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int inputHeight: 40
    readonly property int operatorRowHeight: 32
    readonly property int resultHeight: 46
    readonly property int sectionSpacing: 10
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.inputHeight + root.sectionSpacing + root.operatorRowHeight + root.sectionSpacing + root.resultHeight
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // The displayed number tweens toward this on every valid keystroke, so
    // the result visibly counts up/down instead of snapping.
    property real displayValue: 0
    property bool hasResult: false

    readonly property var operatorTokens: [
        { label: "√", insert: "sqrt(", after: ")" },
        { label: "x²", insert: "^2", after: "" },
        { label: "^", insert: "^", after: "" },
        { label: "%", insert: "%", after: "" },
        { label: "π", insert: " pi ", after: "" },
        { label: "e", insert: " e ", after: "" },
        { label: "n!", insert: "!", after: "" },
        { label: "()", insert: "(", after: ")" }
    ]

    signal closeRequested
    signal settingsRequested

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    Behavior on displayValue {
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }

    // Same reasoning as WallpaperPanel: this panel is instantiated once at
    // startup, so Component.onCompleted would fire long before it's ever
    // opened. Re-grab focus (and reset the expression) on every open instead.
    onVisibleChanged: {
        if (root.visible) {
            calcInput.text = "";
            calcInput.forceActiveFocus();
            openKick.restart();
        }
    }

    SequentialAnimation {
        id: openKick

        NumberAnimation { target: calcFocusScope; property: "scale"; from: 0.9; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
    }

    SequentialAnimation {
        id: resultPopAnim

        NumberAnimation { target: resultLabel; property: "scale"; to: 1.16; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: resultLabel; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
    }

    // Accepts plain arithmetic, common English phrasing ("12 times 12",
    // "12 divided by 12"), and a handful of scientific functions (sqrt, cbrt,
    // log/ln, sin/cos/tan, abs, pi/e, n! factorial, ^ power). Word/function
    // names are first mapped to unique @@TOKEN@@ placeholders — never plain
    // "Math.xxx" text — so a later rule (e.g. the standalone "log" rule)
    // can never re-match text an earlier rule already inserted. Only after
    // every placeholder is swapped in does the whitelist check run, so
    // nothing but digits/operators/parens/known-safe tokens ever reaches
    // the evaluator. Anything not yet a complete, valid expression (mid-word,
    // trailing operator, empty) just shows nothing, the same as Noctalia's
    // inline calculator — no "Error"/"Unknown" flashing while typing.
    function evaluate(raw) {
        const trimmed = raw.trim();

        if (trimmed === "")
            return null;

        let expr = (" " + trimmed.toLowerCase() + " ")
            .replace(/\bto the power of\b/g, " @@POW@@ ")
            .replace(/\bpower of\b/g, " @@POW@@ ")
            .replace(/\bsquare root of\b/g, " @@SQRT@@")
            .replace(/\bcube root of\b/g, " @@CBRT@@")
            .replace(/\blog base 2 of\b/g, " @@LOG2@@")
            .replace(/\blog base 10 of\b/g, " @@LOG10@@")
            .replace(/\bnatural log of\b/g, " @@LN@@")
            .replace(/\bmultiplied by\b/g, " * ")
            .replace(/\bdivided by\b/g, " / ")
            .replace(/\btimes\b/g, " * ")
            .replace(/\binto\b/g, " * ")
            .replace(/\bover\b/g, " / ")
            .replace(/\bplus\b/g, " + ")
            .replace(/\bminus\b/g, " - ")
            .replace(/\bmod(?:ulo)?\b/g, " % ")
            .replace(/\bsqrt\b/g, " @@SQRT@@")
            .replace(/\bcbrt\b/g, " @@CBRT@@")
            .replace(/\blog10\b/g, " @@LOG10@@")
            .replace(/\blog2\b/g, " @@LOG2@@")
            .replace(/\bln\b/g, " @@LN@@")
            .replace(/\blog\b/g, " @@LOG10@@")
            .replace(/\bsin\b/g, " @@SIN@@")
            .replace(/\bcos\b/g, " @@COS@@")
            .replace(/\btan\b/g, " @@TAN@@")
            .replace(/\babs\b/g, " @@ABS@@")
            .replace(/\bpi\b/g, " @@PI@@")
            .replace(/\beuler\b/g, " @@E@@")
            .replace(/\be\b/g, " @@E@@")
            .replace(/\bx\b/g, " * ")
            .replace(/\^/g, " @@POW@@ ")
            .replace(/(\d),(\d)/g, "$1$2")
            .replace(/(\d+(?:\.\d+)?)!/g, "@@FACT@@($1)")
            .replace(/@@POW@@/g, "**")
            .replace(/@@SQRT@@/g, "Math.sqrt")
            .replace(/@@CBRT@@/g, "Math.cbrt")
            .replace(/@@LOG10@@/g, "Math.log10")
            .replace(/@@LOG2@@/g, "Math.log2")
            .replace(/@@LN@@/g, "Math.log")
            .replace(/@@SIN@@/g, "Math.sin")
            .replace(/@@COS@@/g, "Math.cos")
            .replace(/@@TAN@@/g, "Math.tan")
            .replace(/@@ABS@@/g, "Math.abs")
            .replace(/@@PI@@/g, "Math.PI")
            .replace(/@@E@@/g, "Math.E")
            .replace(/@@FACT@@/g, "fact");

        if (!root.isSafeExpression(expr))
            return null;

        try {
            const value = Function("fact", '"use strict"; return (' + expr + ')')(root.factorial);

            return typeof value === "number" && isFinite(value) ? value : null;
        } catch (error) {
            return null;
        }
    }

    // Strips every known-safe token (all of them literal, all inserted only
    // by this file) out of a copy of the expression; whatever is left must
    // be nothing but digits/operators/parens/commas, or the real expression
    // never reaches Function().
    function isSafeExpression(expr) {
        const allowedTokens = ["Math.sqrt", "Math.cbrt", "Math.log10", "Math.log2", "Math.log", "Math.sin", "Math.cos", "Math.tan", "Math.abs", "Math.PI", "Math.E", "fact"];
        let stripped = expr;

        for (const token of allowedTokens)
            stripped = stripped.split(token).join("");

        return /^[\s0-9+\-*/%.(),]*$/.test(stripped);
    }

    function factorial(n) {
        const value = Math.floor(n);

        if (value < 0 || value > 170)
            return NaN;

        let result = 1;

        for (let i = 2; i <= value; i++)
            result *= i;

        return result;
    }

    function formatNumber(value) {
        if (Number.isInteger(value))
            return String(value);

        return String(Math.round(value * 1e8) / 1e8);
    }

    function recompute(text) {
        const value = root.evaluate(text);

        if (value === null) {
            root.hasResult = false;
            return;
        }

        root.hasResult = true;
        root.displayValue = value;
        resultPopAnim.restart();
    }

    function insertOperator(item) {
        const pos = calcInput.cursorPosition;
        const text = calcInput.text;

        calcInput.text = text.slice(0, pos) + item.insert + item.after + text.slice(pos);
        calcInput.cursorPosition = pos + item.insert.length;
        calcInput.forceActiveFocus();
    }

    FocusScope {
        id: calcFocusScope

        anchors.fill: parent
        focus: true
        transformOrigin: Item.Center

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
                    id: iconBadge

                    Layout.preferredWidth: root.headerHeight
                    Layout.preferredHeight: root.headerHeight
                    radius: 11
                    color: "#090909"
                    border.width: 1
                    border.color: "#232323"

                    // A slow, subtle breathing pulse so the panel feels alive
                    // rather than static while it's sitting open.
                    SequentialAnimation on scale {
                        running: root.visible
                        loops: Animation.Infinite

                        NumberAnimation { to: 1.08; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }

                    MIcon {
                        anchors.centerIn: parent
                        name: "calculate"
                        size: 15
                        color: root.primaryText
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Calculator"
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
                    scale: settingsMouse.pressed ? 0.86 : (settingsMouse.containsMouse ? 1.1 : 1)

                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }

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
                Layout.preferredHeight: root.inputHeight

                Rectangle {
                    id: inputBox

                    anchors.fill: parent
                    radius: 12
                    color: "#0a0a0a"
                    border.width: 1
                    border.color: calcInput.activeFocus ? "#3a3a3a" : "#232323"

                    Behavior on border.color {
                        ColorAnimation { duration: 180 }
                    }
                }

                // A soft glow ring that breathes around the input while it
                // holds a valid result — the "something landed" heartbeat.
                Rectangle {
                    anchors.fill: inputBox
                    radius: inputBox.radius
                    color: "transparent"
                    border.width: 1
                    border.color: root.accentColor
                    visible: root.hasResult
                    opacity: 0

                    SequentialAnimation on opacity {
                        running: root.hasResult
                        loops: Animation.Infinite

                        NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.12; duration: 900; easing.type: Easing.InOutSine }
                    }
                }

                TextInput {
                    id: calcInput

                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    clip: true
                    selectByMouse: true

                    onTextChanged: root.recompute(text)
                    // Chain further calculations off the last answer.
                    onAccepted: {
                        if (root.hasResult)
                            calcInput.text = root.formatNumber(root.displayValue);
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "12 times 12"
                        color: "#5f5f5f"
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        visible: calcInput.text.length === 0
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.operatorRowHeight
                spacing: 6

                Repeater {
                    model: root.operatorTokens

                    Rectangle {
                        id: opTile

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: opMouse.containsMouse ? "#161616" : "#0a0a0a"
                        border.width: 1
                        border.color: "#232323"
                        scale: opMouse.pressed ? 0.84 : (opMouse.containsMouse ? 1.08 : 1)

                        Behavior on scale {
                            NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: opTile.modelData.label
                            color: root.primaryText
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: opMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.insertOperator(opTile.modelData)
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.resultHeight

                Text {
                    id: resultLabel

                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: root.hasResult ? "= " + root.formatNumber(root.displayValue) : ""
                    color: root.accentColor
                    font.family: root.fontFamily
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    transformOrigin: Item.Right

                    Behavior on opacity {
                        NumberAnimation { duration: 160 }
                    }

                    opacity: root.hasResult ? 1 : 0
                }
            }
        }
    }
}
