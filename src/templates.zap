import templates.expression
import templates.values
import templates.filters

struct Segment:
    str kind
    str text
    int64 pos

struct Node:
    str kind
    str text
    int64 expression
    list[str] names
    list[int64] defaults
    list[int64] body
    list[int64] alternate
    int64 pos

struct Template:
    list[Node] nodes
    list[expression.Node] expressions
    list[int64] body
    str name

struct Parser:
    list[Segment] segments
    int64 cursor
    list[Node] nodes
    expression.Parser expressions

struct Environment:
    dict[str, str] sources
    str root
    dict[str, Template] cache
    dict[str, JsonValue] globals
    bool autoescape
    bool strict_undefined

struct Block:
    str name
    Template template
    int64 node

struct Macro:
    str kind
    str name
    Template template
    list[int64] body
    list[str] parameters
    list[int64] defaults
    dict[str, values.Value] closure
    int64 block
    bool autoescape
    list[Block] blocks

struct RenderState:
    Environment environment
    values.Budget budget
    list[str] chunks
    list[Macro] callables
    list[values.Value] members
    list[Block] blocks
    list[str] active
    int64 calls

def _fail(int64 pos, str message):
    values.fail(pos, message)

def _scan(str source) -> list[Segment]:
    auto source_length = values.length(source)
    if source_length > 1048576:
        _fail(0, "source exceeds 1048576 characters")
    list[Segment] result = []
    auto i = 0
    auto start = 0
    auto trim_next = False
    while i < source_length:
        auto opener = source[i:i + 2]
        if not opener in ["{{", "{%", "{#"]:
            i = i + 1
            continue
        auto text = source[start:i]
        if trim_next:
            text = text.lstrip()
        auto pos = i
        i = i + 2
        auto left_trim = i < source_length and source[i:i + 1] == "-"
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
        while i < source_length:
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
        if i >= source_length:
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
    result.append(Segment(kind="end", text="", pos=source_length))
    return result

