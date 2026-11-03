import templates

def expect(str source, str expected):
    dict[str, JsonValue] context = {
        "html": JsonValue.Str("<b>&</b>"),
        "items": json.loads("[\"<a>\",\"<b>\"]"),
    }
    auto actual = templates.render(source, context)
    if actual != expected:
        raise "markup result for " + source + ": [" + actual + "] expected [" + expected + "]"

def bad(str source, str label, bool strict = False):
    auto caught = False
    dict[str, JsonValue] context = {
        "items": json.loads("[]"),
        "html": JsonValue.Str("<b>"),
    }
    try:
        auto output = templates.render(source, context, True, strict)
    except Exception as e:
        assert "TemplateError at character " in str(e)
        if not label in str(e):
            raise "missing error label " + label + ": " + str(e)
        caught = True
    if not caught:
        raise "expected error: " + source

def main():
    # Transformations clear trust, including replacement content shaped like HTML.
    expect("{{html|safe|upper}}", "&lt;B&gt;&amp;&lt;/B&gt;")
    expect("{{html|safe|lower}}", "&lt;b&gt;&amp;&lt;/b&gt;")
    expect("{{html|safe|trim}}", "&lt;b&gt;&amp;&lt;/b&gt;")
    expect("{{html|safe|replace('b','script')}}", "&lt;script&gt;&amp;&lt;/script&gt;")
    expect("{{('a'|safe)|replace('a',html)}}", "&lt;b&gt;&amp;&lt;/b&gt;")
    expect("{{html|safe is escaped}}/{{html|safe|lower is escaped}}", "True/False")
    expect(
        "{% set s = html|safe %}{{s}}|{{s ~ html}}",
        "<b>&</b>|<b>&</b>&lt;b&gt;&amp;&lt;/b&gt;",
    )
    expect(
        "{{items|map('safe')|select('string')|join(html)}}",
        "<a>&lt;b&gt;&amp;&lt;/b&gt;<b>",
    )
    expect("{{items|map('escape')|last}}", "&lt;b&gt;")
    expect("{{(items|map('escape')|list)[0]}}", "&lt;a&gt;")
    expect("{{items|map('safe')|reject('equalto','<a>')|join}}", "<b>")
    expect(
        "{% autoescape false %}{{html}}{% autoescape true %}{{html}}{% endautoescape %}{% endautoescape %}{{html}}",
        "<b>&</b>&lt;b&gt;&amp;&lt;/b&gt;&lt;b&gt;&amp;&lt;/b&gt;",
    )
    # Compilation must validate call syntax even inside inactive branches.
    bad("{% if false %}{{html|missing}}{% endif %}", "filter missing")
    bad("{{html|replace('a')}}", "filter replace")
    bad("{{html|join(d='a',d='b')}}", "filter join")
    bad("{{html|join(d='a','b')}}", "filter join")
    bad("{{html|join(1)}}", "filter join")
    bad("{{html|trim(chars=3)}}", "filter trim")
    bad("{{html|round}}", "filter round")
    bad("{{html|sort(reverse=1)}}", "filter sort")
    bad("{{html|select('unknown')}}", "test unknown")
    bad("{{items|select('unknown')}}", "test unknown")
    bad("{{items|map('unknown')}}", "filter unknown")
    bad("{{items|map}}", "filter map")
    bad("{{items|map(attribute='name',argument=1)}}", "filter map")
    bad("{{items|map('map')}}", "filter map")
    bad("{{html is unknown}}", "test unknown")
    bad("{{html is defined(1)}}", "test defined")
    bad("{{html is even}}", "test even")
    bad("{% autoescape 'true' %}x{% endautoescape %}", "autoescape")
    bad("{% autoescape false %}x", "endautoescape")
    bad("{{missing}}", "strict", True)
    bad("{{missing ~ 'x'}}", "strict", True)
    bad("{{missing or 'x'}}", "strict", True)
    bad("{{missing.x|default('x')}}", "strict", True)
    bad("{{missing|safe}}", "filter safe", True)
    bad("{{missing|int}}", "filter int")
    bad("{{missing|tojson}}", "filter tojson")
    dict[str, JsonValue] context = {"html": JsonValue.Str("<b>")}
    auto compiled = templates.compile(
        "{% autoescape false %}{{html}}{% endautoescape %}{{missing|default('x')}}",
    )
    assert templates.render_compiled(compiled, context, True, True) == "<b>x"
    assert templates.render_compiled(compiled, context, True, False) == "<b>x"
    auto failed = templates.compile(
        "{% autoescape false %}{{missing}}{% endautoescape %}{{html}}",
    )
    auto caught = False
    try:
        auto output = templates.render_compiled(failed, context, True, True)
    except Exception:
        caught = True
    assert caught
    assert templates.render_compiled(failed, context) == "&lt;b&gt;"
    # Positions remain codepoint-based after Unicode source text.
    caught = False
    try:
        auto output = templates.render("😀{{html|missing}}", context)
    except Exception as e:
        assert "character 9" in str(e)
        caught = True
    assert caught
    print("markup, policies, and argument errors: PASS")
