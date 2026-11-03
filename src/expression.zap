import math

struct Token:
    str text
    str kind
    int64 pos

struct Node:
    str kind
    str text
    JsonValue value
    list[int64] children
    int64 pos

struct Parser:
    list[Token] tokens
    int64 cursor
    list[Node] nodes

struct Value:
    JsonValue data
    bool defined

struct Budget:
    int64 steps
    int64 output

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

def _ident_start(str c) -> bool:
    return c == "_" or c >= "a" and c <= "z" or c >= "A" and c <= "Z"

def identifier(str s) -> bool:
    if len(s) == 0:
        return False
    if not _ident_start(s[0:1]):
        return False
    for character in s:
        auto c = str(character)
        if not _ident_start(str(c)) and not (c >= "0" and c <= "9"):
            return False
    return not s in ["true", "false", "none", "True", "False", "None", "and", "or", "not", "in", "loop"]

def tokenize(str source, int64 base) -> list[Token]:
    list[Token] tokens = []
    auto source_length = length(source)
    auto i = 0
    while i < source_length:
        auto start = i
        auto c = source[i:i + 1]
        if c in [" ", "\t", "\r", "\n"]:
            i = i + 1
            continue
        if c == "'" or c == "\"":
            auto quote = c
            auto text = ""
            i = i + 1
            while i < source_length and source[i:i + 1] != quote:
                auto ch = source[i:i + 1]
                i = i + 1
                if ch == "\\":
                    if i >= source_length:
                        fail(base + start, "unterminated string escape")
                    ch = source[i:i + 1]
                    i = i + 1
                    if ch == "n":
                        ch = "\n"
                    elif ch == "t":
                        ch = "\t"
                    elif ch == "r":
                        ch = "\r"
                    elif not ch in ["\\", "'", "\""]:
                        fail(base + i - 1, "unsupported string escape")
                text = text + ch
            if i >= source_length:
                fail(base + start, "unterminated string")
            i = i + 1
            tokens.append(Token(text=text, kind="string", pos=base + start))
        elif _ident_start(str(c)):
            i = i + 1
            while i < source_length:
                auto ch = source[i:i + 1]
                if not _ident_start(ch) and not (ch >= "0" and ch <= "9"):
                    break
                i = i + 1
            tokens.append(Token(text=source[start:i], kind="name", pos=base + start))
        elif c >= "0" and c <= "9":
            i = i + 1
            while i < source_length and source[i:i + 1] >= "0" and source[i:i + 1] <= "9":
                i = i + 1
            if i - start > 1 and c == "0":
                fail(base + start, "invalid leading zero in numeric literal")
            if i < source_length and source[i:i + 1] == ".":
                i = i + 1
                if i >= source_length or source[i:i + 1] < "0" or source[i:i + 1] > "9":
                    fail(base + start, "expected digits after decimal point")
                while i < source_length and source[i:i + 1] >= "0" and source[i:i + 1] <= "9":
                    i = i + 1
            tokens.append(Token(text=source[start:i], kind="number", pos=base + start))
        else:
            auto op = source[i:i + 2]
            if op in ["==", "!=", "<=", ">=", "//"]:
                i = i + 2
            else:
                op = c
                i = i + 1
            if not op in ["==", "!=", "<=", ">=", "//", "<", ">", "+", "-", "*", "/", "%", "~", "(", ")", "[", "]", "."]:
                fail(base + start, "unsupported expression token: " + op)
            tokens.append(Token(text=op, kind="symbol", pos=base + start))
    tokens.append(Token(text="", kind="end", pos=base + source_length))
    return tokens

def _peek(Parser p) -> Token:
    return p.tokens[p.cursor]

def _take(Parser p) -> Token:
    auto token = _peek(p)
    if token.kind != "end":
        p.cursor = p.cursor + 1
    return token

def _expect(Parser p, str text):
    auto token = _take(p)
    if token.text != text or token.kind != "symbol":
        fail(token.pos, "expected " + text)

def _node(
    Parser p,
    str kind,
    str text,
    JsonValue value,
    list[int64] children,
    int64 pos,
) -> int64:
    if len(p.nodes) >= 10000:
        fail(pos, "expression exceeds 10000 nodes")
    p.nodes.append(Node(kind=kind, text=text, value=value, children=children, pos=pos))
    return len(p.nodes) - 1

def _priority(Token token) -> int64:
    if token.kind == "name":
        if token.text == "or":
            return 10
        if token.text == "and":
            return 20
        if token.text in ["in", "not"]:
            return 30
    if token.kind == "symbol":
        if token.text in ["==", "!=", "<", ">", "<=", ">="]:
            return 30
        if token.text == "~":
            return 40
        if token.text in ["+", "-"]:
            return 50
        if token.text in ["*", "/", "//", "%"]:
            return 60
    return 0

