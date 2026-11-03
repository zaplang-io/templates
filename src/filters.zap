import math
import templates.values

def signature(str name) -> list[str]:
    if name in ["escape", "e", "safe", "upper", "lower", "title", "length", "count", "first", "last", "reverse", "list", "string", "abs"]:
        return []
    if name in ["default", "d"]:
        return ["default_value", "boolean"]
    if name == "trim":
        return ["chars"]
    if name == "replace":
        return ["old", "new", "count"]
    if name == "join":
        return ["d", "attribute"]
    if name == "sort":
        return ["reverse", "case_sensitive", "attribute"]
    if name == "int":
        return ["default", "base"]
    if name == "float":
        return ["default"]
    if name == "round":
        return ["precision", "method"]
    if name == "dictsort":
        return ["case_sensitive", "by", "reverse"]
    if name in ["select", "reject"]:
        return ["test", "argument"]
    if name in ["selectattr", "rejectattr"]:
        return ["attribute", "test", "argument"]
    if name == "map":
        return ["filter", "argument", "attribute", "default"]
    if name == "tojson":
        return []
    return ["!unknown"]

def test_signature(str name) -> list[str]:
    if name in ["defined", "undefined", "none", "string", "number", "sequence", "mapping", "even", "odd", "boolean", "integer", "float", "true", "false", "iterable", "escaped", "lower", "upper"]:
        return []
    if name in ["equalto", "eq", "ne", "lt", "le", "gt", "ge", "in", "divisibleby"]:
        return ["other"]
    return ["!unknown"]

def _required(str name) -> int64:
    if name == "replace":
        return 2
    if name in ["selectattr", "rejectattr"]:
        return 1
    return 0

def _validate(
    str label,
    list[str] parameters,
    list[str] names,
    int64 required,
    int64 pos,
):
    if "!unknown" in parameters:
        values.fail(pos, "unknown " + label)
    if len(names) > len(parameters):
        values.fail(pos, label + ": too many arguments")
    list[str] supplied = []
    auto named = False
    for i in range(len(names)):
        auto key = names[i]
        if key == "":
            if named:
                values.fail(pos, label + ": positional argument after keyword")
            key = parameters[i]
        else:
            named = True
        if not key in parameters:
            values.fail(pos, label + ": unknown argument " + key)
        if key in supplied:
            values.fail(pos, label + ": duplicate argument " + key)
        supplied.append(key)
    for i in range(required):
        if not parameters[i] in supplied:
            values.fail(pos, label + ": missing argument " + parameters[i])

def validate(str name, list[str] names, int64 pos):
    _validate("filter " + name, signature(name), names, _required(name), pos)

def validate_test(str name, list[str] names, int64 pos):
    auto parameters = test_signature(name)
    _validate("test " + name, parameters, names, len(parameters), pos)

def _bind(
    str name,
    list[values.Value] args,
    list[str] names,
) -> dict[str, values.Value]:
    auto parameters = signature(name)
    dict[str, values.Value] result = {}
    for i in range(len(args)):
        auto key = names[i]
        if key == "":
            key = parameters[i]
        result[key] = args[i]
    return result

def _get(dict[str, values.Value] args, str key, JsonValue fallback) -> values.Value:
    if key in args:
        return args[key]
    return values.value(fallback)

def _text(values.Value v, int64 pos, str label) -> str:
    if v.defined:
        match v.data:
            case JsonValue.Str(s):
                return s
            case _:
                values.fail(pos, label + ": expected string")
    values.fail(pos, label + ": expected defined string")
    return ""

def _bool(values.Value v, int64 pos, str label) -> bool:
    if v.defined:
        match v.data:
            case JsonValue.Bool(b):
                return b
            case _:
                values.fail(pos, label + ": expected boolean")
    values.fail(pos, label + ": expected defined boolean")
    return False

def _int(values.Value v, int64 pos, str label) -> int64:
    if v.defined:
        match v.data:
            case JsonValue.Int(i):
                return i
            case _:
                values.fail(pos, label + ": expected integer")
    values.fail(pos, label + ": expected defined integer")
    return 0

