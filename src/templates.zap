import templates.expression

struct Segment:
    str kind
    str text
    int64 pos

struct Node:
    str kind
    str text
    int64 expression
    list[int64] body
    list[int64] alternate
    int64 pos

struct Template:
    list[Node] nodes
    list[expression.Node] expressions
    list[int64] body

struct Parser:
    list[Segment] segments
    int64 cursor
    list[Node] nodes
    expression.Parser expressions

struct RenderState:
    Template template
    expression.Budget budget
    list[str] chunks
    bool autoescape

def _fail(int64 pos, str message):
    expression.fail(pos, message)

def _scan(str source) -> list[Segment]:
    if len(source) > 1048576:
        _fail(0, "source exceeds 1048576 characters")
    list[Segment] result = []
    auto i = 0
    auto start = 0
    auto trim_next = False
    while i < len(source):
        auto opener = source[i:i + 2]
        if not opener in ["{{", "{%", "{#"]:
            i = i + 1
            continue
        auto text = source[start:i]
        if trim_next:
            text = text.lstrip()
        auto pos = i
        i = i + 2
        auto left_trim = i < len(source) and source[i:i + 1] == "-"
        if left_trim:
            text = text.rstrip()
            i = i + 1
        if len(text) > 0:
            result.append(Segment(kind="text", text=text, pos=start))
        auto closer = "}}"
        auto kind = "expression"
        if opener == "{%":
            closer = "%}"
            kind = "tag"
        elif opener == "{#":
            closer = "#}"
            kind = "comment"
        auto content = i
        auto quote = ""
        while i < len(source):
            auto c = source[i:i + 1]
            if kind != "comment":
                if len(quote) > 0:
                    if c == "\\":
                        i = i + 2
                        continue
                    if c == quote:
                        quote = ""
                elif c in ["'", "\""]:
                    quote = c
                elif source[i:i + 2] == closer:
                    break
            elif source[i:i + 2] == closer:
                break
            i = i + 1
        if i >= len(source):
            _fail(pos, "unterminated " + kind)
        trim_next = i > content and source[i - 1:i] == "-"
        auto end = i
        if trim_next:
            end = end - 1
        if kind != "comment":
            result.append(Segment(kind=kind, text=source[content:end], pos=content))
        i = i + 2
        start = i
    auto tail = source[start:]
    if trim_next:
        tail = tail.lstrip()
    if len(tail) > 0:
        result.append(Segment(kind="text", text=tail, pos=start))
    result.append(Segment(kind="end", text="", pos=len(source)))
    return result

def _head(Segment segment) -> str:
    auto text = segment.text.strip()
    auto end = 0
    while end < len(text) and not text[end:end + 1] in [" ", "\t", "\r", "\n"]:
        end = end + 1
    return text[:end]

def _expression(Parser p, str text, int64 pos) -> int64:
    return expression.parse(p.expressions, text, pos)

def _add(
    Parser p,
    str kind,
    str text,
    int64 expression,
    list[int64] body,
    list[int64] alternate,
    int64 pos,
) -> int64:
    if len(p.nodes) >= 10000:
        _fail(pos, "template exceeds 10000 nodes")
    p.nodes.append(
        Node(
            kind=kind,
            text=text,
            expression=expression,
            body=body,
            alternate=alternate,
            pos=pos,
        ),
    )
    return len(p.nodes) - 1

def _closing(Parser p, str wanted):
    auto segment = p.segments[p.cursor]
    if segment.kind != "tag" or segment.text.strip() != wanted:
        _fail(segment.pos, "expected " + wanted)
    p.cursor = p.cursor + 1

def _if(Parser p, int64 depth) -> int64:
    if depth > 64:
        _fail(p.segments[p.cursor].pos, "template nesting exceeds 64")
    auto segment = p.segments[p.cursor]
    auto head = _head(segment)
    auto text = segment.text
    auto offset = text.find(head) + len(head)
    auto condition = _expression(p, text[offset:], segment.pos + offset)
    p.cursor = p.cursor + 1
    auto body = _block(p, ["elif", "else", "endif"], depth + 1)
    auto stop = p.segments[p.cursor]
    list[int64] alternate = []
    if stop.kind == "tag" and _head(stop) == "elif":
        alternate.append(_if(p, depth + 1))
    else:
        if stop.kind == "tag" and stop.text.strip() == "else":
            p.cursor = p.cursor + 1
            alternate = _block(p, ["endif"], depth + 1)
        _closing(p, "endif")
    return _add(p, "if", "", condition, body, alternate, segment.pos)

