import templates.values
import templates.filters

struct Token:
    str text
    str kind
    int64 pos

struct Node:
    str kind
    str text
    JsonValue value
    list[int64] children
    list[str] names
    int64 pos

struct Parser:
    list[Token] tokens
    int64 cursor
    list[Node] nodes

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
    auto source_length = values.length(source)
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
                        values.fail(base + start, "unterminated string escape")
                    ch = source[i:i + 1]
                    i = i + 1
                    if ch == "n":
                        ch = "\n"
                    elif ch == "t":
                        ch = "\t"
                    elif ch == "r":
                        ch = "\r"
                    elif not ch in ["\\", "'", "\""]:
                        values.fail(base + i - 1, "unsupported string escape")
                text = text + ch
            if i >= source_length:
                values.fail(base + start, "unterminated string")
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
                values.fail(base + start, "invalid leading zero in numeric literal")
            if i < source_length and source[i:i + 1] == ".":
                i = i + 1
                if i >= source_length or source[i:i + 1] < "0" or source[i:i + 1] > "9":
                    values.fail(base + start, "expected digits after decimal point")
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
            if not op in ["==", "!=", "<=", ">=", "//", "<", ">", "+", "-", "*", "/", "%", "~", "(", ")", "[", "]", ".", "|", ",", "="]:
                values.fail(base + start, "unsupported expression token: " + op)
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
        values.fail(token.pos, "expected " + text)

def _node(
    Parser p,
    str kind,
    str text,
    JsonValue value,
    list[int64] children,
    int64 pos,
    list[str] names = [],
) -> int64:
    if len(p.nodes) >= 10000:
        values.fail(pos, "expression exceeds 10000 nodes")
    p.nodes.append(
        Node(
            kind=kind,
            text=text,
            value=value,
            children=children,
            names=names,
            pos=pos,
        ),
    )
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

struct Arguments:
    list[int64] nodes
    list[str] names

def _arguments(Parser p, int64 depth) -> Arguments:
    list[int64] nodes = []
    list[str] names = []
    if _peek(p).kind != "symbol" or _peek(p).text != "(":
        return Arguments(nodes=nodes, names=names)
    auto open = _take(p)
    if _peek(p).kind == "symbol" and _peek(p).text == ")":
        auto close = _take(p)
        return Arguments(nodes=nodes, names=names)
    while True:
        if len(nodes) >= 16:
            values.fail(_peek(p).pos, "call exceeds 16 arguments")
        auto name = ""
        auto token = _peek(p)
        if token.kind == "name" and p.tokens[p.cursor + 1].text == "=" and p.tokens[p.cursor + 1].kind == "symbol":
            auto key = _take(p)
            auto equal = _take(p)
            name = key.text
        nodes.append(_expr(p, 1, depth + 1))
        names.append(name)
        if _peek(p).kind == "symbol" and _peek(p).text == ",":
            auto comma = _take(p)
            if _peek(p).kind == "symbol" and _peek(p).text == ")":
                break
        else:
            break
    _expect(p, ")")
    return Arguments(nodes=nodes, names=names)

