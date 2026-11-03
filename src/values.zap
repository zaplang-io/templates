import math

struct Value:
    JsonValue data
    bool defined
    bool safe
    list[bool] item_safe
    list[bool] item_defined

struct Budget:
    int64 steps
    int64 output
    bool strict
    bool autoescape

def fail(int64 pos, str message):
    raise "TemplateError at character " + str(pos + 1) + ": " + message

def tick(Budget budget):
    budget.steps = budget.steps + 1
    if budget.steps > 100000:
        fail(0, "evaluation exceeds 100000 steps")

# Zap's current len(str) reports UTF-8 bytes, while slicing uses codepoints.
def length(str text) -> int64:
    auto count = 0
    for c in text:
        count = count + 1
    return count

def value(JsonValue data) -> Value:
    return Value(data=data, defined=True, safe=False, item_safe=[], item_defined=[])

def undefined() -> Value:
    return Value(
        data=JsonValue.Null,
        defined=False,
        safe=False,
        item_safe=[],
        item_defined=[],
    )

def truth(Value v) -> bool:
    if not v.defined:
        return False
    match v.data:
        case JsonValue.Null:
            return False
        case JsonValue.Bool(b):
            return b
        case JsonValue.Int(i):
            return i != 0
        case JsonValue.Float(f):
            return f != 0.0
        case JsonValue.Str(s):
            return len(s) > 0
        case JsonValue.Array(xs):
            return len(xs) > 0
        case JsonValue.Object(fields):
            return len(fields) > 0

def string(Value v) -> str:
    if not v.defined:
        return ""
    match v.data:
        case JsonValue.Str(s):
            return s
        case JsonValue.Null:
            return "None"
        case JsonValue.Bool(b):
            if b:
                return "True"
            return "False"
        case _:
            return json.dumps(v.data)

def number(Value v, int64 pos) -> float64:
    if v.defined:
        match v.data:
            case JsonValue.Int(i):
                return float64(i)
            case JsonValue.Float(f):
                return f
            case _:
                fail(pos, "numeric operand required")
    fail(pos, "undefined numeric operand")
    return 0.0

def _integer(Value v) -> bool:
    match v.data:
        case JsonValue.Int(i):
            return v.defined
        case _:
            return False

def lookup(Value base, Value key, int64 pos, Budget budget) -> Value:
    require(base, budget, pos)
    require(key, budget, pos)
    if not base.defined or not key.defined:
        return undefined()
    match base.data:
        case JsonValue.Object(fields):
            match key.data:
                case JsonValue.Str(s):
                    if s in fields:
                        return value(fields[s])
                case _:
                    fail(pos, "object key must be a string")
        case JsonValue.Array(xs):
            match key.data:
                case JsonValue.Int(i):
                    auto index = i
                    if index < 0:
                        index = index + len(xs)
                    if index >= 0 and index < len(xs):
                        return item(base, index)
                case _:
                    fail(pos, "array index must be an integer")
        case JsonValue.Str(s):
            auto size = length(s)
            match key.data:
                case JsonValue.Int(i):
                    auto index = i
                    if index < 0:
                        index = index + size
                    if index >= 0 and index < size:
                        return marked(s[index:index + 1], base.safe)
                case _:
                    fail(pos, "string index must be an integer")
        case _:
            fail(pos, "cannot look up a scalar value")
    return undefined()

def equal(Value a, Value b, Budget budget, int64 depth = 0) -> bool:
    tick(budget)
    if depth > 64:
        fail(0, "value nesting exceeds 64")
    if not a.defined or not b.defined:
        return a.defined == b.defined
    match a.data:
        case JsonValue.Int(i):
            match b.data:
                case JsonValue.Int(j):
                    return i == j
                case JsonValue.Float(f):
                    return f >= -9223372036854775808.0 and f < 9223372036854775808.0 and math.floor(f) == f and i == int64(f)
                case _:
                    return False
        case JsonValue.Float(f):
            match b.data:
                case JsonValue.Int(i):
                    return equal(b, a, budget, depth + 1)
                case JsonValue.Float(g):
                    return f == g
                case _:
                    return False
        case JsonValue.Array(xs):
            match b.data:
                case JsonValue.Array(ys):
                    if len(xs) != len(ys):
                        return False
                    for i in range(len(xs)):
                        if not equal(value(xs[i]), value(ys[i]), budget, depth + 1):
                            return False
                    return True
                case _:
                    return False
        case JsonValue.Object(xs):
            match b.data:
                case JsonValue.Object(ys):
                    if len(xs) != len(ys):
                        return False
                    for key in xs:
                        if not key in ys:
                            return False
                        if not equal(value(xs[key]), value(ys[key]), budget, depth + 1):
                            return False
                    return True
                case _:
                    return False
        case _:
            return json.dumps(a.data) == json.dumps(b.data)

def _contains(Value container, Value needle, Budget budget, int64 pos) -> bool:
    if not container.defined:
        fail(pos, "undefined membership operand")
    match container.data:
        case JsonValue.Str(s):
            match needle.data:
                case JsonValue.Str(t):
                    return needle.defined and t in s
                case _:
                    fail(pos, "string membership requires a string")
        case JsonValue.Object(fields):
            match needle.data:
                case JsonValue.Str(t):
                    return needle.defined and t in fields
                case _:
                    fail(pos, "object membership requires a string")
        case JsonValue.Array(xs):
            for item in xs:
                if equal(value(item), needle, budget):
                    return True
            return False
        case _:
            fail(pos, "membership requires a string, array, or object")
    return False

