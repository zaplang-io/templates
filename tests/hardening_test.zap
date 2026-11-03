import templates

def bad(str source, dict[str, JsonValue] context, str label):
    auto caught = False
    try:
        auto output = templates.render(source, context)
    except Exception as e:
        if not label in str(e):
            raise "expected [" + label + "] in [" + str(e) + "]"
        caught = True
    if not caught:
        raise "expected bounded error: " + source

def main():
    dict[str, JsonValue] context = {}
    # Long Unicode templates, strings, and comments must scan without repeated
    # whole-string codepoint slicing. These also exercise GC while ASTs are live.
    auto text = "é😀"
    for i in range(15):
        text = text + text
    assert templates.render(text + "{{'終'}}", context) == text + "終"
    assert templates.render("{{'" + text + "'}}", context) == text
    assert templates.render("{#" + text + "#}done", context) == "done"
    auto source = "{{'x'}}"
    auto expected = "x"
    for i in range(12):
        source = source + source
        expected = expected + expected
    auto compiled = templates.compile(source)
    for i in range(5):
        assert templates.render_compiled(compiled, context) == expected
    # Long repeated-prefix replacement is linear and non-overlapping.
    auto prefix = "a"
    for i in range(10):
        prefix = prefix + prefix
    context["pattern"] = JsonValue.Str(prefix + "c")
    context["text"] = JsonValue.Str(prefix + prefix + prefix + prefix + "b")
    assert templates.render("{{text|replace(pattern,'x')}}", context) == prefix + prefix + prefix + prefix + "b"
    context["text"] = JsonValue.Str("aaaaa")
    assert templates.render("{{text|replace('aa','X')}}", context) == "XXa"
    assert templates.render("{{text|replace('aa','X',1)}}", context) == "Xaaa"
    assert templates.render("{{text|replace('','X',2)}}", context) == "XaXaaaa"
    context["text"] = JsonValue.Str("😀é😀")
    assert templates.render("{{text|replace('😀','<')}}", context) == "&lt;é&lt;"
    auto deep = "1"
    for i in range(70):
        deep = "[" + deep + "]"
    context["deep"] = json.loads(deep)
    bad("{{deep == deep}}", context, "64")
    bad("{{deep|tojson}}", context, "64")
    source = "{{ 1"
    for i in range(150):
        source = source + "+1"
    bad(source + " }}", context, "128")
    auto huge = "x"
    for i in range(20):
        huge = huge + huge
    context["huge"] = JsonValue.Str(huge)
    bad("{% macro f() %}{{huge}}{% endmacro %}{{f()}}x", context, "output exceeds")
    list[JsonValue] items = []
    for i in range(100001):
        items.append(JsonValue.Int(i))
    context["items"] = JsonValue.Array(items)
    bad("{% for item in items %}{{item}}{% endfor %}", context, "100000 items")
    bad("{{items|list|length}}", context, "100000 items")
    dict[str, str] files = {}
    for i in range(33):
        files[str(i)] = "{% extends '" + str(i + 1) + "' %}"
    files["33"] = "base"
    auto env = templates.environment(files)
    auto caught = False
    try:
        auto output = templates.render_named(env, "0", context)
    except Exception as e:
        assert "32 templates" in str(e)
        caught = True
    assert caught
    # Cached syntax is bounded independently from a loader's source namespace.
    files = {}
    for i in range(270):
        files[str(i)] = "x"
    env = templates.environment(files)
    for i in range(270):
        assert templates.render_named(env, str(i), context) == "x"
        assert len(env.cache) <= 256
    # Diagnostics include the failing file and a source character offset.
    templates.set_source(env, "broken", "😀{{ 1 + }}")
    caught = False
    try:
        auto template = templates.get_template(env, "broken")
    except Exception as e:
        assert "broken" in str(e)
        assert "character 9" in str(e)
        caught = True
    assert caught
    print(
        "large Unicode, replacement, nesting, expansion, iteration, cache bounds: PASS",
    )