def _kind(values.Value v) -> str:
    if not v.defined:
        return "undefined"
    match v.data:
        case JsonValue.Null:
            return "none"
        case JsonValue.Bool(b):
            return "boolean"
        case JsonValue.Int(i):
            return "integer"
        case JsonValue.Float(f):
            return "float"
        case JsonValue.Str(s):
            return "string"
        case JsonValue.Array(xs):
            return "sequence"
        case JsonValue.Object(fields):
            return "mapping"

def test(
    str name,
    values.Value v,
    list[values.Value] args,
    values.Budget budget,
    int64 pos,
) -> bool:
    list[str] names = []
    for arg in args:
        names.append("")
    validate_test(name, names, pos)
    auto kind = _kind(v)
    if name == "defined":
        return v.defined
    if name == "undefined":
        return not v.defined
    # Type tests can inspect undefined without consuming it, as in Jinja.
    if name in ["none", "string", "mapping", "boolean", "integer", "float"]:
        return kind == name
    if name == "number":
        return kind in ["integer", "float", "boolean"]
    if name == "sequence":
        return kind in ["sequence", "string", "mapping"]
    if name == "iterable":
        return kind in ["sequence", "string", "mapping"]
    if name == "escaped":
        return v.safe
    if name in ["true", "false"]:
        if kind != "boolean":
            return False
        return values.truth(v) == (name == "true")
    if name in ["lower", "upper"]:
        values.require(v, budget, pos)
        auto s = values.string(v)
        auto has_case = s.lower() != s.upper()
        if name == "lower":
            return has_case and s == s.lower()
        return has_case and s == s.upper()
    if name in ["even", "odd", "divisibleby"]:
        auto n = values.number(v, pos)
        auto divisor = 2.0
        if name == "divisibleby":
            divisor = values.number(args[0], pos)
            if divisor == 0.0:
                values.fail(pos, "test divisibleby: division by zero")
        auto remainder = math.fmod(n, divisor)
        if name == "odd":
            return math.fabs(remainder) == 1.0
        return remainder == 0.0
    auto op = "=="
    if name == "ne":
        op = "!="
    elif name == "lt":
        op = "<"
    elif name == "le":
        op = "<="
    elif name == "gt":
        op = ">"
    elif name == "ge":
        op = ">="
    elif name == "in":
        op = "in"
    return values.compare(op, v, args[0], budget, pos)

def attribute(
    values.Value v,
    values.Value path,
    values.Budget budget,
    int64 pos,
) -> values.Value:
    match path.data:
        case JsonValue.Int(i):
            return values.lookup(v, path, pos, budget)
        case JsonValue.Str(s):
            auto result = v
            for part in s.split("."):
                values.tick(budget)
                auto key = values.value(JsonValue.Str(part))
                if len(part) > 0:
                    auto digits = True
                    for c in part:
                        if ord(c) < 48 or ord(c) > 57:
                            digits = False
                    if digits:
                        try:
                            key = values.value(JsonValue.Int(int(part)))
                        except Exception:
                            values.fail(pos, "attribute index out of range")
                if not result.defined:
                    return result
                result = values.lookup(result, key, pos, budget)
            return result
        case JsonValue.Null:
            return v
        case _:
            values.fail(pos, "attribute must be a string or integer")
    return values.undefined()

def _sort_key(values.Value v, bool case_sensitive) -> values.Value:
    if not case_sensitive:
        match v.data:
            case JsonValue.Str(s):
                return values.value(JsonValue.Str(s.lower()))
            case _:
                return v
    return v

# Stable bottom-up mergesort: comparisons and traversal share the render budget.
def sort(
    list[values.Value] data,
    bool reverse,
    bool case_sensitive,
    values.Value path,
    values.Budget budget,
    int64 pos,
) -> list[values.Value]:
    auto width = 1
    auto current = data
    while width < len(data):
        list[values.Value] merged = []
        auto start = 0
        while start < len(data):
            auto middle = start + width
            if middle > len(data):
                middle = len(data)
            auto end = middle + width
            if end > len(data):
                end = len(data)
            auto left = start
            auto right = middle
            while left < middle or right < end:
                values.tick(budget)
                auto take_left = right >= end
                if left < middle and right < end:
                    auto a = _sort_key(
                        attribute(current[left], path, budget, pos),
                        case_sensitive,
                    )
                    auto b = _sort_key(
                        attribute(current[right], path, budget, pos),
                        case_sensitive,
                    )
                    if reverse:
                        take_left = values.compare(">=", a, b, budget, pos)
                    else:
                        take_left = values.compare("<=", a, b, budget, pos)
                if take_left:
                    merged.append(current[left])
                    left = left + 1
                else:
                    merged.append(current[right])
                    right = right + 1
            start = end
        current = merged
        width = width * 2
    return current