def compare(str op, Value a, Value b, Budget budget, int64 pos) -> bool:
    require(a, budget, pos)
    require(b, budget, pos)
    if op == "==":
        return equal(a, b, budget)
    if op == "!=":
        return not equal(a, b, budget)
    if op in ["in", "not in"]:
        auto found = _contains(b, a, budget, pos)
        if op == "not in":
            return not found
        return found
    if not a.defined or not b.defined:
        fail(pos, "undefined comparison operand")
    auto less = False
    auto same = equal(a, b, budget)
    match a.data:
        case JsonValue.Str(s):
            match b.data:
                case JsonValue.Str(t):
                    less = s < t
                case _:
                    fail(pos, "incompatible comparison operands")
        case JsonValue.Int(i):
            match b.data:
                case JsonValue.Int(j):
                    less = i < j
                case _:
                    less = number(a, pos) < number(b, pos)
        case _:
            less = number(a, pos) < number(b, pos)
    if op == "<":
        return less
    if op == "<=":
        return less or same
    if op == ">":
        return not less and not same
    return not less

def arithmetic(str op, Value a, Value b, int64 pos, Budget budget) -> Value:
    require(a, budget, pos)
    require(b, budget, pos)
    if op == "~":
        auto trusted = a.safe or b.safe
        auto first = fragment(a, trusted, pos)
        auto second = fragment(b, trusted, pos)
        if length(first) + length(second) > 1048576:
            fail(pos, "expression string exceeds 1048576 characters")
        return marked(first + second, trusted)
    if op == "+":
        match a.data:
            case JsonValue.Str(s):
                match b.data:
                    case JsonValue.Str(t):
                        if a.defined and b.defined:
                            return arithmetic("~", a, b, pos, budget)
                    case _:
                        fail(pos, "cannot add string and non-string")
            case _:
                auto ignored = 0
    auto x = number(a, pos)
    auto y = number(b, pos)
    auto both_int = _integer(a) and _integer(b)
    # Exact arithmetic range, avoiding silent i64 overflow or rounded integers.
    if both_int and (math.fabs(x) > 9007199254740991.0 or math.fabs(y) > 9007199254740991.0):
        fail(pos, "integer arithmetic exceeds exact binary64 range")
    auto result = 0.0
    if op == "+":
        result = x + y
    elif op == "-":
        result = x - y
    elif op == "*":
        result = x * y
    else:
        if y == 0.0:
            fail(pos, "division by zero")
        if op == "/":
            result = x / y
        elif op == "//":
            result = math.floor(x / y)
        else:
            result = x - math.floor(x / y) * y
    if math.isnan(result) or math.isinf(result):
        fail(pos, "non-finite arithmetic result")
    if both_int and op != "/":
        if math.fabs(result) > 9007199254740991.0:
            fail(pos, "integer arithmetic exceeds exact binary64 range")
        return value(JsonValue.Int(int64(result)))
    return value(JsonValue.Float(result))


def require(Value v, Budget budget, int64 pos):
    if budget.strict and not v.defined:
        fail(pos, "undefined value under strict policy")

def marked(str text, bool safe) -> Value:
    auto result = value(JsonValue.Str(text))
    result.safe = safe
    return result

def escape(str text) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&#34;").replace(
        "'",
        "&#39;",
    )

def fragment(Value v, bool escaping, int64 pos) -> str:
    auto text = string(v)
    if length(text) > 1048576:
        fail(pos, "string exceeds 1048576 characters")
    if escaping and not v.safe:
        text = escape(text)
    if length(text) > 1048576:
        fail(pos, "escaped string exceeds 1048576 characters")
    return text

def item(Value sequence, int64 index) -> Value:
    match sequence.data:
        case JsonValue.Array(xs):
            auto result = value(xs[index])
            if index < len(sequence.item_safe):
                result.safe = sequence.item_safe[index]
            if index < len(sequence.item_defined):
                result.defined = sequence.item_defined[index]
            return result
        case _:
            return undefined()

def sequence_value(list[Value] items) -> Value:
    list[JsonValue] data = []
    list[bool] safety = []
    list[bool] defined = []
    for v in items:
        data.append(v.data)
        safety.append(v.safe)
        defined.append(v.defined)
    auto result = value(JsonValue.Array(data))
    result.item_safe = safety
    result.item_defined = defined
    return result

def items(Value v, Budget budget, int64 pos) -> list[Value]:
    require(v, budget, pos)
    list[Value] result = []
    if not v.defined:
        return result
    match v.data:
        case JsonValue.Array(xs):
            if len(xs) > 100000:
                fail(pos, "iteration exceeds 100000 items")
            for i in range(len(xs)):
                tick(budget)
                result.append(item(v, i))
        case JsonValue.Str(s):
            if length(s) > 100000:
                fail(pos, "iteration exceeds 100000 items")
            for c in s:
                tick(budget)
                result.append(value(JsonValue.Str(str(c))))
        case JsonValue.Object(fields):
            if len(fields) > 100000:
                fail(pos, "iteration exceeds 100000 items")
            for key in fields:
                tick(budget)
                result.append(value(JsonValue.Str(key)))
        case _:
            fail(pos, "iteration requires an array, object, string, or undefined")
    return result
