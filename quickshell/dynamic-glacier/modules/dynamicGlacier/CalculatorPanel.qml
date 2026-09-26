import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Calculator. One input, understood as:
//   maths      12 times 12 · 2^10 · sqrt 16 · 200 + 10% · 5! · sin 30
//   variables  x = 5 → x * 2 · ans is the last result
//   chaining   start with + × / ^ to carry on from ans
//   currency   100 usd to huf · €50 in ft · 1000 ft
//   units      5 km to mi · 180 lb in kg · 30 c to f · 2 gb in mib · 90 min
//   bases      0xff + 1 · 255 in hex · 0b1010 · 42 to bin
//   dates      days until dec 24 · today + 30 days · 2026.12.24
// Enter keeps it in the history (↑/↓ recall it, like a shell); Tab puts the
// result back into the input.
Item {
    id: root

    property string fontFamily: "Noto Sans"
    property real morph: 0

    signal closeRequested

    readonly property color primaryText: "#f7f7f7"
    readonly property color secondaryText: "#777777"
    readonly property color faintText: "#4f4f4f"
    readonly property color accentColor: "#4ade80"
    readonly property color errorColor: "#f87171"
    readonly property color cardColor: "#080808"
    readonly property color cardBorder: "#1b1b1b"
    readonly property var kindColors: ({ math: "#4ade80", currency: "#fbbf24", units: "#60a5fa", base: "#a78bfa", date: "#f472b6", var: "#22d3ee" })

    readonly property int panelPadding: 16
    readonly property int headerHeight: 34
    readonly property int inputHeight: 46
    readonly property int resultHeight: 64
    readonly property int altsHeight: 24
    readonly property int historyHeight: 168
    readonly property int hintHeight: 14
    readonly property int sectionSpacing: 10

    readonly property real contentHeight: root.panelPadding * 2 + root.headerHeight + root.inputHeight + root.resultHeight + root.altsHeight + root.historyHeight + root.hintHeight + root.sectionSpacing * 6
    readonly property real panelProgress: Math.max(0, Math.min(1, (root.morph - 0.22) / 0.78))

    // ── State ─────────────────────────────────────────────────────────────
    property string expr: ""
    property var result: null // { kind, value, text, copy, label, alts: [{ label, text }] }
    property var history: [] // newest first: { expr, text, copy, kind }
    property var vars: ({})
    property real ans: 0
    property bool hasAns: false
    property int recallIndex: -1
    property string toast: ""

    // ── Currency (rates relative to EUR, kept fresh by currency-rates.sh) ─
    readonly property string homeCurrency: "huf"
    readonly property string foreignCurrency: "eur"
    readonly property string ratesPath: Quickshell.env("HOME") + "/.cache/dynamic-glacier/rates.json"
    property var rates: ({})
    property string ratesDate: ""
    property bool ratesFetching: false
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

    // ── Units ─────────────────────────────────────────────────────────────
    // factor = how many base units one of these is. Temperature is special.
    readonly property var unitTable: ({
        length: { base: "m", units: { mm: 0.001, cm: 0.01, dm: 0.1, m: 1, km: 1000, "µm": 1e-6, in: 0.0254, ft: 0.3048, yd: 0.9144, mi: 1609.344, nmi: 1852 }, pairs: { km: "mi", mi: "km", m: "ft", ft: "m", cm: "in", in: "cm", mm: "in", yd: "m", nmi: "km", dm: "cm", "µm": "mm" } },
        mass: { base: "kg", units: { mg: 1e-6, g: 0.001, kg: 1, t: 1000, oz: 0.028349523125, lb: 0.45359237, st: 6.35029318 }, pairs: { kg: "lb", lb: "kg", g: "oz", oz: "g", t: "lb", st: "kg", mg: "g" } },
        volume: { base: "l", units: { ml: 0.001, cl: 0.01, dl: 0.1, l: 1, m3: 1000, tsp: 0.00492892159, tbsp: 0.0147867648, floz: 0.0295735296, cup: 0.2365882365, pt: 0.473176473, qt: 0.946352946, gal: 3.785411784 }, pairs: { l: "gal", gal: "l", ml: "floz", floz: "ml", cup: "ml", dl: "ml", cl: "ml", m3: "l", tsp: "ml", tbsp: "ml", pt: "l", qt: "l" } },
        time: { base: "s", units: { ms: 0.001, s: 1, min: 60, h: 3600, d: 86400, wk: 604800, mo: 2629746, yr: 31556952 }, pairs: { ms: "s", s: "min", min: "h", h: "min", d: "h", wk: "d", mo: "d", yr: "d" } },
        speed: { base: "m/s", units: { "m/s": 1, "km/h": 1 / 3.6, mph: 0.44704, kn: 0.514444 }, pairs: { "km/h": "mph", mph: "km/h", "m/s": "km/h", kn: "km/h" } },
        data: { base: "B", units: { bit: 0.125, B: 1, KB: 1e3, MB: 1e6, GB: 1e9, TB: 1e12, KiB: 1024, MiB: 1048576, GiB: 1073741824, TiB: 1099511627776 }, pairs: { KB: "KiB", MB: "MiB", GB: "GiB", TB: "TiB", KiB: "KB", MiB: "MB", GiB: "GB", TiB: "TB", bit: "B", B: "bit" } },
        area: { base: "m²", units: { "mm²": 1e-6, "cm²": 1e-4, "m²": 1, "km²": 1e6, ha: 1e4, acre: 4046.8564224, "ft²": 0.09290304, "in²": 0.00064516 }, pairs: { "m²": "ft²", "ft²": "m²", ha: "acre", acre: "ha", "km²": "ha", "cm²": "in²", "in²": "cm²", "mm²": "cm²" } },
        energy: { base: "J", units: { J: 1, kJ: 1000, cal: 4.184, kcal: 4184, Wh: 3600, kWh: 3.6e6 }, pairs: { kcal: "kJ", kJ: "kcal", cal: "J", J: "cal", kWh: "kJ", Wh: "J" } },
        temperature: { base: "°C", units: { "°C": 1, "°F": 1, K: 1 }, pairs: { "°C": "°F", "°F": "°C", K: "°C" } }
    })

    // Every spelling → [dimension, canonical unit]
    readonly property var unitAliases: {
        const map = {};
        const add = (dim, unit, names) => {
            for (const n of names)
                map[n] = [dim, unit];
        };
        add("length", "mm", ["mm", "millimeter", "millimeters", "millimetre", "millimetres"]);
        add("length", "cm", ["cm", "centimeter", "centimeters", "centimetre", "centimetres"]);
        add("length", "dm", ["dm", "decimeter", "decimeters"]);
        add("length", "m", ["m", "meter", "meters", "metre", "metres", "méter"]);
        add("length", "km", ["km", "kms", "kilometer", "kilometers", "kilometre", "kilometres"]);
        add("length", "µm", ["µm", "um", "micron", "microns", "micrometer", "micrometers"]);
        add("length", "in", ["in", "inch", "inches", "\""]);
        add("length", "ft", ["feet", "foot", "'"]); // "ft" is forints
        add("length", "yd", ["yd", "yard", "yards"]);
        add("length", "mi", ["mi", "mile", "miles"]);
        add("length", "nmi", ["nmi", "nautical mile", "nautical miles"]);
        add("mass", "mg", ["mg", "milligram", "milligrams"]);
        add("mass", "g", ["g", "gram", "grams", "gramm"]);
        add("mass", "kg", ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"]);
        add("mass", "t", ["t", "ton", "tons", "tonne", "tonnes"]);
        add("mass", "oz", ["oz", "ounce", "ounces"]);
        add("mass", "lb", ["lb", "lbs", "pound", "pounds"]);
        add("mass", "st", ["st", "stone", "stones"]);
        add("volume", "ml", ["ml", "milliliter", "milliliters", "millilitre", "millilitres"]);
        add("volume", "cl", ["cl", "centiliter", "centiliters"]);
        add("volume", "dl", ["dl", "deciliter", "deciliters"]);
        add("volume", "l", ["l", "liter", "liters", "litre", "litres"]);
        add("volume", "m3", ["m3", "m³", "cubic meter", "cubic meters"]);
        add("volume", "tsp", ["tsp", "teaspoon", "teaspoons"]);
        add("volume", "tbsp", ["tbsp", "tablespoon", "tablespoons"]);
        add("volume", "floz", ["floz", "fl oz", "fluid ounce", "fluid ounces"]);
        add("volume", "cup", ["cup", "cups"]);
        add("volume", "pt", ["pt", "pint", "pints"]);
        add("volume", "qt", ["qt", "quart", "quarts"]);
        add("volume", "gal", ["gal", "gallon", "gallons"]);
        add("time", "ms", ["ms", "millisecond", "milliseconds"]);
        add("time", "s", ["s", "sec", "secs", "second", "seconds", "mp"]);
        add("time", "min", ["min", "mins", "minute", "minutes", "perc"]);
        add("time", "h", ["h", "hr", "hrs", "hour", "hours", "óra"]);
        add("time", "d", ["d", "day", "days", "nap"]);
        add("time", "wk", ["wk", "wks", "week", "weeks", "hét"]);
        add("time", "mo", ["mo", "month", "months", "hónap"]);
        add("time", "yr", ["yr", "yrs", "year", "years", "év"]);
        add("speed", "m/s", ["m/s", "mps"]);
        add("speed", "km/h", ["km/h", "kmh", "kph", "kmph"]);
        add("speed", "mph", ["mph"]);
        add("speed", "kn", ["kn", "knot", "knots"]);
        add("data", "bit", ["bit", "bits"]);
        add("data", "B", ["b", "byte", "bytes"]);
        add("data", "KB", ["kb", "kilobyte", "kilobytes"]);
        add("data", "MB", ["mb", "megabyte", "megabytes"]);
        add("data", "GB", ["gb", "gigabyte", "gigabytes"]);
        add("data", "TB", ["tb", "terabyte", "terabytes"]);
        add("data", "KiB", ["kib", "kibibyte", "kibibytes"]);
        add("data", "MiB", ["mib", "mebibyte", "mebibytes"]);
        add("data", "GiB", ["gib", "gibibyte", "gibibytes"]);
        add("data", "TiB", ["tib", "tebibyte", "tebibytes"]);
        add("area", "mm²", ["mm2", "mm²"]);
        add("area", "cm²", ["cm2", "cm²"]);
        add("area", "m²", ["m2", "m²", "sqm", "square meter", "square meters"]);
        add("area", "km²", ["km2", "km²"]);
        add("area", "ha", ["ha", "hectare", "hectares"]);
        add("area", "acre", ["acre", "acres"]);
        add("area", "ft²", ["ft2", "ft²", "sqft", "square foot", "square feet"]);
        add("area", "in²", ["in2", "in²"]);
        add("energy", "J", ["j", "joule", "joules"]);
        add("energy", "kJ", ["kj", "kilojoule", "kilojoules"]);
        add("energy", "cal", ["cal", "calorie", "calories"]);
        add("energy", "kcal", ["kcal", "kilocalorie", "kilocalories"]);
        add("energy", "Wh", ["wh"]);
        add("energy", "kWh", ["kwh"]);
        add("temperature", "°C", ["c", "°c", "celsius", "°"]);
        add("temperature", "°F", ["f", "°f", "fahrenheit"]);
        add("temperature", "K", ["k", "kelvin"]);
        return map;
    }

    // ── Maths engine ──────────────────────────────────────────────────────
    // Recursive descent over normalised tokens; nothing goes near eval.
    //   ^ right-assoc, binds tighter than unary minus (-2^2 = -4)
    //   "a + b%" = a plus b percent of a; "a % b"/"a mod b" = modulo
    //   implicit multiplication: 2(3), 2pi, 2 sqrt 4
    //   trig in degrees; , or . decimal; 1 000 000 and 1,000,000 group
    readonly property var calcConstants: ({ pi: Math.PI, e: Math.E, tau: 2 * Math.PI, phi: (1 + Math.sqrt(5)) / 2 })
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
            .replace(/([\d)])\s*x\s*([\d(])/g, "$1 * $2")
            .replace(/(^|[^a-z0-9_])x(?=[^a-z0-9_]|$)/g, (m, p) => root.vars.x !== undefined ? m : p + " * ");
    }

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
            } else if ((match = rest.match(/^0x[0-9a-f]+|^0b[01]+|^0o[0-7]+/))) {
                const body = match[0].slice(2);
                const radix = ({ x: 16, b: 2, o: 8 })[match[0][1]];
                tokens.push({ type: "number", value: parseInt(body, radix) });
                i += match[0].length;
            } else if ((match = rest.match(/^\d{1,3}(?: \d{3})+(?:[.,]\d+)?(?![\d.,])/)) || (match = rest.match(/^\d+(?:[.,]\d+)?e[+-]?\d+(?![\d.,])/)) || (match = rest.match(/^(?:\d+(?:[.,]\d+)*|[.,]\d+)/))) {
                const value = root.parseNumberToken(match[0]);
                if (!isFinite(value))
                    return null;
                tokens.push({ type: "number", value: value });
                i += match[0].length;
            } else if ((match = rest.match(/^[a-z_][a-z0-9_]*/))) {
                const word = match[0];
                if (word === "mod")
                    tokens.push({ type: "op", value: "mod" });
                else if (word === "ans") {
                    if (!root.hasAns)
                        return null;
                    tokens.push({ type: "const", value: root.ans });
                } else if (word in root.vars)
                    tokens.push({ type: "const", value: root.vars[word] });
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
        const isOp = value => pos < tokens.length && tokens[pos].type === "op" && tokens[pos].value === value;
        const take = () => tokens[pos++];
        const startsOperand = token => token !== undefined && (token.type === "number" || token.type === "const" || token.type === "func" || (token.type === "op" && token.value === "("));
        const fail = () => {
            throw new Error("parse");
        };

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
                    op = "*";
                else if (peek() !== undefined && peek().type === "number" && tokens[pos - 1].type === "op" && tokens[pos - 1].value === ")")
                    op = "*";
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

    // ── Formatting ────────────────────────────────────────────────────────
    function group(integerText) {
        const sign = integerText.startsWith("-") ? "-" : "";
        let digits = sign ? integerText.slice(1) : integerText;
        if (digits.length <= 4)
            return sign + digits;
        let out = "";
        while (digits.length > 3) {
            out = " " + digits.slice(-3) + out;
            digits = digits.slice(0, -3);
        }
        return sign + digits + out;
    }

    // 12 significant digits hide float noise (0.1 + 0.2 → 0.3).
    function plain(value) {
        if (Number.isInteger(value) && Math.abs(value) < 1e21)
            return String(value === 0 ? 0 : value);
        const rounded = Number(value.toPrecision(12));
        return String(rounded === 0 ? 0 : rounded);
    }

    function pretty(value) {
        const text = root.plain(value);
        if (text.indexOf("e") >= 0)
            return text.replace(/e\+?(-?\d+)$/, " × 10^$1");
        const parts = text.split(".");
        return root.group(parts[0]) + (parts.length > 1 ? "." + parts[1] : "");
    }

    function money(value) {
        const abs = Math.abs(value);
        let text = abs >= 1 ? value.toFixed(2) : Number(value.toPrecision(4)).toString();
        if (text.indexOf("e") >= 0)
            return text;
        text = text.replace(/\.?0+$/, "");
        const parts = text.split(".");
        return root.group(parts[0]) + (parts.length > 1 ? "." + parts[1] : "");
    }

    function short(value) {
        const abs = Math.abs(value);
        if (abs !== 0 && (abs < 0.001 || abs >= 1e12))
            return value.toExponential(3).replace(/e\+?(-?\d+)$/, " × 10^$1");
        return root.pretty(Number(value.toPrecision(abs >= 1 ? 6 : 4)));
    }

    // Closest simple fraction, if one is (nearly) exact: 0.75 → 3/4.
    function fraction(value) {
        if (Number.isInteger(value) || Math.abs(value) > 1e6)
            return "";
        const sign = value < 0 ? "-" : "";
        const x = Math.abs(value);
        for (let d = 2; d <= 1000; d++) {
            const n = Math.round(x * d);
            if (Math.abs(n / d - x) < 1e-9) {
                const whole = Math.floor(n / d);
                const rest = n % d;
                return sign + n + "/" + d + (whole > 0 ? "  (" + sign + whole + " " + rest + "/" + d + ")" : "");
            }
        }
        return "";
    }

    function numberAlts(value) {
        const alts = [];
        const f = root.fraction(value);
        if (f !== "")
            alts.push({ label: "fraction", text: f });
        if (Number.isInteger(value) && Math.abs(value) < 2 ** 53 && Math.abs(value) >= 16) {
            const hex = (value < 0 ? "-0x" : "0x") + Math.abs(value).toString(16).toUpperCase();
            alts.push({ label: "hex", text: hex });
            if (Math.abs(value) < 65536)
                alts.push({ label: "bin", text: (value < 0 ? "-0b" : "0b") + Math.abs(value).toString(2) });
        }
        const abs = Math.abs(value);
        if (abs >= 1e6 || (abs > 0 && abs < 1e-3))
            alts.push({ label: "sci", text: value.toExponential(4) });
        if (!Number.isInteger(value) && abs < 1e6)
            alts.push({ label: "rounded", text: root.pretty(Math.round(value * 100) / 100) });
        return alts;
    }

    // ── Currency ──────────────────────────────────────────────────────────
    function currencyCode(word) {
        if (word in root.currencyAliases)
            return root.currencyAliases[word];
        if (/^[a-z]{3}$/.test(word) && word in root.rates && !(word in root.calcFunctions) && word !== "mod" && word !== "ans" && !(word in root.vars))
            return word;
        return null;
    }

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

    function currencyResult(raw) {
        const c = root.parseCurrency(raw);
        if (!c)
            return null;
        const amount = c.amountText === "" ? 1 : root.evaluate(c.amountText);
        const F = c.from.toUpperCase();
        const T = c.to.toUpperCase();
        if (Object.keys(root.rates).length === 0)
            return { kind: "currency", error: root.ratesFetching ? "Fetching exchange rates…" : "Exchange rates unavailable (offline?)" };
        if (!(c.from in root.rates) || !(c.to in root.rates))
            return { kind: "currency", error: "Unknown currency" };
        if (amount === null)
            return null;
        const rate = root.rates[c.to] / root.rates[c.from];
        const value = amount * rate;
        const alts = [
            { label: "rate", text: "1 " + F + " = " + root.money(rate) + " " + T },
            { label: "back", text: "1 " + T + " = " + root.money(1 / rate) + " " + F }
        ];
        for (const code of ["eur", "usd", "huf", "gbp"])
            if (code !== c.from && code !== c.to && code in root.rates && alts.length < 4)
                alts.push({ label: code.toUpperCase(), text: root.money(amount * root.rates[code] / root.rates[c.from]) + " " + code.toUpperCase() });
        return { kind: "currency", value: value, text: root.money(value) + " " + T, copy: value.toFixed(2), label: root.money(amount) + " " + F + (root.ratesDate ? "  ·  rates " + root.ratesDate : ""), alts: alts };
    }

    // ── Units ─────────────────────────────────────────────────────────────
    function unitOf(word) {
        return root.unitAliases[word.toLowerCase()] || null;
    }

    function toBase(dim, unit, value) {
        if (dim === "temperature")
            return unit === "°F" ? (value - 32) * 5 / 9 : (unit === "K" ? value - 273.15 : value);
        return value * root.unitTable[dim].units[unit];
    }

    function fromBase(dim, unit, value) {
        if (dim === "temperature")
            return unit === "°F" ? value * 9 / 5 + 32 : (unit === "K" ? value + 273.15 : value);
        return value / root.unitTable[dim].units[unit];
    }

    function unitResult(raw) {
        const text = raw.trim();
        const unitPattern = "((?:fl oz|nautical miles?|square (?:meters?|feet|foot)|cubic meters?)|[a-zµ°²³/\"'][a-z0-9µ°²³/]*)";
        let m = new RegExp("^(.*?)\\s*" + unitPattern + "\\s+(?:to|in|into|as|->|→)\\s+" + unitPattern + "\\s*$", "i").exec(text);
        let from = null;
        let to = null;
        let amountText;
        if (m) {
            from = root.unitOf(m[2]);
            to = root.unitOf(m[3]);
            amountText = m[1];
            if (!from || !to)
                return null;
            if (from[0] !== to[0])
                return { kind: "units", error: "Can't convert " + root.unitTable[from[0]].base + " (" + from[0] + ") to " + root.unitTable[to[0]].base + " (" + to[0] + ")" };
        } else {
            m = new RegExp("^(.*?[\\d)])\\s*" + unitPattern + "\\s*$", "i").exec(text);
            if (!m)
                return null;
            from = root.unitOf(m[2]);
            if (!from)
                return null;
            amountText = m[1];
            to = [from[0], root.unitTable[from[0]].pairs[from[1]]];
        }
        const amount = amountText.trim() === "" ? 1 : root.evaluate(amountText);
        if (amount === null)
            return null;
        const dim = from[0];
        const base = root.toBase(dim, from[1], amount);
        const value = root.fromBase(dim, to[1], base);
        const alts = [];
        for (const unit of Object.keys(root.unitTable[dim].units)) {
            if (unit === from[1] || unit === to[1])
                continue;
            const v = root.fromBase(dim, unit, base);
            const a = Math.abs(v);
            if (dim === "temperature" || (a >= 0.01 && a < 100000))
                alts.push({ label: unit, text: root.short(v) + " " + unit, score: dim === "temperature" ? 0 : Math.abs(Math.log10(a || 1) - 1.5) });
        }
        alts.sort((a, b) => a.score - b.score);
        return { kind: "units", value: value, text: root.short(value) + " " + to[1], copy: root.plain(Number(value.toPrecision(10))), label: root.short(amount) + " " + from[1] + "  ·  " + dim, alts: alts.slice(0, 4) };
    }

    // ── Bases ─────────────────────────────────────────────────────────────
    function baseResult(raw) {
        const m = /^(.+?)\s+(?:to|in|as|->|→)\s+(hex|hexadecimal|bin|binary|oct|octal|dec|decimal)\s*$/i.exec(raw.trim());
        if (!m)
            return null;
        const value = root.evaluate(m[1]);
        if (value === null)
            return null;
        if (!Number.isInteger(value))
            return { kind: "base", error: "Only whole numbers convert to other bases" };
        const kind = m[2].toLowerCase().slice(0, 3);
        const abs = Math.abs(value);
        const sign = value < 0 ? "-" : "";
        const forms = { hex: sign + "0x" + abs.toString(16).toUpperCase(), bin: sign + "0b" + abs.toString(2).replace(/\B(?=(\d{4})+(?!\d))/g, " "), oct: sign + "0o" + abs.toString(8), dec: root.pretty(value) };
        const alts = Object.keys(forms).filter(k => k !== kind).map(k => ({ label: k, text: forms[k] }));
        return { kind: "base", value: value, text: forms[kind], copy: forms[kind].replace(/ /g, ""), label: root.pretty(value) + " in " + ({ hex: "hexadecimal", bin: "binary", oct: "octal", dec: "decimal" })[kind], alts: alts };
    }

    // ── Dates ─────────────────────────────────────────────────────────────
    readonly property var monthWords: ({ jan: 0, feb: 1, mar: 2, "már": 2, apr: 3, "ápr": 3, may: 4, "máj": 4, jun: 5, "jún": 5, jul: 6, "júl": 6, aug: 7, sep: 8, sze: 8, oct: 9, okt: 9, nov: 10, dec: 11 })

    function today() {
        const d = new Date();
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function parseDate(text) {
        const t = text.trim().toLowerCase();
        const base = root.today();
        if (t === "today" || t === "ma" || t === "now")
            return base;
        if (t === "tomorrow" || t === "holnap")
            return new Date(base.getFullYear(), base.getMonth(), base.getDate() + 1);
        if (t === "yesterday" || t === "tegnap")
            return new Date(base.getFullYear(), base.getMonth(), base.getDate() - 1);
        const future = (month, day) => {
            let d = new Date(base.getFullYear(), month, day);
            if (d < base)
                d = new Date(base.getFullYear() + 1, month, day);
            return d;
        };
        if (/^(xmas|christmas|karácsony)$/.test(t))
            return future(11, 25);
        if (/^(new year|new year's|újév)$/.test(t))
            return future(0, 1);
        let m;
        if ((m = /^(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})\.?$/.exec(t)))
            return new Date(+m[1], +m[2] - 1, +m[3]);
        if ((m = /^(\d{1,2})[.\-/](\d{1,2})\.?$/.exec(t)))
            return future(+m[1] - 1, +m[2]);
        if ((m = /^([a-záéíóöőúüű]+)\.?\s+(\d{1,2})(?:st|nd|rd|th|\.)?(?:,?\s*(\d{4}))?$/.exec(t)) || (m = /^(\d{1,2})\.?\s+([a-záéíóöőúüű]+)\.?(?:\s+(\d{4}))?$/.exec(t))) {
            const word = isNaN(+m[1]) ? m[1] : m[2];
            const day = isNaN(+m[1]) ? +m[2] : +m[1];
            const key = Object.keys(root.monthWords).find(k => word.startsWith(k));
            if (key === undefined)
                return null;
            return m[3] ? new Date(+m[3], root.monthWords[key], day) : future(root.monthWords[key], day);
        }
        return null;
    }

    function dateText(d) {
        return Qt.formatDate(d, "ddd, d MMM yyyy");
    }

    function daysBetween(a, b) {
        return Math.round((b.getTime() - a.getTime()) / 86400000);
    }

    function spanText(days) {
        const abs = Math.abs(days);
        const parts = [];
        if (abs >= 7)
            parts.push(Math.floor(abs / 7) + " weeks" + (abs % 7 ? " " + abs % 7 + " days" : ""));
        if (abs >= 60)
            parts.push("≈ " + (abs / 30.44).toFixed(1) + " months");
        if (abs >= 365)
            parts.push("≈ " + (abs / 365.25).toFixed(2) + " years");
        return parts;
    }

    function dateResult(raw) {
        const t = raw.trim().toLowerCase();
        let m;
        if ((m = /^(?:how many\s+)?days?\s+(until|till|to|since|from)\s+(.+)$/.exec(t))) {
            const target = root.parseDate(m[2]);
            if (!target)
                return null;
            const days = root.daysBetween(root.today(), target);
            const since = m[1] === "since" || m[1] === "from";
            const value = since ? -days : days;
            return { kind: "date", value: value, text: value + (Math.abs(value) === 1 ? " day" : " days"), copy: String(value), label: (since ? "since " : "until ") + root.dateText(target), alts: root.spanText(value).map(s => ({ label: "", text: s })).concat([{ label: "weekday", text: Qt.formatDate(target, "dddd") }]) };
        }
        if ((m = /^(.+?)\s*([+-])\s*(\d+)\s*(days?|d|weeks?|w|wk|months?|mo|years?|yr|y|nap|hét|hónap|év)$/.exec(t))) {
            const start = root.parseDate(m[1]);
            if (!start)
                return null;
            const n = (m[2] === "-" ? -1 : 1) * parseInt(m[3], 10);
            const unit = m[4];
            const d = new Date(start);
            if (/^(w|wk|weeks?|hét)$/.test(unit))
                d.setDate(d.getDate() + n * 7);
            else if (/^(mo|months?|hónap)$/.test(unit))
                d.setMonth(d.getMonth() + n);
            else if (/^(y|yr|years?|év)$/.test(unit))
                d.setFullYear(d.getFullYear() + n);
            else
                d.setDate(d.getDate() + n);
            const days = root.daysBetween(root.today(), d);
            return { kind: "date", value: days, text: root.dateText(d), copy: Qt.formatDate(d, "yyyy-MM-dd"), label: raw.trim(), alts: [{ label: "", text: days === 0 ? "today" : (days > 0 ? "in " + days + " days" : -days + " days ago") }, { label: "ISO", text: Qt.formatDate(d, "yyyy-MM-dd") }, { label: "week", text: "week " + root.isoWeek(d) }] };
        }
        // A date on its own only when it can't be maths: it has a word in it
        // ("dec 24", "today") or is a full yyyy.mm.dd.
        const single = /[a-záéíóöőúüű]/.test(t) || /^\d{4}[.\-/]\d{1,2}[.\-/]\d{1,2}\.?$/.test(t) ? root.parseDate(t) : null;
        if (single) {
            const days = root.daysBetween(root.today(), single);
            return { kind: "date", value: days, text: root.dateText(single), copy: Qt.formatDate(single, "yyyy-MM-dd"), label: days === 0 ? "today" : (days > 0 ? "in " + days + " days" : -days + " days ago"), alts: [{ label: "weekday", text: Qt.formatDate(single, "dddd") }, { label: "week", text: "week " + root.isoWeek(single) }] };
        }
        return null;
    }

    function isoWeek(d) {
        const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = date.getUTCDay() || 7;
        date.setUTCDate(date.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
        return Math.ceil(((date - yearStart) / 86400000 + 1) / 7);
    }

    // ── Analyse the input ─────────────────────────────────────────────────
    function analyse(raw) {
        let text = raw.trim();
        if (text === "")
            return null;

        // Chaining: an operator first means "carry on from ans".
        if (root.hasAns && /^[+*/^×÷·%]/.test(text) && !/^%\s*of/.test(text))
            text = "ans " + text;

        // Assignment: name = expression
        const assign = /^([a-z_][a-z0-9_]*)\s*=\s*(.+)$/i.exec(text);
        if (assign && !(assign[1].toLowerCase() in root.calcFunctions) && !(assign[1].toLowerCase() in root.calcConstants) && assign[1].toLowerCase() !== "ans") {
            const value = root.evaluate(assign[2]);
            if (value === null)
                return null;
            return { kind: "var", value: value, text: root.pretty(value), copy: root.plain(value), label: assign[1].toLowerCase() + " = …  ·  Enter stores it", name: assign[1].toLowerCase(), alts: root.numberAlts(value) };
        }

        const staged = [root.dateResult, root.baseResult, root.unitResult, root.currencyResult];
        for (const stage of staged) {
            const r = stage(text);
            if (r)
                return r;
        }

        const value = root.evaluate(text);
        if (value === null)
            return null;
        return { kind: "math", value: value, text: root.pretty(value), copy: root.plain(value), label: "", alts: root.numberAlts(value) };
    }

    function recompute() {
        const r = root.analyse(root.expr);
        const changed = !root.result || !r || r.text !== root.result.text;
        root.result = r;
        if (r && !r.error && changed)
            resultPop.restart();
    }

    onExprChanged: root.recompute()
    onRatesChanged: root.recompute()

    // ── Actions ───────────────────────────────────────────────────────────
    function commit() {
        const r = root.result;
        if (!r || r.error) {
            if (root.expr.trim() !== "")
                shake.restart();
            return;
        }
        if (r.kind === "var") {
            const vars = Object.assign({}, root.vars);
            vars[r.name] = r.value;
            root.vars = vars;
        }
        if (typeof r.value === "number" && isFinite(r.value)) {
            root.ans = r.value;
            root.hasAns = true;
        }
        const entry = { expr: root.expr.trim(), text: r.text, copy: r.copy, kind: r.kind };
        root.history = [entry].concat(root.history.filter(h => h.expr !== entry.expr)).slice(0, 60);
        root.save();
        root.recallIndex = -1;
        historyList.positionViewAtBeginning();
        input.text = "";
        root.expr = "";
    }

    function useResult() {
        if (root.result && !root.result.error) {
            input.text = root.result.copy;
            root.expr = input.text;
            input.cursorPosition = input.text.length;
        }
    }

    function recall(delta) {
        if (root.history.length === 0)
            return;
        const next = Math.max(-1, Math.min(root.history.length - 1, root.recallIndex + delta));
        root.recallIndex = next;
        input.text = next < 0 ? "" : root.history[next].expr;
        root.expr = input.text;
        input.cursorPosition = input.text.length;
        if (next >= 0)
            historyList.positionViewAtIndex(next, ListView.Contain);
    }

    function copy(text, what) {
        if (!text)
            return;
        Quickshell.execDetached(["wl-copy", text]);
        root.showToast("Copied " + (what || text));
    }

    function insert(text) {
        const pos = input.cursorPosition;
        input.text = input.text.slice(0, pos) + text + input.text.slice(pos);
        root.expr = input.text;
        input.cursorPosition = pos + text.length;
        input.forceActiveFocus();
    }

    function clearHistory() {
        root.history = [];
        root.vars = ({});
        root.hasAns = false;
        root.save();
        root.showToast("History and variables cleared");
    }

    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    // ── Persistence ───────────────────────────────────────────────────────
    readonly property string historyPath: Quickshell.env("HOME") + "/.local/share/dynamic-glacier/calc-history.json"
    property bool loaded: false

    function save() {
        if (root.loaded)
            saveTimer.restart();
    }

    FileView {
        id: historyFile

        path: root.historyPath
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(historyFile.text());
                root.history = Array.isArray(data.history) ? data.history.filter(h => h && typeof h.expr === "string") : [];
                root.vars = data.vars && typeof data.vars === "object" ? data.vars : {};
                if (typeof data.ans === "number") {
                    root.ans = data.ans;
                    root.hasAns = true;
                }
            } catch (error) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: historyFile.setText(JSON.stringify({ ans: root.hasAns ? root.ans : null, vars: root.vars, history: root.history }, null, 2) + "\n")
    }

    // Rates: the script is a no-op while the cache is under 12 h old.
    function refreshRates() {
        if (ratesFetch.running)
            return;
        root.ratesFetching = true;
        ratesFetch.running = true;
    }

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
        preload: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(ratesFile.text());
                if (data && data.eur && typeof data.eur === "object") {
                    root.ratesDate = data.date || "";
                    root.rates = data.eur;
                }
            } catch (error) {}
        }
    }

    Timer {
        id: toastTimer

        interval: 2000
        onTriggered: root.toast = ""
    }

    opacity: root.panelProgress
    visible: opacity > 0.001
    scale: 0.94 + 0.06 * root.panelProgress
    transformOrigin: Item.Top

    // Keyboard focus goes to the text field once the island has finished
    // opening. Taken mid-morph, Hyprland held back the surface's frame
    // callbacks for ~300 ms and the opening animation froze halfway.
    Timer {
        id: focusAfterOpen

        interval: 360
        onTriggered: {
            if (!root.visible)
                return;
            input.forceActiveFocus();
            if (root.typedEarly !== "") {
                input.insert(input.cursorPosition, root.typedEarly);
                root.typedEarly = "";
                input.textEdited();
            }
        }
    }

    // Until then the panel itself holds the keyboard: what's typed in the
    // first moments is kept and handed to the field, and Esc still closes.
    property string typedEarly: ""

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            root.typedEarly += event.text;
            event.accepted = true;
        }
    }

    onVisibleChanged: {
        if (root.visible) {
            input.text = "";
            root.expr = "";
            root.recallIndex = -1;
            root.typedEarly = "";
            root.forceActiveFocus();
            focusAfterOpen.restart();
            root.refreshRates();
        }
    }

    // ── Components ────────────────────────────────────────────────────────

    component IconButton: Rectangle {
        id: iconButton

        required property string icon

        signal clicked

        width: 26
        height: 26
        radius: 9
        color: iconHover.hovered ? "#1a1a1a" : "#0a0a0a"
        border.width: 1
        border.color: "#232323"
        scale: iconMouse.pressed ? 0.88 : (iconHover.hovered ? 1.08 : 1)

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

        HoverHandler {
            id: iconHover

            cursorShape: Qt.PointingHandCursor
        }

        MIcon {
            anchors.centerIn: parent
            name: iconButton.icon
            size: 14
            color: "#a8a8a8"
        }

        MouseArea {
            id: iconMouse

            anchors.fill: parent
            onClicked: iconButton.clicked()
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panelPadding
        spacing: root.sectionSpacing

        // Header
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
                    name: "calculate"
                    size: 17
                    color: root.result && !root.result.error ? root.kindColors[root.result.kind] : root.primaryText

                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "Calculator"
                    color: root.primaryText
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const parts = [];
                        if (root.hasAns)
                            parts.push("ans = " + root.short(root.ans));
                        for (const name of Object.keys(root.vars).slice(0, 4))
                            parts.push(name + " = " + root.short(root.vars[name]));
                        return parts.length > 0 ? parts.join("   ") : "Maths · currency · units · bases · dates";
                    }
                    color: root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.features: { "tnum": 1 }
                }
            }

            IconButton {
                icon: "content_copy"
                onClicked: root.copy(root.result && !root.result.error ? root.result.copy : "", root.result ? root.result.text : "")
            }

            IconButton {
                icon: "delete_sweep"
                onClicked: root.clearHistory()
            }

            IconButton {
                icon: "close"
                onClicked: root.closeRequested()
            }
        }

        // Input
        Rectangle {
            id: inputBox

            readonly property color tint: root.result && root.result.error ? root.errorColor : (root.result ? root.kindColors[root.result.kind] : "#2a2a2a")

            Layout.fillWidth: true
            Layout.preferredHeight: root.inputHeight
            radius: 14
            color: "#0a0a0a"
            border.width: 1
            border.color: root.expr === "" ? "#1f1f1f" : Qt.rgba(inputBox.tint.r, inputBox.tint.g, inputBox.tint.b, 0.6)

            Behavior on border.color { ColorAnimation { duration: 180 } }

            transform: Translate {
                id: shakeShift
            }

            SequentialAnimation {
                id: shake

                NumberAnimation { target: shakeShift; property: "x"; to: 8; duration: 50 }
                NumberAnimation { target: shakeShift; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: shakeShift; property: "x"; to: 4; duration: 60 }
                NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 70 }
            }

            Text {
                id: prompt

                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: root.hasAns && /^[+*/^×÷·%]/.test(root.expr.trim()) ? "ans" : "›"
                color: root.hasAns && /^[+*/^×÷·%]/.test(root.expr.trim()) ? root.accentColor : "#4a4a4a"
                font.family: root.fontFamily
                font.pixelSize: 18
                font.weight: Font.Bold
            }

            TextInput {
                id: input

                anchors.left: prompt.right
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: root.primaryText
                selectionColor: "#2f4f3a"
                selectByMouse: true
                clip: true
                font.family: root.fontFamily
                font.pixelSize: 17
                font.weight: Font.DemiBold
                onTextEdited: {
                    root.recallIndex = -1;
                    root.expr = text;
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const key = event.key;
                    if (key === Qt.Key_Return || key === Qt.Key_Enter)
                        root.commit();
                    else if (key === Qt.Key_Tab)
                        root.useResult();
                    else if (key === Qt.Key_Up)
                        root.recall(1);
                    else if (key === Qt.Key_Down)
                        root.recall(-1);
                    else if (ctrl && key === Qt.Key_C && input.selectedText === "")
                        root.copy(root.result && !root.result.error ? root.result.copy : "", root.result ? root.result.text : "");
                    else if (ctrl && key === Qt.Key_L)
                        root.clearHistory();
                    else if (key === Qt.Key_Escape) {
                        if (input.text !== "") {
                            input.text = "";
                            root.expr = "";
                            root.recallIndex = -1;
                        } else {
                            root.closeRequested();
                        }
                    } else
                        return;
                    event.accepted = true;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    width: input.width
                    elide: Text.ElideRight
                    text: root.hasAns ? "Type, or start with + − × ÷ to use " + root.short(root.ans) : "12 × 12  ·  100 usd to huf  ·  5 km to mi  ·  days until xmas"
                    color: "#4a4a4a"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                }
            }
        }

        // Result
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.resultHeight

            // Kind badge + what was understood
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.4
                spacing: 3
                opacity: root.result ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 160 } }

                Rectangle {
                    width: kindText.implicitWidth + 12
                    height: 18
                    radius: 6
                    color: root.result ? Qt.rgba(inputBox.tint.r, inputBox.tint.g, inputBox.tint.b, 0.15) : "transparent"

                    Text {
                        id: kindText

                        anchors.centerIn: parent
                        text: root.result ? (root.result.error ? "HMM" : ({ math: "MATH", currency: "CURRENCY", units: "UNITS", base: "BASES", date: "DATE", var: "VARIABLE" })[root.result.kind]) : ""
                        color: inputBox.tint
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Black
                        font.letterSpacing: 1.2
                    }
                }

                Text {
                    width: parent.width
                    text: root.result ? (root.result.error || root.result.label || "") : ""
                    color: root.result && root.result.error ? root.errorColor : root.secondaryText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }

            Text {
                id: resultText

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.62
                horizontalAlignment: Text.AlignRight
                text: root.result && !root.result.error ? "= " + root.result.text : (root.expr === "" ? "" : "…")
                color: root.result && !root.result.error ? root.primaryText : "#3a3a3a"
                elide: Text.ElideLeft
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 16
                font.family: root.fontFamily
                font.pixelSize: 32
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                transformOrigin: Item.Right

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.copy(root.result && !root.result.error ? root.result.copy : "", root.result ? root.result.text : "")
                }
            }

            SequentialAnimation {
                id: resultPop

                NumberAnimation { target: resultText; property: "scale"; to: 1.06; duration: 80; easing.type: Easing.OutCubic }
                NumberAnimation { target: resultText; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
        }

        // Other forms of the result
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.altsHeight
            clip: true

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                opacity: root.result && !root.result.error ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 160 } }

                Repeater {
                    model: root.result && !root.result.error ? (root.result.alts || []) : []

                    Rectangle {
                        id: alt

                        required property var modelData

                        width: altRow.implicitWidth + 16
                        height: 22
                        radius: 7
                        color: altHover.hovered ? "#171717" : "#0d0d0d"
                        border.width: 1
                        border.color: altHover.hovered ? "#2c2c2c" : "#1c1c1c"
                        scale: altMouse.pressed ? 0.92 : 1

                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }

                        HoverHandler {
                            id: altHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        Row {
                            id: altRow

                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                visible: alt.modelData.label !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: alt.modelData.label
                                color: root.faintText
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Black
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: alt.modelData.text
                                color: altHover.hovered ? root.primaryText : "#b0b0b0"
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }

                        MouseArea {
                            id: altMouse

                            anchors.fill: parent
                            onClicked: {
                                root.copy(alt.modelData.text.replace(/ /g, "").replace(/\s*\(.*\)$/, ""), alt.modelData.text);
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // History
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.historyHeight
            radius: 14
            color: root.cardColor
            border.width: 1
            border.color: root.cardBorder
            clip: true

            Column {
                anchors.centerIn: parent
                spacing: 5
                visible: root.history.length === 0

                MIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "history"
                    size: 22
                    color: "#333333"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Press Enter to keep a result here"
                    color: "#555555"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            ListView {
                id: historyList

                anchors.fill: parent
                anchors.margins: 5
                model: root.history
                boundsBehavior: Flickable.StopAtBounds
                spacing: 1

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                }

                delegate: Rectangle {
                    id: historyRow

                    required property var modelData
                    required property int index

                    readonly property bool recalled: root.recallIndex === index
                    readonly property color tint: root.kindColors[modelData.kind] || root.accentColor

                    width: historyList.width
                    height: 30
                    radius: 9
                    color: historyRow.recalled ? "#161616" : (rowHover.hovered ? "#0f0f0f" : "transparent")
                    border.width: historyRow.recalled ? 1 : 0
                    border.color: "#2a2a2a"

                    HoverHandler {
                        id: rowHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 4
                            Layout.preferredHeight: 4
                            radius: 2
                            color: historyRow.tint
                        }

                        Text {
                            Layout.fillWidth: true
                            text: historyRow.modelData.expr
                            color: "#8a8a8a"
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }

                        Text {
                            Layout.maximumWidth: historyList.width * 0.5
                            text: "= " + historyRow.modelData.text
                            color: root.primaryText
                            elide: Text.ElideLeft
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        MIcon {
                            visible: rowHover.hovered
                            name: "content_copy"
                            size: 12
                            color: "#7a7a7a"
                        }
                    }

                    // Click: drop the result into the input at the cursor.
                    // Middle-click: copy it. Right-click: edit the expression.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.MiddleButton)
                                root.copy(historyRow.modelData.copy, historyRow.modelData.text);
                            else if (mouse.button === Qt.RightButton) {
                                input.text = historyRow.modelData.expr;
                                root.expr = input.text;
                                input.forceActiveFocus();
                            } else
                                root.insert(historyRow.modelData.copy);
                        }
                    }
                }
            }
        }

        // Hint / toast
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: root.hintHeight
            horizontalAlignment: Text.AlignHCenter
            text: root.toast !== "" ? root.toast : "Enter keep  ·  Tab use result  ·  ↑↓ history  ·  Ctrl+C copy  ·  click a result to insert it"
            color: root.toast !== "" ? root.accentColor : root.faintText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