def _trim(str text, values.Value chars, int64 pos) -> str:
    if _kind(chars) == "none":
        return text.strip()
    auto allowed = _text(chars, pos, "filter trim")
    auto first = 0
    auto last = values.length(text)
    while first < last and text[first:first + 1] in allowed:
        first = first + 1
    while last > first and text[last - 1:last] in allowed:
        last = last - 1
    return text[first:last]

def _replace(
    str text,
    str old,
    str replacement,
    int64 count,
    values.Budget budget,
    int64 pos,
) -> str:
    list[str] chunks = []
    auto size = values.length(text)
    auto old_size = values.length(old)
    auto offset = 0
    auto used = 0
    auto output_size = 0
    while offset <= size:
        values.tick(budget)
        auto matches = old_size == 0 or text[offset:offset + old_size] == old
        auto chunk = ""
        if matches and (count < 0 or used < count):
            chunk = replacement
            used = used + 1
            if old_size > 0:
                offset = offset + old_size
            else:
                chunk = chunk + text[offset:offset + 1]
                offset = offset + 1
        else:
            chunk = text[offset:offset + 1]
            offset = offset + 1
        output_size = output_size + values.length(chunk)
        if output_size > 1048576:
            values.fail(pos, "filter replace: output exceeds 1048576 characters")
        chunks.append(chunk)
    return "".join(chunks)

def _decimal(str text) -> bool:
    auto size = values.length(text)
    auto i = 0
    if i < size and text[i:i + 1] in ["+", "-"]:
        i = i + 1
    auto digits = 0
    while i < size and text[i:i + 1] >= "0" and text[i:i + 1] <= "9":
        i = i + 1
        digits = digits + 1
    if i < size and text[i:i + 1] == ".":
        i = i + 1
        while i < size and text[i:i + 1] >= "0" and text[i:i + 1] <= "9":
            i = i + 1
            digits = digits + 1
    if digits == 0:
        return False
    if i < size and text[i:i + 1] in ["e", "E"]:
        i = i + 1
        if i < size and text[i:i + 1] in ["+", "-"]:
            i = i + 1
        auto start = i
        while i < size and text[i:i + 1] >= "0" and text[i:i + 1] <= "9":
            i = i + 1
        if start == i:
            return False
    return i == size

def _convert(
    values.Value v,
    bool floating,
    int64 base,
    values.Value fallback,
    int64 pos,
) -> values.Value:
    auto kind = _kind(v)
    if kind == "undefined":
        values.fail(pos, "numeric conversion of undefined")
    if kind == "boolean":
        auto n = 0
        if values.truth(v):
            n = 1
        if floating:
            return values.value(JsonValue.Float(float64(n)))
        return values.value(JsonValue.Int(n))
    auto number = 0.0
    if kind == "integer" and not floating:
        return v
    if kind in ["integer", "float"]:
        number = values.number(v, pos)
    elif kind == "string":
        auto text = values.string(v).strip()
        if not floating:
            auto sign = 1
            if text.startswith("-"):
                sign = -1
                text = text[1:]
            elif text.startswith("+"):
                text = text[1:]
            if not base in [2, 8, 10, 16]:
                values.fail(pos, "filter int: base must be 2, 8, 10, or 16")
            if base == 16 and text.lower().startswith("0x") or base == 8 and text.lower().startswith("0o") or base == 2 and text.lower().startswith("0b"):
                text = text[2:]
            auto integral = len(text) > 0
            auto magnitude = 0
            for c in text.lower():
                auto digit = "0123456789abcdef".find(str(c))
                if digit < 0 or digit >= base:
                    integral = False
                    break
                if magnitude > (9223372036854775807 - digit) // base:
                    integral = False
                    break
                magnitude = magnitude * base + digit
            if integral:
                return values.value(JsonValue.Int(sign * magnitude))
            if base != 10:
                return fallback
        if not _decimal(values.string(v).strip()):
            return fallback
        try:
            number = float(values.string(v).strip())
        except Exception:
            return fallback
    else:
        return fallback
    if math.isnan(number) or math.isinf(number):
        return fallback
    if floating:
        return values.value(JsonValue.Float(number))
    if number < -9223372036854775808.0 or number >= 9223372036854775808.0:
        return fallback
    return values.value(JsonValue.Int(int64(number)))

