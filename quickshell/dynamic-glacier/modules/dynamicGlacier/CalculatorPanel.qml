import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string fontFamily: "Noto Sans"

    // SF Pro Display is an optical size drawn for 20px and up; below that it
    // reads small and thin, so the sub-20px sizes get bumped whenever it is
    // the selected family. Every other family (all monospace) is unchanged.
    function fontPx(size) {
        return root.fontFamily === "SF Pro Display" && size < 20 ? Math.round(size * 1.2) : size;
    }
    property real morph: 0

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color accentColor: "#4ade80"
    readonly property int panelPadding: 16
    readonly property int headerHeight: 32
    readonly property int inputHeight: 40
    // Big result on top, a small caption line (currency rate/date) below.
    readonly property int resultHeight: 58
    readonly property int sectionSpacing: 10
    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.sectionSpacing + root.inputHeight + root.sectionSpacing + root.resultHeight
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // The displayed number tweens toward this on every valid keystroke, so
    // the result visibly counts up/down instead of snapping.
    property real displayValue: 0
    property real resultValue: 0
    property bool hasResult: false

    // Currency conversion: "100 usd to huf", "€50 in ft", "$20", "1000 ft"
    // (home currency converts to the foreign one), "100 to usd" (from the
    // home currency), "usd to huf" (just the rate). The amount is any
    // calculator expression. Rates are relative to EUR, from the cache
    // currency-rates.sh keeps fresh; while a conversion is showing, the
    // caption under the result gives the rate and the rates' date.
    readonly property string homeCurrency: "huf"
    readonly property string foreignCurrency: "eur"
    readonly property string ratesPath: Quickshell.env("HOME") + "/.cache/dynamic-glacier/rates.json"
    property var rates: ({})
    property string ratesDate: ""
    property bool ratesFetching: false
    // Set while the input reads as a conversion, whether or not it has a
    // result yet (rates may still be loading).
    property bool currencyMode: false
    property string currencyFrom: ""
    property string currencyTo: ""
    property real currencyRate: 0
    readonly property var currencyAliases: ({
        "$": "usd", "dollar": "usd", "dollars": "usd", "bucks": "usd",
        "€": "eur", "euro": "eur", "euros": "eur",
        "ft": "huf", "forint": "huf", "forints": "huf",
        "£": "gbp", "pound": "gbp", "pounds": "gbp", "quid": "gbp",
        "franc": "chf", "francs": "chf",
        "¥": "jpy", "yen": "jpy",
        "zloty": "pln", "złoty": "pln",
        "koruna": "czk", "korona": "czk",
        "lei": "ron", "leu": "ron",
        "yuan": "cny", "lira": "try",
        "₹": "inr", "rupee": "inr", "rupees": "inr",
        "₿": "btc", "bitcoin": "btc", "ethereum": "eth"
    })

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
            root.refreshRates();
        }
    }

    function refreshRates() {
        if (ratesFetch.running)
            return;

        root.ratesFetching = true;
        ratesFetch.running = true;
    }

    function applyRates(text) {
        try {
            const data = JSON.parse(text);

            if (data && data.eur && typeof data.eur === "object") {
                root.rates = data.eur;
                root.ratesDate = data.date || "";
            }
        } catch (error) {
        }

        if (root.currencyMode)
            root.recompute(calcInput.text);
    }

    // Keeps the cache fresh (no-op under twelve hours old) and then reloads
    // it, so a stale or missing cache heals itself the next time the panel
    // is opened with a connection.
    Process {
        id: ratesFetch

        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/currency-rates.sh"]
        onExited: {
            root.ratesFetching = false;
            ratesFile.reload();
        }
    }

    FileView {
        id: ratesFile

        path: root.ratesPath
        printErrors: false
        onLoaded: root.applyRates(ratesFile.text())
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
    // "square root of 16", "10 percent of 50"), unicode operators (× ÷ − √ π
    // ² ³) and the usual scientific functions. The text is normalised to
    // symbols, tokenised, and parsed by a small recursive-descent parser —
    // nothing is ever handed to eval/Function, so there is no whitelist to
    // get wrong and no JavaScript quirks leaking through (-2^2 is -4, not a
    // syntax error). Anything not yet a complete, valid expression (mid-word,
    // trailing operator, empty) just shows nothing, the same as Noctalia's
    // inline calculator — no "Error"/"Unknown" flashing while typing.
    //
    // Semantics:
    //   ^ is right-associative and binds tighter than unary minus
    //   n! factorial and n% percent are postfix; "a + b%" is a plus b percent
    //   of a (200 + 10% = 220), while "a % b" and "a mod b" are modulo
    //   2(3), (2)(3), 2pi, 2 sqrt 4 multiply implicitly
    //   functions work with or without parentheses: sqrt 16, sqrt(16)
    //   trig is in degrees; asin/acos/atan return degrees
    //   , and . are both decimal separators; 1 000 000 and 1,000,000 group
    //   2e3 is scientific notation; e on its own is Euler's number
    //   : divides (10:2 = 5), x multiplies, a trailing = is ignored
    readonly property var calcConstants: ({ pi: Math.PI, e: Math.E, tau: 2 * Math.PI })
    readonly property var calcFunctions: ({
        sqrt: x => Math.sqrt(x),
        cbrt: x => Math.cbrt(x),
        ln: x => Math.log(x),
        log: x => Math.log10(x),
        log10: x => Math.log10(x),
        log2: x => Math.log2(x),
        sin: x => root.roundTiny(Math.sin(x * Math.PI / 180)),
        cos: x => root.roundTiny(Math.cos(x * Math.PI / 180)),
        tan: x => root.roundTiny(Math.tan(x * Math.PI / 180)),
        asin: x => Math.asin(x) * 180 / Math.PI,
        acos: x => Math.acos(x) * 180 / Math.PI,
        atan: x => Math.atan(x) * 180 / Math.PI,
        abs: x => Math.abs(x),
        floor: x => Math.floor(x),
        ceil: x => Math.ceil(x),
        round: x => Math.round(x),
        exp: x => Math.exp(x)
    })

    // sin(180°) is 1.2e-16 in floating point; nobody wants to see that.
    function roundTiny(value) {
        return Math.abs(value) < 1e-12 ? 0 : value;
    }

    function normalize(raw) {
        return (" " + raw.toLowerCase() + " ")
            .replace(/[×·]/g, " * ")
            .replace(/[÷:]/g, " / ")
            .replace(/=\s*$/, " ")
            .replace(/−/g, " - ")
            .replace(/√/g, " sqrt ")
            .replace(/π/g, " pi ")
            .replace(/²/g, "^2")
            .replace(/³/g, "^3")
            .replace(/\*\*/g, "^")
            .replace(/\b(?:to the power of|raised to the power of|raised to|power of)\b/g, " ^ ")
            .replace(/\bsquare root of\b/g, " sqrt ")
            .replace(/\bcube root of\b/g, " cbrt ")
            .replace(/\bnatural log of\b/g, " ln ")
            .replace(/\blog base 2 of\b/g, " log2 ")
            .replace(/\blog base 10 of\b/g, " log10 ")
            .replace(/\b(sqrt|cbrt|ln|log|log2|log10|sin|cos|tan|asin|acos|atan|abs|floor|ceil|round|exp)\s+of\b/g, " $1 ")
            .replace(/\b(?:multiplied by|times|into)\b/g, " * ")
            .replace(/\b(?:divided by|over)\b/g, " / ")
            .replace(/\bplus\b/g, " + ")
            .replace(/\bminus\b/g, " - ")
            .replace(/\bmod(?:ulo)?\b/g, " mod ")
            .replace(/\bsquared\b/g, "^2")
            .replace(/\bcubed\b/g, "^3")
            .replace(/\bpercent\b/g, "%")
            .replace(/%\s*of\b/g, "% * ")
            .replace(/\bhalf of\b/g, " 0.5 * ")
            .replace(/\bdouble\b/g, " 2 * ")
            // "2x3", "2 x 3", "(1+1)x3": x between operands is multiplication.
            .replace(/([\d)])\s*x\s*([\d(])/g, "$1 * $2")
            .replace(/\bx\b/g, " * ");
    }

    // Digits with optional space-grouped thousands ("1 000 000"), scientific
    // notation ("2e3"), or a plain decimal with , or . — several commas each
    // followed by three digits are grouping ("1,000,000"), a single one is a
    // decimal point.
    function parseNumberToken(text) {
        let digits = text.replace(/ /g, "");
        const commas = (digits.match(/,/g) || []).length;

        if (commas > 1 && /^\d{1,3}(?:,\d{3})+(?:\.\d+)?$/.test(digits))
            digits = digits.replace(/,/g, "");
        else
            digits = digits.replace(/,/g, ".");

        if ((digits.match(/\./g) || []).length > 1)
            return NaN;

        return Number(digits);
    }

    function tokenize(text) {
        const tokens = [];
        let i = 0;

        while (i < text.length) {
            const rest = text.slice(i);
            let match;

            if (/^\s/.test(rest)) {
                i += 1;
            } else if ((match = rest.match(/^\d{1,3}(?: \d{3})+(?:[.,]\d+)?(?![\d.,])/)) || (match = rest.match(/^\d+(?:[.,]\d+)?e[+-]?\d+(?![\d.,])/)) || (match = rest.match(/^(?:\d+(?:[.,]\d+)*|[.,]\d+)/))) {
                const value = root.parseNumberToken(match[0]);

                if (!isFinite(value))
                    return null;

                tokens.push({ type: "number", value: value });
                i += match[0].length;
            } else if ((match = rest.match(/^[a-z][a-z0-9]*/))) {
                const word = match[0];

                if (word === "mod")
                    tokens.push({ type: "op", value: "mod" });
                else if (word in root.calcConstants)
                    tokens.push({ type: "const", value: root.calcConstants[word] });
                else if (word in root.calcFunctions)
                    tokens.push({ type: "func", value: word });
                else
                    return null;

                i += word.length;
            } else if ("+-*/^%!()".indexOf(rest[0]) >= 0) {
                tokens.push({ type: "op", value: rest[0] });
                i += 1;
            } else {
                return null;
            }
        }

        return tokens;
    }

    function evaluate(raw) {
        if (raw.trim() === "")
            return null;

        const tokens = root.tokenize(root.normalize(raw));

        if (!tokens || tokens.length === 0)
            return null;

        let pos = 0;
        const peek = () => tokens[pos];
        const isOp = (value) => pos < tokens.length && tokens[pos].type === "op" && tokens[pos].value === value;
        const take = () => tokens[pos++];
        const startsOperand = (token) => token !== undefined && (token.type === "number" || token.type === "const" || token.type === "func" || (token.type === "op" && token.value === "("));
        const fail = () => { throw new Error("parse"); };

        // Values carry a percent flag so "a + b%" can mean a plus b percent
        // of a; it is dropped as soon as the value takes part in anything
        // else.
        function additive() {
            let left = multiplicative();

            while (isOp("+") || isOp("-")) {
                const op = take().value;
                const right = multiplicative();
                const rightValue = right.percent ? left.value * right.value : right.value;

                left = { value: op === "+" ? left.value + rightValue : left.value - rightValue, percent: false };
            }

            return left;
        }

        function multiplicative() {
            let left = unary();

            for (;;) {
                let op;

                if (isOp("*") || isOp("/") || isOp("mod"))
                    op = take().value;
                else if (isOp("%") && startsOperand(tokens[pos + 1])) {
                    take();
                    op = "mod";
                } else if (startsOperand(peek()) && peek().type !== "number")
                    op = "*"; // implicit: 2(3), 2pi, 2 sqrt 4
                else if (peek() !== undefined && peek().type === "number" && tokens[pos - 1].type === "op" && tokens[pos - 1].value === ")")
                    op = "*"; // implicit: (2)3
                else
                    break;

                const right = unary();
                let value;

                if (op === "*")
                    value = left.value * right.value;
                else if (op === "/")
                    value = left.value / right.value;
                else
                    value = left.value % right.value;

                left = { value: value, percent: false };
            }

            return left;
        }

        function unary() {
            if (isOp("-")) {
                take();
                const operand = unary();
                return { value: -operand.value, percent: operand.percent };
            }

            if (isOp("+")) {
                take();
                return unary();
            }

            return power();
        }

        function power() {
            const base = postfix();

            if (isOp("^")) {
                take();
                const exponent = unary();
                return { value: Math.pow(base.value, exponent.value), percent: false };
            }

            return base;
        }

        function postfix() {
            let node = primary();

            for (;;) {
                if (isOp("!")) {
                    take();
                    node = { value: root.factorial(node.value), percent: false };
                } else if (isOp("%") && !startsOperand(tokens[pos + 1])) {
                    take();
                    node = { value: node.value / 100, percent: true };
                } else {
                    break;
                }
            }

            return node;
        }

        function primary() {
            const token = take();

            if (token === undefined)
                fail();

            if (token.type === "number" || token.type === "const")
                return { value: token.value, percent: false };

            if (token.type === "func") {
                let argument;

                if (isOp("(")) {
                    take();
                    argument = additive();
                    if (!isOp(")"))
                        fail();
                    take();
                } else {
                    argument = unary();
                }

                return { value: root.calcFunctions[token.value](argument.value), percent: false };
            }

            if (token.type === "op" && token.value === "(") {
                const inner = additive();

                if (!isOp(")"))
                    fail();
                take();
                return inner;
            }

            fail();
        }

        try {
            const result = additive();

            if (pos !== tokens.length)
                return null;

            return typeof result.value === "number" && isFinite(result.value) ? result.value : null;
        } catch (error) {
            return null;
        }
    }

    function factorial(n) {
        if (!Number.isInteger(n) || n < 0 || n > 170)
            return NaN;

        let result = 1;

        for (let i = 2; i <= n; i++)
            result *= i;

        return result;
    }

    // A currency for a word/symbol: an alias, or any three-letter code the
    // rates know (function names excluded, so "sin 30" is never a currency).
    function currencyCode(word) {
        if (word in root.currencyAliases)
            return root.currencyAliases[word];

        if (/^[a-z]{3}$/.test(word) && word in root.rates && !(word in root.calcFunctions) && word !== "mod")
            return word;

        return null;
    }

    // Splits "<amount> <from> to <to>" (any part optional but at least one
    // currency) into its pieces, or returns null for a plain calculation.
    function parseCurrency(raw) {
        let text = raw.toLowerCase().trim();
        let from = null;
        let to = null;

        const target = text.match(/(?:\b(?:to|in|into|as)\s+|->\s*|→\s*)([a-ząćęłńóśźżáéíóöőúüű]{2,}|[$€£¥₹₿])\s*$/);

        if (target) {
            to = root.currencyCode(target[1]);
            if (to)
                text = text.slice(0, target.index).trim();
        }

        const suffix = text.match(/([a-ząćęłńóśźżáéíóöőúüű]{2,}|[$€£¥₹₿])\s*$/);

        if (suffix) {
            from = root.currencyCode(suffix[1]);
            if (from)
                text = text.slice(0, suffix.index).trim();
        }

        if (!from) {
            const prefix = text.match(/^([$€£¥₹₿]|[a-z]{3}\b)\s*/);

            if (prefix) {
                from = root.currencyCode(prefix[1]);
                if (from)
                    text = text.slice(prefix[0].length);
            }
        }

        if (!from && !to)
            return null;

        if (!from)
            from = root.homeCurrency;
        if (!to)
            to = from === root.homeCurrency ? root.foreignCurrency : root.homeCurrency;

        return { amountText: text, from: from, to: to };
    }

    // Money: two decimals for anything from 1 up (trailing zeros trimmed),
    // four significant digits below that, thousands grouped with spaces.
    function formatMoney(value) {
        const abs = Math.abs(value);
        let text = abs >= 1 ? value.toFixed(2) : Number(value.toPrecision(4)).toString();

        if (text.indexOf("e") >= 0)
            return text;

        text = text.replace(/\.?0+$/, "");

        const parts = text.split(".");
        const sign = parts[0].startsWith("-") ? "-" : "";
        let integer = sign ? parts[0].slice(1) : parts[0];
        let grouped = "";

        while (integer.length > 3) {
            grouped = " " + integer.slice(-3) + grouped;
            integer = integer.slice(0, -3);
        }

        return sign + integer + grouped + (parts.length > 1 ? "." + parts[1] : "");
    }

    // 12 significant digits hides floating-point noise (0.1 + 0.2 shows as
    // 0.3) without rounding anything a person would type.
    function formatNumber(value) {
        if (Number.isInteger(value))
            return String(value === 0 ? 0 : value);

        const rounded = Number(value.toPrecision(12));

        return String(rounded === 0 ? 0 : rounded);
    }

    // While the displayed value is still tweening toward the result, show
    // it with the result's own number of decimals rather than a dozen digits
    // of animation noise.
    function formatDisplay() {
        if (root.currencyMode)
            return root.formatMoney(root.displayValue) + " " + root.currencyTo.toUpperCase();

        const finalText = root.formatNumber(root.resultValue);

        if (root.displayValue === root.resultValue || finalText.indexOf("e") >= 0)
            return finalText;

        const dot = finalText.indexOf(".");
        const decimals = dot < 0 ? 0 : finalText.length - dot - 1;

        return root.displayValue.toFixed(decimals);
    }

    function recompute(text) {
        const currency = root.parseCurrency(text);
        let value;

        root.currencyMode = currency !== null;

        if (currency) {
            const amount = currency.amountText === "" ? 1 : root.evaluate(currency.amountText);
            const known = currency.from in root.rates && currency.to in root.rates;

            root.currencyFrom = currency.from;
            root.currencyTo = currency.to;
            root.currencyRate = known ? root.rates[currency.to] / root.rates[currency.from] : 0;
            value = amount === null || !known ? null : amount * root.currencyRate;
        } else {
            value = root.evaluate(text);
        }

        if (value === null) {
            root.hasResult = false;
            return;
        }

        root.hasResult = true;
        root.resultValue = value;
        root.displayValue = value;
        resultPopAnim.restart();
    }

    function captionText() {
        if (!root.currencyMode)
            return "";

        if (root.hasResult)
            return "1 " + root.currencyFrom.toUpperCase() + " = " + root.formatMoney(root.currencyRate) + " " + root.currencyTo.toUpperCase() + (root.ratesDate ? " · " + root.ratesDate : "");

        if (root.ratesFetching)
            return "Fetching exchange rates…";

        if (!(root.currencyFrom in root.rates) || !(root.currencyTo in root.rates))
            return Object.keys(root.rates).length === 0 ? "Exchange rates unavailable" : "Unknown currency";

        return "";
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
                    font.pixelSize: root.fontPx(15)
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
                    font.features: { "tnum": 1 }
                    font.pixelSize: root.fontPx(14)
                    clip: true
                    selectByMouse: true

                    onTextChanged: root.recompute(text)
                    // Chain further calculations off the last answer.
                    onAccepted: {
                        if (root.hasResult)
                            calcInput.text = root.formatNumber(root.resultValue);
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "12 times 12  ·  100 usd to huf"
                        color: "#5f5f5f"
                        font.family: root.fontFamily
                        font.pixelSize: root.fontPx(14)
                        visible: calcInput.text.length === 0
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.resultHeight

                Text {
                    id: resultLabel

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 38
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: root.hasResult ? "= " + root.formatDisplay() : ""
                    color: root.accentColor
                    font.family: root.fontFamily
                    font.features: { "tnum": 1 }
                    font.pixelSize: root.fontPx(28)
                    font.weight: Font.Bold
                    transformOrigin: Item.Right

                    Behavior on opacity {
                        NumberAnimation { duration: 160 }
                    }

                    opacity: root.hasResult ? 1 : 0
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: root.captionText()
                    color: root.secondaryText
                    font.family: root.fontFamily
                    font.features: { "tnum": 1 }
                    font.pixelSize: root.fontPx(11)
                    opacity: text !== "" ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 160 }
                    }
                }
            }
        }
    }
}