def _block(Parser p, list[str] stops, int64 depth) -> list[int64]:
    if depth > 64:
        _fail(p.segments[p.cursor].pos, "template nesting exceeds 64")
    list[int64] body = []
    while True:
        auto segment = p.segments[p.cursor]
        if segment.kind == "end":
            break
        if segment.kind == "text":
            body.append(_add(p, "text", segment.text, -1, [], [], segment.pos))
            p.cursor = p.cursor + 1
        elif segment.kind == "expression":
            auto expr_index = _expression(p, segment.text, segment.pos)
            body.append(_add(p, "output", "", expr_index, [], [], segment.pos))
            p.cursor = p.cursor + 1
        else:
            auto head = _head(segment)
            if head in stops:
                break
            if head == "if":
                body.append(_if(p, depth + 1))
            elif head == "for":
                auto tokens = expression.tokenize(segment.text, segment.pos)
                if len(tokens) < 5 or tokens[0].text != "for" or tokens[1].kind != "name" or not expression.identifier(tokens[1].text) or tokens[2].text != "in" or tokens[2].kind != "name":
                    _fail(segment.pos, "expected for <name> in <expression>")
                auto offset = tokens[3].pos - segment.pos
                auto expr_index = _expression(
                    p,
                    segment.text[offset:],
                    segment.pos + offset,
                )
                p.cursor = p.cursor + 1
                auto loop_body = _block(p, ["else", "endfor"], depth + 1)
                list[int64] alternate = []
                auto stop = p.segments[p.cursor]
                if stop.kind == "tag" and stop.text.strip() == "else":
                    p.cursor = p.cursor + 1
                    alternate = _block(p, ["endfor"], depth + 1)
                _closing(p, "endfor")
                body.append(
                    _add(
                        p,
                        "for",
                        tokens[1].text,
                        expr_index,
                        loop_body,
                        alternate,
                        segment.pos,
                    ),
                )
            elif head == "set":
                # Locate the assignment separator separately: '=' is not an expression operator.
                auto offset = segment.text.find("=")
                if offset < 0:
                    _fail(segment.pos, "expected set <name> = <expression>")
                auto name = segment.text[:offset].strip()[3:].strip()
                if not expression.identifier(name):
                    _fail(segment.pos, "invalid assignment name")
                auto expr_index = _expression(
                    p,
                    segment.text[offset + 1:],
                    segment.pos + offset + 1,
                )
                body.append(_add(p, "set", name, expr_index, [], [], segment.pos))
                p.cursor = p.cursor + 1
            else:
                _fail(segment.pos, "unknown or misplaced tag: " + head)
    return body

def compile(str source) -> Template:
    auto expressions = expression.Parser(tokens=[], cursor=0, nodes=[])
    auto parser = Parser(
        segments=_scan(source),
        cursor=0,
        nodes=[],
        expressions=expressions,
    )
    auto body = _block(parser, [], 0)
    return Template(nodes=parser.nodes, expressions=parser.expressions.nodes, body=body)

def escape(str text) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&#34;").replace(
        "'",
        "&#39;",
    )

def _emit(RenderState state, str text, int64 pos):
    if len(text) > 1048576 - state.budget.output:
        _fail(pos, "output exceeds 1048576 characters")
    state.budget.output = state.budget.output + len(text)
    state.chunks.append(text)

def _context(dict[str, JsonValue] source) -> dict[str, JsonValue]:
    dict[str, JsonValue] result = {}
    for key in source:
        result[key] = source[key]
    return result

def _items(expression.Value value, int64 pos) -> list[JsonValue]:
    if not value.defined:
        return []
    match value.data:
        case JsonValue.Array(items):
            return items
        case JsonValue.Object(fields):
            list[JsonValue] items = []
            for key in fields:
                if len(items) >= 100000:
                    _fail(pos, "iteration exceeds 100000 items")
                items.append(JsonValue.Str(key))
            return items
        case JsonValue.Str(text):
            if len(text) > 100000:
                _fail(pos, "iteration exceeds 100000 items")
            list[JsonValue] items = []
            for c in text:
                items.append(JsonValue.Str(str(c)))
            return items
        case _:
            _fail(pos, "for requires an array, object, string, or undefined")
    return []

def _render(
    RenderState state,
    list[int64] body,
    dict[str, JsonValue] context,
    int64 depth,
):
    if depth > 64:
        _fail(0, "render nesting exceeds 64")
    for index in body:
        expression.tick(state.budget)
        auto node = state.template.nodes[index]
        if node.kind == "text":
            _emit(state, node.text, node.pos)
            continue
        auto value = expression.evaluate(
            state.template.expressions,
            node.expression,
            context,
            state.budget,
        )
        if node.kind == "output":
            auto text = expression.string(value)
            if state.autoescape:
                text = escape(text)
            _emit(state, text, node.pos)
        elif node.kind == "set":
            # Preserve undefined rather than assigning it the explicit null value.
            if not value.defined:
                _fail(node.pos, "cannot assign an undefined value")
            context[node.text] = value.data
        elif node.kind == "if":
            if expression.truth(value):
                _render(state, node.body, context, depth + 1)
            else:
                _render(state, node.alternate, context, depth + 1)
        elif node.kind == "for":
            auto items = _items(value, node.pos)
            if len(items) > 100000:
                _fail(node.pos, "iteration exceeds 100000 items")
            if len(items) == 0:
                auto bindings = _context(context)
                _render(state, node.alternate, bindings, depth + 1)
            for i in range(len(items)):
                auto bindings = _context(context)
                bindings[node.text] = items[i]
                dict[str, JsonValue] loop = {
                    "index": JsonValue.Int(i + 1),
                    "index0": JsonValue.Int(i),
                    "revindex": JsonValue.Int(len(items) - i),
                    "revindex0": JsonValue.Int(len(items) - i - 1),
                    "first": JsonValue.Bool(i == 0),
                    "last": JsonValue.Bool(i == len(items) - 1),
                    "length": JsonValue.Int(len(items)),
                }
                bindings["loop"] = JsonValue.Object(loop)
                _render(state, node.body, bindings, depth + 1)

def render_compiled(
    Template template,
    dict[str, JsonValue] context,
    bool autoescape = True,
) -> str:
    auto state = RenderState(
        template=template,
        budget=expression.Budget(steps=0, output=0),
        chunks=[],
        autoescape=autoescape,
    )
    auto bindings = _context(context)
    _render(state, template.body, bindings, 0)
    return "".join(state.chunks)

def render(str source, dict[str, JsonValue] context, bool autoescape = True) -> str:
    return render_compiled(compile(source), context, autoescape)