def _round(float64 number, int64 precision, str method, int64 pos) -> float64:
    if precision < -15 or precision > 15:
        values.fail(pos, "filter round: precision must be between -15 and 15")
    if not method in ["common", "ceil", "floor"]:
        values.fail(pos, "filter round: method must be common, ceil, or floor")
    auto factor = math.pow(10.0, float64(precision))
    auto scaled = number * factor
    if math.isnan(scaled) or math.isinf(scaled):
        values.fail(pos, "filter round: non-finite result")
    auto rounded = 0.0
    if method == "ceil":
        rounded = math.ceil(scaled)
    elif method == "floor":
        rounded = math.floor(scaled)
    else:
        auto lower = math.floor(scaled)
        auto fraction = scaled - lower
        rounded = lower
        if fraction > 0.5 or fraction == 0.5 and math.fmod(lower, 2.0) != 0.0:
            rounded = lower + 1.0
    return rounded / factor

# JSON for HTML script bodies: deterministic keys and HTML-sensitive escapes.
def _json(JsonValue data, values.Budget budget, int64 pos, int64 depth = 0) -> str:
    values.tick(budget)
    if depth > 64:
        values.fail(pos, "filter tojson: value nesting exceeds 64")
    list[str] chunks = []
    auto opening = ""
    auto closing = ""
    auto size = 0
    match data:
        case JsonValue.Array(xs):
            opening = "["
            closing = "]"
            for x in xs:
                auto text = _json(x, budget, pos, depth + 1)
                size = size + values.length(text) + 2
                if size > 1048576:
                    values.fail(pos, "filter tojson: output limit")
                chunks.append(text)
        case JsonValue.Object(fields):
            opening = "{"
            closing = "}"
            list[values.Value] keys = []
            for key in fields:
                values.tick(budget)
                keys.append(values.value(JsonValue.Str(key)))
            auto ordered = sort(
                keys,
                False,
                True,
                values.value(JsonValue.Null),
                budget,
                pos,
            )
            for key in ordered:
                auto name = values.string(key)
                auto text = json.dumps(JsonValue.Str(name)) + ": " + _json(fields[name], budget, pos, depth + 1)
                size = size + values.length(text) + 2
                if size > 1048576:
                    values.fail(pos, "filter tojson: output limit")
                chunks.append(text)
        case _:
            return json.dumps(data)
    return opening + ", ".join(chunks) + closing