def _expr(Parser p, int64 minimum, int64 depth) -> int64:
    if depth > 64:
        fail(_peek(p).pos, "expression nesting exceeds 64")
    auto token = _take(p)
    auto left = -1
    if token.kind == "string":
        left = _node(p, "literal", "", JsonValue.Str(token.text), [], token.pos)
    elif token.kind == "number":
        auto value = JsonValue.Null
        try:
            value = json.loads(token.text)
        except Exception:
            fail(token.pos, "invalid numeric literal")
        left = _node(p, "literal", "", value, [], token.pos)
    elif token.kind == "name" and token.text in ["true", "True", "false", "False", "none", "None"]:
        auto value = JsonValue.Null
        if token.text in ["true", "True", "false", "False"]:
            value = JsonValue.Bool(token.text in ["true", "True"])
        left = _node(p, "literal", "", value, [], token.pos)
    elif token.kind == "symbol" and token.text in ["+", "-"] or token.kind == "name" and token.text == "not":
        auto priority = 70
        if token.text == "not":
            priority = 25
        auto operand = _expr(p, priority, depth + 1)
        left = _node(p, "unary", token.text, JsonValue.Null, [operand], token.pos)
    elif token.kind == "symbol" and token.text == "(":
        left = _expr(p, 1, depth + 1)
        _expect(p, ")")
    elif token.kind == "name" and (identifier(token.text) or token.text == "loop"):
        left = _node(p, "name", token.text, JsonValue.Null, [], token.pos)
    else:
        fail(token.pos, "expected expression")
    while True:
        auto next = _peek(p)
        if next.kind == "symbol" and next.text == ".":
            auto dot = _take(p)
            auto key = _take(p)
            if key.kind != "name":
                fail(key.pos, "expected attribute name")
            auto index = _node(p, "literal", "", JsonValue.Str(key.text), [], key.pos)
            left = _node(p, "lookup", "", JsonValue.Null, [left, index], next.pos)
            continue
        if next.kind == "symbol" and next.text == "[":
            auto open = _take(p)
            auto index = _expr(p, 1, depth + 1)
            _expect(p, "]")
            left = _node(p, "lookup", "", JsonValue.Null, [left, index], next.pos)
            continue
        auto priority = _priority(next)
        if priority < minimum or priority == 0:
            break
        if priority == 30:
            list[int64] operands = [left]
            list[str] operators = []
            while _priority(_peek(p)) == 30:
                auto op = _take(p)
                auto operator = op.text
                if operator == "not":
                    auto in_token = _take(p)
                    if in_token.kind != "name" or in_token.text != "in":
                        fail(in_token.pos, "expected in after not")
                    operator = "not in"
                operators.append(operator)
                operands.append(_expr(p, 31, depth + 1))
            left = _node(
                p,
                "compare",
                "\n".join(operators),
                JsonValue.Null,
                operands,
                next.pos,
            )
        else:
            auto op = _take(p)
            auto right = _expr(p, priority + 1, depth + 1)
            left = _node(p, "binary", op.text, JsonValue.Null, [left, right], op.pos)
    return left

def parse(Parser p, str source, int64 base) -> int64:
    p.tokens = tokenize(source, base)
    p.cursor = 0
    auto root = _expr(p, 1, 0)
    if _peek(p).kind != "end":
        fail(_peek(p).pos, "unexpected expression token: " + _peek(p).text)
    return root

def value(JsonValue data) -> Value:
    return Value(data=data, defined=True)

def undefined() -> Value:
    return Value(data=JsonValue.Null, defined=False)

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

def lookup(Value base, Value key, int64 pos) -> Value:
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
                        return value(xs[index])
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
                        return value(JsonValue.Str(s[index:index + 1]))
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

def _compare(str op, Value a, Value b, Budget budget, int64 pos) -> bool:
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

def _arithmetic(str op, Value a, Value b, int64 pos) -> Value:
    if op == "~":
        auto first = string(a)
        auto second = string(b)
        if length(first) + length(second) > 1048576:
            fail(pos, "expression string exceeds 1048576 characters")
        return value(JsonValue.Str(first + second))
    if op == "+":
        match a.data:
            case JsonValue.Str(s):
                match b.data:
                    case JsonValue.Str(t):
                        if a.defined and b.defined:
                            return _arithmetic("~", a, b, pos)
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

def evaluate(
    list[Node] nodes,
    int64 index,
    dict[str, JsonValue] context,
    Budget budget,
    int64 depth = 0,
) -> Value:
    tick(budget)
    if depth > 128:
        fail(0, "expression evaluation nesting exceeds 128")
    auto node = nodes[index]
    if node.kind == "literal":
        return value(node.value)
    if node.kind == "name":
        if node.text in context:
            return value(context[node.text])
        return undefined()
    if node.kind == "lookup":
        auto base = evaluate(nodes, node.children[0], context, budget, depth + 1)
        auto key = evaluate(nodes, node.children[1], context, budget, depth + 1)
        return lookup(base, key, node.pos)
    if node.kind == "unary":
        auto operand = evaluate(nodes, node.children[0], context, budget, depth + 1)
        if node.text == "not":
            return value(JsonValue.Bool(not truth(operand)))
        if node.text == "+":
            auto checked = number(operand, node.pos)
            return operand
        return _arithmetic("-", value(JsonValue.Int(0)), operand, node.pos)
    if node.kind == "compare":
        auto operators = node.text.split("\n")
        auto left = evaluate(nodes, node.children[0], context, budget, depth + 1)
        for i in range(len(operators)):
            auto right = evaluate(
                nodes,
                node.children[i + 1],
                context,
                budget,
                depth + 1,
            )
            if not _compare(operators[i], left, right, budget, node.pos):
                return value(JsonValue.Bool(False))
            left = right
        return value(JsonValue.Bool(True))
    auto left = evaluate(nodes, node.children[0], context, budget, depth + 1)
    if node.text == "and" and not truth(left):
        return left
    if node.text == "or" and truth(left):
        return left
    auto right = evaluate(nodes, node.children[1], context, budget, depth + 1)
    if node.text in ["and", "or"]:
        return right
    return _arithmetic(node.text, left, right, node.pos)