def _expr(Parser p, int64 minimum, int64 depth) -> int64:
    if depth > 64:
        values.fail(_peek(p).pos, "expression nesting exceeds 64")
    auto token = _take(p)
    auto left = -1
    if token.kind == "string":
        left = _node(p, "literal", "", JsonValue.Str(token.text), [], token.pos)
    elif token.kind == "number":
        auto value = JsonValue.Null
        try:
            value = json.loads(token.text)
        except Exception:
            values.fail(token.pos, "invalid numeric literal")
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
        values.fail(token.pos, "expected expression")
    while True:
        auto next = _peek(p)
        if next.kind == "symbol" and next.text == ".":
            auto dot = _take(p)
            auto key = _take(p)
            if key.kind != "name":
                values.fail(key.pos, "expected attribute name")
            auto index = _node(p, "literal", "", JsonValue.Str(key.text), [], key.pos)
            left = _node(p, "lookup", "", JsonValue.Null, [left, index], next.pos)
            continue
        if next.kind == "symbol" and next.text == "[":
            auto open = _take(p)
            auto index = _expr(p, 1, depth + 1)
            _expect(p, "]")
            left = _node(p, "lookup", "", JsonValue.Null, [left, index], next.pos)
            continue
        if minimum <= 65 and (next.kind == "symbol" and next.text == "|" or next.kind == "name" and next.text == "is"):
            auto marker = _take(p)
            auto negate = False
            if marker.text == "is" and _peek(p).kind == "name" and _peek(p).text == "not":
                auto negation = _take(p)
                negate = True
            auto name = _take(p)
            if name.kind != "name":
                values.fail(name.pos, "expected filter or test name")
            auto arguments = _arguments(p, depth + 1)
            list[int64] children = [left]
            for argument in arguments.nodes:
                children.append(argument)
            if marker.text == "|":
                filters.validate(name.text, arguments.names, name.pos)
                left = _node(
                    p,
                    "filter",
                    name.text,
                    JsonValue.Null,
                    children,
                    name.pos,
                    arguments.names,
                )
            else:
                filters.validate_test(name.text, arguments.names, name.pos)
                auto test_name = name.text
                if negate:
                    test_name = "not:" + test_name
                left = _node(
                    p,
                    "test",
                    test_name,
                    JsonValue.Null,
                    children,
                    name.pos,
                    arguments.names,
                )
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
                        values.fail(in_token.pos, "expected in after not")
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
        values.fail(_peek(p).pos, "unexpected expression token: " + _peek(p).text)
    return root

def evaluate(
    list[Node] nodes,
    int64 index,
    dict[str, values.Value] context,
    values.Budget budget,
    int64 depth = 0,
) -> values.Value:
    values.tick(budget)
    if depth > 128:
        values.fail(0, "expression evaluation nesting exceeds 128")
    auto node = nodes[index]
    if node.kind == "literal":
        return values.value(node.value)
    if node.kind == "name":
        if node.text in context:
            return context[node.text]
        return values.undefined()
    if node.kind == "lookup":
        auto base = evaluate(nodes, node.children[0], context, budget, depth + 1)
        auto key = evaluate(nodes, node.children[1], context, budget, depth + 1)
        return values.lookup(base, key, node.pos, budget)
    if node.kind in ["filter", "test"]:
        auto input = evaluate(nodes, node.children[0], context, budget, depth + 1)
        list[values.Value] arguments = []
        for i in range(1, len(node.children)):
            arguments.append(
                evaluate(nodes, node.children[i], context, budget, depth + 1),
            )
        if node.kind == "filter":
            try:
                return filters.apply(
                    node.text,
                    input,
                    arguments,
                    node.names,
                    budget,
                    node.pos,
                )
            except Exception as e:
                values.fail(node.pos, "filter " + node.text + ": " + str(e))
        auto name = node.text
        auto negate = name.startswith("not:")
        if negate:
            name = name[4:]
        try:
            auto matched = filters.test(name, input, arguments, budget, node.pos)
            return values.value(JsonValue.Bool(matched != negate))
        except Exception as e:
            values.fail(node.pos, "test " + name + ": " + str(e))
    if node.kind == "unary":
        auto operand = evaluate(nodes, node.children[0], context, budget, depth + 1)
        values.require(operand, budget, node.pos)
        if node.text == "not":
            return values.value(JsonValue.Bool(not values.truth(operand)))
        if node.text == "+":
            auto checked = values.number(operand, node.pos)
            return operand
        return values.arithmetic(
            "-",
            values.value(JsonValue.Int(0)),
            operand,
            node.pos,
            budget,
        )
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
            if not values.compare(operators[i], left, right, budget, node.pos):
                return values.value(JsonValue.Bool(False))
            left = right
        return values.value(JsonValue.Bool(True))
    auto left = evaluate(nodes, node.children[0], context, budget, depth + 1)
    if node.text in ["and", "or"]:
        values.require(left, budget, node.pos)
    if node.text == "and" and not values.truth(left):
        return left
    if node.text == "or" and values.truth(left):
        return left
    auto right = evaluate(nodes, node.children[1], context, budget, depth + 1)
    if node.text in ["and", "or"]:
        return right
    return values.arithmetic(node.text, left, right, node.pos, budget)