def apply(
    str name,
    values.Value v,
    list[values.Value] arguments,
    list[str] names,
    values.Budget budget,
    int64 pos,
) -> values.Value:
    values.tick(budget)
    validate(name, names, pos)
    auto args = _bind(name, arguments, names)
    if name in ["default", "d"]:
        auto boolean = _bool(
            _get(args, "boolean", JsonValue.Bool(False)),
            pos,
            "filter " + name,
        )
        if not v.defined or boolean and not values.truth(v):
            return _get(args, "default_value", JsonValue.Str(""))
        return v
    values.require(v, budget, pos)
    if name in ["escape", "e"]:
        return values.marked(values.fragment(v, True, pos), True)
    if name == "safe":
        return values.marked(values.string(v), True)
    if name == "string":
        return values.marked(values.string(v), v.safe)
    if name == "tojson":
        if not v.defined:
            values.fail(pos, "filter tojson: undefined value")
        auto text = _json(v.data, budget, pos).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026").replace(
            "'",
            "\\u0027",
        )
        return values.marked(text, True)
    if name in ["upper", "lower", "title", "trim", "replace"]:
        auto text = values.string(v)
        if name == "upper":
            text = text.upper()
        elif name == "lower":
            text = text.lower()
        elif name == "title":
            auto beginning = True
            auto result = ""
            for c in text:
                values.tick(budget)
                auto ch = str(c)
                if ch in ["-", " ", "\t", "\r", "\n", "(", "{", "[", "<"]:
                    beginning = True
                else:
                    if beginning:
                        ch = ch.upper()
                    else:
                        ch = ch.lower()
                    beginning = False
                result = result + ch
            text = result
        elif name == "trim":
            text = _trim(text, _get(args, "chars", JsonValue.Null), pos)
        else:
            auto old = _text(args["old"], pos, "filter replace")
            auto replacement = _text(args["new"], pos, "filter replace")
            auto count = _int(
                _get(args, "count", JsonValue.Int(-1)),
                pos,
                "filter replace",
            )
            text = _replace(text, old, replacement, count, budget, pos)
        # Conservative boundary: transformations cannot grant or retain HTML trust.
        return values.marked(text, False)
    if name in ["length", "count"]:
        if not v.defined:
            return values.value(JsonValue.Int(0))
        auto kind = _kind(v)
        auto size = 0
        match v.data:
            case JsonValue.Str(s):
                size = values.length(s)
            case JsonValue.Array(xs):
                size = len(xs)
            case JsonValue.Object(fields):
                size = len(fields)
            case _:
                values.fail(
                    pos,
                    "filter " + name + ": requires string, array, or object",
                )
        return values.value(JsonValue.Int(size))
    if name in ["int", "float"]:
        auto fallback = _get(args, "default", JsonValue.Int(0))
        if name == "float":
            fallback = _get(args, "default", JsonValue.Float(0.0))
        auto base = _int(_get(args, "base", JsonValue.Int(10)), pos, "filter int")
        return _convert(v, name == "float", base, fallback, pos)
    if name == "abs":
        auto n = values.number(v, pos)
        if n < 0.0:
            return values.arithmetic(
                "-",
                values.value(JsonValue.Int(0)),
                v,
                pos,
                budget,
            )
        return v
    if name == "round":
        auto n = values.number(v, pos)
        auto precision = _int(
            _get(args, "precision", JsonValue.Int(0)),
            pos,
            "filter round",
        )
        auto method = _text(
            _get(args, "method", JsonValue.Str("common")),
            pos,
            "filter round",
        )
        return values.value(JsonValue.Float(_round(n, precision, method, pos)))
    if name == "dictsort":
        if _kind(v) != "mapping":
            values.fail(pos, "filter dictsort: requires an object")
        auto sensitive = _bool(
            _get(args, "case_sensitive", JsonValue.Bool(False)),
            pos,
            "filter dictsort",
        )
        auto reverse = _bool(
            _get(args, "reverse", JsonValue.Bool(False)),
            pos,
            "filter dictsort",
        )
        auto by = _text(_get(args, "by", JsonValue.Str("key")), pos, "filter dictsort")
        if not by in ["key", "value"]:
            values.fail(pos, "filter dictsort: by must be key or value")
        list[values.Value] pairs = []
        match v.data:
            case JsonValue.Object(fields):
                for key in fields:
                    values.tick(budget)
                    pairs.append(
                        values.value(
                            JsonValue.Array([JsonValue.Str(key), fields[key]]),
                        ),
                    )
            case _:
                values.fail(pos, "filter dictsort: requires an object")
        auto path = 0
        if by == "value":
            path = 1
        return values.sequence_value(
            sort(
                pairs,
                reverse,
                sensitive,
                values.value(JsonValue.Int(path)),
                budget,
                pos,
            ),
        )
    auto sequence = values.items(v, budget, pos)
    if name == "list":
        return values.sequence_value(sequence)
    if name in ["first", "last"]:
        if len(sequence) == 0:
            return values.undefined()
        if name == "first":
            return sequence[0]
        return sequence[len(sequence) - 1]
    if name == "reverse":
        if _kind(v) == "string":
            auto text = ""
            for i in range(len(sequence)):
                text = text + values.string(sequence[len(sequence) - 1 - i])
            return values.marked(text, False)
        list[values.Value] result = []
        for i in range(len(sequence)):
            result.append(sequence[len(sequence) - 1 - i])
        return values.sequence_value(result)
    if name == "sort":
        auto reverse = _bool(
            _get(args, "reverse", JsonValue.Bool(False)),
            pos,
            "filter sort",
        )
        auto sensitive = _bool(
            _get(args, "case_sensitive", JsonValue.Bool(False)),
            pos,
            "filter sort",
        )
        return values.sequence_value(
            sort(
                sequence,
                reverse,
                sensitive,
                _get(args, "attribute", JsonValue.Null),
                budget,
                pos,
            ),
        )
    if name == "join":
        auto separator = _get(args, "d", JsonValue.Str(""))
        auto delimiter = _text(separator, pos, "filter join")
        auto path = _get(args, "attribute", JsonValue.Null)
        list[values.Value] parts = []
        auto trusted = separator.safe
        for vitem in sequence:
            auto part = attribute(vitem, path, budget, pos)
            values.require(part, budget, pos)
            trusted = trusted or part.safe
            parts.append(part)
        auto escaping = budget.autoescape and trusted
        auto d = values.fragment(separator, escaping, pos)
        list[str] chunks = []
        auto size = 0
        for i in range(len(parts)):
            auto text = values.fragment(parts[i], escaping, pos)
            if i > 0:
                size = size + values.length(d)
                chunks.append(d)
            size = size + values.length(text)
            if size > 1048576:
                values.fail(pos, "filter join: output limit")
            chunks.append(text)
        return values.marked("".join(chunks), escaping)
    if name in ["select", "reject", "selectattr", "rejectattr"]:
        auto path = _get(args, "attribute", JsonValue.Null)
        auto testing = ""
        if "test" in args:
            testing = _text(args["test"], pos, "filter " + name)
        list[values.Value] test_args = []
        if "argument" in args:
            test_args.append(args["argument"])
        if testing != "":
            list[str] test_names = []
            for arg in test_args:
                test_names.append("")
            validate_test(testing, test_names, pos)
        elif len(test_args) > 0:
            values.fail(pos, "filter " + name + ": argument requires a test")
        list[values.Value] result = []
        for entry in sequence:
            auto selected = attribute(entry, path, budget, pos)
            auto matches = False
            if testing == "":
                values.require(selected, budget, pos)
                matches = values.truth(selected)
            else:
                matches = test(testing, selected, test_args, budget, pos)
            if name in ["reject", "rejectattr"]:
                matches = not matches
            if matches:
                result.append(entry)
        return values.sequence_value(result)
    if name == "map":
        if ("attribute" in args) == ("filter" in args):
            values.fail(pos, "filter map: provide attribute or filter")
        list[values.Value] result = []
        auto filter_name = ""
        if "filter" in args:
            filter_name = _text(args["filter"], pos, "filter map")
        if "attribute" in args and "argument" in args:
            values.fail(pos, "filter map: argument requires a filter")
        if "filter" in args and "default" in args:
            values.fail(pos, "filter map: default requires attribute")
        list[str] delegated_names = []
        if "argument" in args:
            delegated_names.append("")
        if "filter" in args:
            validate(filter_name, delegated_names, pos)
        if filter_name == "map":
            values.fail(pos, "filter map: recursive map is unsupported")
        for entry in sequence:
            auto mapped = values.undefined()
            if "attribute" in args:
                mapped = attribute(entry, args["attribute"], budget, pos)
                if not mapped.defined and "default" in args:
                    mapped = args["default"]
            else:
                list[values.Value] filter_args = []
                list[str] filter_names = []
                if "argument" in args:
                    filter_args.append(args["argument"])
                    filter_names.append("")
                mapped = apply(
                    filter_name,
                    entry,
                    filter_args,
                    filter_names,
                    budget,
                    pos,
                )
            result.append(mapped)
        return values.sequence_value(result)
    values.fail(pos, "unsupported filter " + name)
    return values.undefined()