def _head(Segment segment) -> str:
    auto text = segment.text.strip()
    auto end = 0
    auto size = values.length(text)
    while end < size and not text[end:end + 1] in [" ", "\t", "\r", "\n", "("]:
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
    list[str] names = [],
    list[int64] defaults = [],
) -> int64:
    if len(p.nodes) >= 10000:
        _fail(pos, "template exceeds 10000 nodes")
    p.nodes.append(
        Node(
            kind=kind,
            text=text,
            expression=expression,
            names=names,
            defaults=defaults,
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

def _tag_tail(Segment segment, str head) -> str:
    return segment.text[segment.text.find(head) + len(head):].strip()

struct ContextTail:
    str text
    bool with_context

def _context_tail(str text, bool default_context, int64 pos) -> ContextTail:
    auto tokens = expression.tokenize(text, pos)
    auto end = len(tokens) - 1
    auto enabled = default_context
    auto content = text
    if end >= 2 and tokens[end - 1].kind == "name" and tokens[end - 1].text == "context" and tokens[end - 2].kind == "name" and tokens[end - 2].text in ["with", "without"]:
        enabled = tokens[end - 2].text == "with"
        content = text[:tokens[end - 2].pos - pos].strip()
    return ContextTail(text=content, with_context=enabled)

def _composition(Parser p, Segment segment, str head, int64 depth) -> int64:
    auto text = _tag_tail(segment, head)
    auto base = segment.pos + segment.text.find(head) + len(head)
    # Keep exact offsets after stripping the tag's leading whitespace.
    base = base + values.length(segment.text[segment.text.find(head) + len(head):]) - values.length(segment.text[segment.text.find(head) + len(head):].lstrip())
    if head == "extends":
        auto expr_index = _expression(p, text, base)
        p.cursor = p.cursor + 1
        return _add(p, head, "", expr_index, [], [], segment.pos)
    if head == "include":
        auto tail = _context_tail(text, True, base)
        auto tokens = expression.tokenize(tail.text, base)
        auto end = len(tokens) - 1
        auto content = tail.text
        auto ignore = False
        if end >= 2 and tokens[end - 2].kind == "name" and tokens[end - 2].text == "ignore" and tokens[end - 1].kind == "name" and tokens[end - 1].text == "missing":
            ignore = True
            content = tail.text[:tokens[end - 2].pos - base]
        auto expr_index = _expression(p, content, base)
        p.cursor = p.cursor + 1
        auto flags = ""
        if tail.with_context:
            flags = "context"
        if ignore:
            flags = flags + ":ignore"
        return _add(p, head, flags, expr_index, [], [], segment.pos)
    if head in ["import", "from"]:
        auto tail = _context_tail(text, False, base)
        auto tokens = expression.tokenize(tail.text, base)
        auto separator = -1
        auto wanted = "as"
        if head == "from":
            wanted = "import"
        for i in range(len(tokens) - 1):
            if tokens[i].kind == "name" and tokens[i].text == wanted:
                separator = i
                break
        if separator < 1:
            _fail(segment.pos, "invalid " + head + " syntax")
        auto expr_index = _expression(p, tail.text[:tokens[separator].pos - base], base)
        list[str] exports = []
        auto cursor = separator + 1
        while cursor < len(tokens) - 1:
            auto name = tokens[cursor]
            if name.kind != "name" or not expression.identifier(name.text) or name.text.startswith("_"):
                _fail(name.pos, "invalid or private imported name")
            auto local = name.text
            cursor = cursor + 1
            if head == "from" and tokens[cursor].kind == "name" and tokens[cursor].text == "as":
                cursor = cursor + 1
                if tokens[cursor].kind != "name" or not expression.identifier(tokens[cursor].text):
                    _fail(tokens[cursor].pos, "invalid import alias")
                local = tokens[cursor].text
                cursor = cursor + 1
            exports.append(name.text)
            exports.append(local)
            if head == "import" or tokens[cursor].kind == "end":
                break
            if tokens[cursor].text != "," or tokens[cursor].kind != "symbol":
                _fail(tokens[cursor].pos, "expected import comma")
            cursor = cursor + 1
        if len(exports) == 0 or tokens[cursor].kind != "end":
            _fail(segment.pos, "invalid import names")
        auto flags = ""
        if tail.with_context:
            flags = "context"
        p.cursor = p.cursor + 1
        return _add(p, head, flags, expr_index, [], [], segment.pos, exports)
    if head == "block":
        auto tokens = expression.tokenize(text, base)
        if len(tokens) != 2 or tokens[0].kind != "name" or not expression.identifier(tokens[0].text):
            _fail(segment.pos, "expected block <name>")
        auto name = tokens[0].text
        p.cursor = p.cursor + 1
        auto body = _block(p, ["endblock"], depth + 1)
        auto ending = p.segments[p.cursor]
        if ending.kind != "tag" or not ending.text.strip() in ["endblock", "endblock " + name]:
            _fail(ending.pos, "expected endblock " + name)
        p.cursor = p.cursor + 1
        return _add(p, head, name, -1, body, [], segment.pos)
    if head == "macro":
        auto tokens = expression.tokenize(text, base)
        if len(tokens) < 4 or tokens[0].kind != "name" or not expression.identifier(tokens[0].text):
            _fail(segment.pos, "expected macro name(parameters)")
        auto name = tokens[0].text
        auto offset = tokens[1].pos - base
        auto parameters = expression.parameters(
            p.expressions,
            text[offset:],
            base + offset,
        )
        p.cursor = p.cursor + 1
        auto body = _block(p, ["endmacro"], depth + 1)
        _closing(p, "endmacro")
        return _add(
            p,
            head,
            name,
            -1,
            body,
            [],
            segment.pos,
            parameters.names,
            parameters.defaults,
        )
    # A call block creates a lexical callback macro, optionally with parameters.
    list[str] names = []
    list[int64] defaults = []
    auto offset = 0
    if text.startswith("("):
        auto tokens = expression.tokenize(text, base)
        auto nesting = 0
        auto end = -1
        for i in range(len(tokens) - 1):
            if tokens[i].kind == "symbol":
                if tokens[i].text == "(":
                    nesting = nesting + 1
                elif tokens[i].text == ")":
                    nesting = nesting - 1
                    if nesting == 0:
                        end = tokens[i].pos - base + 1
                        break
        if end < 0:
            _fail(segment.pos, "unterminated call parameters")
        auto parameters = expression.parameters(p.expressions, text[:end], base)
        names = parameters.names
        defaults = parameters.defaults
        offset = end
    auto expr_index = _expression(p, text[offset:], base + offset)
    if p.expressions.nodes[expr_index].kind != "call":
        _fail(segment.pos, "call block requires a macro invocation")
    p.cursor = p.cursor + 1
    auto body = _block(p, ["endcall"], depth + 1)
    _closing(p, "endcall")
    return _add(p, "call", "caller", expr_index, body, [], segment.pos, names, defaults)

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
            if head in ["extends", "include", "import", "from", "block", "macro", "call"]:
                body.append(_composition(p, segment, head, depth + 1))
            elif head == "if":
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
            elif head == "autoescape":
                auto offset = segment.text.find(head) + len(head)
                auto expr_index = _expression(
                    p,
                    segment.text[offset:],
                    segment.pos + offset,
                )
                p.cursor = p.cursor + 1
                auto nested = _block(p, ["endautoescape"], depth + 1)
                _closing(p, "endautoescape")
                body.append(
                    _add(p, "autoescape", "", expr_index, nested, [], segment.pos),
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

def compile(str source, str name = "<string>") -> Template:
    auto expressions = expression.Parser(tokens=[], cursor=0, nodes=[])
    auto parser = Parser(
        segments=_scan(source),
        cursor=0,
        nodes=[],
        expressions=expressions,
    )
    auto body = _block(parser, [], 0)
    list[str] blocks = []
    auto extending = 0
    for node in parser.nodes:
        if node.kind == "block":
            if node.text in blocks:
                _fail(node.pos, "duplicate block " + node.text)
            blocks.append(node.text)
        if node.kind == "extends":
            extending = extending + 1
            if extending > 1:
                _fail(node.pos, "multiple extends tags")
    for node in parser.nodes:
        if node.kind == "extends":
            auto top_level = False
            for index in body:
                if parser.nodes[index].kind == "extends":
                    top_level = True
            if not top_level:
                _fail(node.pos, "extends must be top-level")
    return Template(
        nodes=parser.nodes,
        expressions=parser.expressions.nodes,
        body=body,
        name=name,
    )

def escape(str text) -> str:
    return values.escape(text)

def _emit(RenderState state, str text, int64 pos):
    auto size = values.length(text)
    if size > 1048576 - state.budget.output:
        _fail(pos, "output exceeds 1048576 characters")
    state.budget.output = state.budget.output + size
    state.chunks.append(text)

def _context(dict[str, values.Value] source) -> dict[str, values.Value]:
    dict[str, values.Value] result = {}
    for key in source:
        result[key] = source[key]
    return result

def _render(
    RenderState state,
    Template template,
    list[int64] body,
    dict[str, values.Value] context,
    int64 depth,
):
    if depth > 64:
        _fail(0, "render nesting exceeds 64")
    for index in body:
        values.tick(state.budget)
        auto node = template.nodes[index]
        if node.kind == "text":
            _emit(state, node.text, node.pos)
            continue
        if node.kind in ["extends", "block", "macro", "include", "import", "from", "call"]:
            _render_composition(state, template, node, context, depth + 1)
            continue
        auto value = _evaluate(state, template, node.expression, context, depth + 1)
        if node.kind == "output":
            values.require(value, state.budget, node.pos)
            auto text = values.fragment(value, state.budget.autoescape, node.pos)
            _emit(state, text, node.pos)
        elif node.kind == "set":
            # Preserve undefined rather than assigning it the explicit null value.
            if not value.defined:
                _fail(node.pos, "cannot assign an undefined value")
            context[node.text] = value
        elif node.kind == "if":
            values.require(value, state.budget, node.pos)
            if values.truth(value):
                _render(state, template, node.body, context, depth + 1)
            else:
                _render(state, template, node.alternate, context, depth + 1)
        elif node.kind == "autoescape":
            auto enabled = False
            match value.data:
                case JsonValue.Bool(b):
                    enabled = b
                case _:
                    _fail(node.pos, "autoescape requires a boolean")
            auto previous = state.budget.autoescape
            state.budget.autoescape = enabled
            auto bindings = _context(context)
            _render(state, template, node.body, bindings, depth + 1)
            state.budget.autoescape = previous
        elif node.kind == "for":
            auto items = values.items(value, state.budget, node.pos)
            if len(items) > 100000:
                _fail(node.pos, "iteration exceeds 100000 items")
            if len(items) == 0:
                auto bindings = _context(context)
                _render(state, template, node.alternate, bindings, depth + 1)
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
                bindings["loop"] = values.value(JsonValue.Object(loop))
                _render(state, template, node.body, bindings, depth + 1)

def render_compiled(
    Template template,
    dict[str, JsonValue] context,
    bool autoescape = True,
    bool strict_undefined = False,
) -> str:
    auto env = environment({}, autoescape, strict_undefined)
    auto state = _state(env)
    auto bindings = _bindings(context)
    _execute(state, template, bindings, 0)
    return "".join(state.chunks)

def render(
    str source,
    dict[str, JsonValue] context,
    bool autoescape = True,
    bool strict_undefined = False,
) -> str:
    return render_compiled(compile(source), context, autoescape, strict_undefined)

def _evaluate(
    RenderState state,
    Template template,
    int64 index,
    dict[str, values.Value] context,
    int64 depth = 0,
    int64 caller = -1,
) -> values.Value:
    auto budget = state.budget
    auto nodes = template.expressions
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
        auto base = _evaluate(state, template, node.children[0], context, depth + 1)
        auto key = _evaluate(state, template, node.children[1], context, depth + 1)
        if base.namespace:
            auto name = _name(key, node.pos)
            if name in base.members:
                return state.members[base.members[name]]
            return values.undefined()
        return values.lookup(base, key, node.pos, budget)
    if node.kind == "call":
        auto target = _evaluate(state, template, node.children[0], context, depth + 1)
        list[values.Value] arguments = []
        for i in range(1, len(node.children)):
            arguments.append(
                _evaluate(state, template, node.children[i], context, depth + 1),
            )
        return _invoke(
            state,
            target,
            arguments,
            node.names,
            context,
            depth + 1,
            node.pos,
            caller,
        )
    if node.kind in ["filter", "test"]:
        auto input = _evaluate(state, template, node.children[0], context, depth + 1)
        list[values.Value] arguments = []
        for i in range(1, len(node.children)):
            arguments.append(
                _evaluate(state, template, node.children[i], context, depth + 1),
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
        auto operand = _evaluate(state, template, node.children[0], context, depth + 1)
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
        auto left = _evaluate(state, template, node.children[0], context, depth + 1)
        for i in range(len(operators)):
            auto right = _evaluate(
                state,
                template,
                node.children[i + 1],
                context,
                depth + 1,
            )
            if not values.compare(operators[i], left, right, budget, node.pos):
                return values.value(JsonValue.Bool(False))
            left = right
        return values.value(JsonValue.Bool(True))
    auto left = _evaluate(state, template, node.children[0], context, depth + 1)
    if node.text in ["and", "or"]:
        values.require(left, budget, node.pos)
    if node.text == "and" and not values.truth(left):
        return left
    if node.text == "or" and values.truth(left):
        return left
    auto right = _evaluate(state, template, node.children[1], context, depth + 1)
    if node.text in ["and", "or"]:
        return right
    return values.arithmetic(node.text, left, right, node.pos, budget)

# Loader names are relative to an explicit namespace, never to the current template.
def normalize_name(str name) -> str:
    if len(name) == 0 or name.startswith("/") or "\\" in name or ":" in name:
        _fail(0, "unsafe template name: " + name)
    list[str] parts = []
    for part in name.split("/"):
        if part == "..":
            _fail(0, "template name escapes loader root: " + name)
        for c in part:
            if ord(c) < 32 or ord(c) == 127:
                _fail(0, "control character in template name")
        if part != "" and part != ".":
            parts.append(part)
    if len(parts) == 0 or values.length(name) > 1024:
        _fail(0, "invalid template name")
    return "/".join(parts)

def environment(
    dict[str, str] sources,
    bool autoescape = True,
    bool strict_undefined = False,
) -> Environment:
    dict[str, str] copied = {}
    for name in sources:
        auto key = normalize_name(name)
        if key in copied:
            _fail(0, "duplicate normalized template name: " + key)
        copied[key] = sources[name]
    return Environment(
        sources=copied,
        root="",
        cache={},
        globals={},
        autoescape=autoescape,
        strict_undefined=strict_undefined,
    )

def filesystem_environment(
    str root,
    bool autoescape = True,
    bool strict_undefined = False,
) -> Environment:
    if len(root) == 0 or "\x00" in root:
        _fail(0, "invalid filesystem loader root")
    auto absolute = root
    if not absolute.startswith("/"):
        absolute = os.path_join(os.getcwd(), root)
    if not fs.is_dir(absolute):
        _fail(0, "filesystem loader root is not a directory: " + root)
    auto env = environment({}, autoescape, strict_undefined)
    env.root = absolute
    return env

def invalidate(Environment env):
    env.cache = {}

def set_source(Environment env, str name, str source):
    env.sources[normalize_name(name)] = source
    # Invalidate dependents as well; imported output is never cached.
    invalidate(env)

def _exists(Environment env, str name) -> bool:
    if name in env.sources:
        return True
    return len(env.root) > 0 and fs.is_file(os.path_join(env.root, name))

def get_template(Environment env, str name) -> Template:
    auto key = normalize_name(name)
    if key in env.cache:
        return env.cache[key]
    auto source = ""
    if key in env.sources:
        source = env.sources[key]
    elif len(env.root) > 0 and fs.is_file(os.path_join(env.root, key)):
        auto path = os.path_join(env.root, key)
        if fs.size(path) > 4194304:
            _fail(0, "template file exceeds 4194304 bytes: " + key)
        source = fs.read_file(path)
    else:
        _fail(0, "template not found: " + key)
    try:
        auto template = compile(source, key)
        if len(env.cache) >= 256:
            invalidate(env)
        env.cache[key] = template
        return template
    except Exception as e:
        _fail(0, "template " + key + ": " + str(e))
    return compile("")

def _bindings(dict[str, JsonValue] source) -> dict[str, values.Value]:
    dict[str, values.Value] result = {}
    for key in source:
        result[key] = values.value(source[key])
    return result

def _state(Environment env) -> RenderState:
    return RenderState(
        environment=env,
        budget=values.Budget(
            steps=0,
            output=0,
            strict=env.strict_undefined,
            autoescape=env.autoescape,
        ),
        chunks=[],
        callables=[],
        members=[],
        blocks=[],
        active=[],
        calls=0,
    )

def render_named(Environment env, str name, dict[str, JsonValue] context) -> str:
    auto state = _state(env)
    auto bindings = _bindings(env.globals)
    for key in context:
        bindings[key] = values.value(context[key])
    _execute(state, get_template(env, name), bindings, 0)
    return "".join(state.chunks)

def _name(values.Value v, int64 pos) -> str:
    if v.defined:
        match v.data:
            case JsonValue.Str(s):
                return s
            case _:
                _fail(pos, "expected template or member name string")
    _fail(pos, "undefined template or member name")
    return ""

def _reference(RenderState state, Macro macro) -> values.Value:
    if len(state.callables) >= 10000:
        _fail(0, "render exceeds 10000 macro references")
    state.callables.append(macro)
    auto result = values.value(JsonValue.Null)
    result.callable = len(state.callables) - 1
    return result

def _macro(
    RenderState state,
    Template template,
    Node node,
    dict[str, values.Value] context,
) -> values.Value:
    return _reference(
        state,
        Macro(
            kind="macro",
            name=node.text,
            template=template,
            body=node.body,
            parameters=node.names,
            defaults=node.defaults,
            closure=context,
            block=-1,
            autoescape=state.budget.autoescape,
            blocks=state.blocks,
        ),
    )

def _capture(
    RenderState state,
    Template template,
    list[int64] body,
    dict[str, values.Value] context,
    int64 depth,
) -> str:
    auto previous = state.chunks
    auto size = state.budget.output
    state.chunks = []
    state.budget.output = 0
    _render(state, template, body, context, depth + 1)
    auto result = "".join(state.chunks)
    state.chunks = previous
    state.budget.output = size
    return result

def _invoke(
    RenderState state,
    values.Value target,
    list[values.Value] arguments,
    list[str] names,
    dict[str, values.Value] context,
    int64 depth,
    int64 pos,
    int64 caller,
) -> values.Value:
    values.tick(state.budget)
    if target.callable < 0 or target.callable >= len(state.callables):
        _fail(pos, "only template macros, caller, and super can be called")
    state.calls = state.calls + 1
    if state.calls > 64 or depth > 64:
        _fail(pos, "macro recursion exceeds 64")
    auto macro = state.callables[target.callable]
    if macro.kind == "super":
        if len(arguments) != 0:
            _fail(pos, "super takes no arguments")
        auto previous = state.chunks
        auto size = state.budget.output
        state.chunks = []
        state.budget.output = 0
        _render_block(state, macro.name, macro.block, macro.closure, depth + 1)
        auto result = "".join(state.chunks)
        state.chunks = previous
        state.budget.output = size
        state.calls = state.calls - 1
        return values.marked(result, state.budget.autoescape)
    if len(arguments) > len(macro.parameters):
        _fail(pos, "macro " + macro.name + ": too many arguments")
    auto calling_policy = state.budget.autoescape
    auto previous_blocks = state.blocks
    state.budget.autoescape = macro.autoescape
    state.blocks = macro.blocks
    auto bindings = _context(macro.closure)
    list[str] supplied = []
    auto named = False
    for i in range(len(arguments)):
        auto key = names[i]
        if key == "":
            if named:
                _fail(
                    pos,
                    "macro " + macro.name + ": positional argument after keyword",
                )
            key = macro.parameters[i]
        else:
            named = True
        if not key in macro.parameters or key in supplied:
            _fail(pos, "macro " + macro.name + ": unknown or duplicate argument " + key)
        supplied.append(key)
        bindings[key] = arguments[i]
    for i in range(len(macro.parameters)):
        auto key = macro.parameters[i]
        if not key in supplied:
            if macro.defaults[i] >= 0:
                bindings[key] = _evaluate(
                    state,
                    macro.template,
                    macro.defaults[i],
                    bindings,
                    depth + 1,
                )
            else:
                bindings[key] = values.undefined()
    if caller >= 0:
        auto callback = values.value(JsonValue.Null)
        callback.callable = caller
        bindings["caller"] = callback
    try:
        auto result = _capture(state, macro.template, macro.body, bindings, depth + 1)
        state.calls = state.calls - 1
        state.budget.autoescape = calling_policy
        state.blocks = previous_blocks
        return values.marked(result, calling_policy)
    except Exception as e:
        _fail(pos, "macro " + macro.name + " in " + macro.template.name + ": " + str(e))
    return values.undefined()

def _render_block(
    RenderState state,
    str name,
    int64 after,
    dict[str, values.Value] context,
    int64 depth,
):
    if depth > 64:
        _fail(0, "block nesting exceeds 64")
    for i in range(after + 1, len(state.blocks)):
        auto block = state.blocks[i]
        if block.name == name:
            auto bindings = _context(context)
            bindings["super"] = _reference(
                state,
                Macro(
                    kind="super",
                    name=name,
                    template=block.template,
                    body=[],
                    parameters=[],
                    defaults=[],
                    closure=context,
                    block=i,
                    autoescape=state.budget.autoescape,
                    blocks=state.blocks,
                ),
            )
            _render(
                state,
                block.template,
                block.template.nodes[block.node].body,
                bindings,
                depth + 1,
            )
            return
    _fail(0, "no parent block for super: " + name)

def _import(
    RenderState state,
    Template template,
    Node node,
    dict[str, values.Value] context,
    int64 depth,
):
    auto source = _name(
        _evaluate(state, template, node.expression, context, depth + 1),
        node.pos,
    )
    auto bindings = _bindings(state.environment.globals)
    if node.text == "context":
        bindings = _context(context)
    auto previous = state.chunks
    auto size = state.budget.output
    state.chunks = []
    state.budget.output = 0
    auto exported = _execute(
        state,
        get_template(state.environment, source),
        bindings,
        depth + 1,
    )
    state.chunks = previous
    state.budget.output = size
    if node.kind == "import":
        auto namespace = values.value(JsonValue.Object({}))
        namespace.namespace = True
        for key in exported:
            if not key.startswith("_") and key in bindings:
                if len(state.members) >= 10000:
                    _fail(node.pos, "import exceeds 10000 exported values")
                state.members.append(bindings[key])
                namespace.members[key] = len(state.members) - 1
        context[node.names[1]] = namespace
    else:
        auto i = 0
        while i < len(node.names):
            auto name = node.names[i]
            if not name in bindings or not name in exported:
                _fail(node.pos, "template " + source + " does not export " + name)
            context[node.names[i + 1]] = bindings[name]
            i = i + 2

def _render_composition(
    RenderState state,
    Template template,
    Node node,
    dict[str, values.Value] context,
    int64 depth,
):
    if depth > 64:
        _fail(node.pos, "composition nesting exceeds 64")
    if node.kind == "macro":
        context[node.text] = _macro(state, template, node, context)
    elif node.kind == "block":
        _render_block(state, node.text, -1, context, depth + 1)
    elif node.kind == "include":
        auto name = normalize_name(
            _name(
                _evaluate(state, template, node.expression, context, depth + 1),
                node.pos,
            ),
        )
        if ":ignore" in node.text and not _exists(state.environment, name):
            return
        auto bindings = _bindings(state.environment.globals)
        if node.text.startswith("context"):
            bindings = _context(context)
        _execute(state, get_template(state.environment, name), bindings, depth + 1)
    elif node.kind in ["import", "from"]:
        _import(state, template, node, context, depth + 1)
    elif node.kind == "call":
        auto callback = _macro(state, template, node, context)
        auto result = _evaluate(
            state,
            template,
            node.expression,
            context,
            depth + 1,
            callback.callable,
        )
        _emit(
            state,
            values.fragment(result, state.budget.autoescape, node.pos),
            node.pos,
        )

def _execute(
    RenderState state,
    Template template,
    dict[str, values.Value] context,
    int64 depth,
) -> list[str]:
    if depth > 32:
        _fail(0, "template composition exceeds 32 levels")
    auto saved_blocks = state.blocks
    auto saved_policy = state.budget.autoescape
    state.budget.autoescape = state.environment.autoescape
    state.blocks = []
    dict[str, bool] declared = {}
    auto active_count = len(state.active)
    auto current = template
    auto chain = 0
    try:
        while True:
            values.tick(state.budget)
            if current.name in state.active:
                _fail(
                    0,
                    "template cycle: " + " -> ".join(state.active) + " -> " + current.name,
                )
            if chain >= 32:
                _fail(0, "inheritance exceeds 32 templates")
            chain = chain + 1
            state.active.append(current.name)
            _exports(current, current.body, declared)
            for i in range(len(current.nodes)):
                if current.nodes[i].kind == "block":
                    state.blocks.append(
                        Block(name=current.nodes[i].text, template=current, node=i),
                    )
            auto parent = -1
            for index in current.body:
                if current.nodes[index].kind == "extends":
                    parent = current.nodes[index].expression
            if parent < 0:
                break
            # Child setup executes declarations; output comes from the parent layout.
            for index in current.body:
                auto node = current.nodes[index]
                if node.kind in ["set", "macro", "import", "from"]:
                    _render(state, current, [index], context, depth + 1)
                elif node.kind == "text" and len(node.text.strip()) > 0:
                    _fail(node.pos, "extending templates require output inside blocks")
                elif not node.kind in ["text", "block", "extends"]:
                    _fail(
                        node.pos,
                        "unsupported top-level tag in extending template: " + node.kind,
                    )
            auto parent_name = _name(
                _evaluate(state, current, parent, context, depth + 1),
                0,
            )
            current = get_template(state.environment, parent_name)
        _render(state, current, current.body, context, depth + 1)
        state.active = state.active[:active_count]
        state.blocks = saved_blocks
        state.budget.autoescape = saved_policy
        list[str] exported = []
        for key in declared:
            exported.append(key)
        return exported
    except Exception as e:
        _fail(0, "template " + current.name + ": " + str(e))
    return []


def _exports(Template template, list[int64] body, dict[str, bool] names):
    for index in body:
        auto node = template.nodes[index]
        if node.kind in ["macro", "set"]:
            names[node.text] = True
        elif node.kind == "import":
            names[node.names[1]] = True
        elif node.kind == "from":
            auto i = 1
            while i < len(node.names):
                names[node.names[i]] = True
                i = i + 2
        elif node.kind == "if":
            _exports(template, node.body, names)
            _exports(template, node.alternate, names)
