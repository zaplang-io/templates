import templates

def bad_syntax(str source):
    auto caught = False
    try:
        auto compiled = templates.compile(source)
    except Exception as e:
        assert "TemplateError at character " in str(e)
        caught = True
    if not caught:
        raise "expected syntax error: " + source

def bad_render(str source):
    auto caught = False
    dict[str, JsonValue] context = {}
    try:
        auto output = templates.render(source, context)
    except Exception as e:
        assert "TemplateError at character " in str(e)
        caught = True
    if not caught:
        raise "expected rendering error: " + source

def main():
    bad_syntax("{{")
    bad_syntax("{#")
    bad_syntax("{%")
    bad_syntax("{{ 'broken }}")
    bad_syntax("{{ 'bad\\q' }}")
    bad_syntax("{{ }}")
    bad_syntax("{{ 1 + }}")
    bad_syntax("{{ 01 }}")
    bad_syntax("{{ 1. }}")
    bad_syntax("{{ user. }}")
    bad_syntax("{{ user[1 }}")
    bad_render("{{ user() }}")
    bad_syntax("{{ name | unknown }}")
    bad_syntax("{% unknown %}")
    bad_syntax("{% else %}")
    bad_syntax("{% endif %}")
    bad_syntax("{% if true %}unclosed")
    bad_syntax("{% if true %}ok{% else extra %}bad{% endif %}")
    bad_syntax("{% if false %}{{ 1 + }}{% endif %}")
    bad_syntax("{% if true %}ok{% else %}{{1 +}}{% endif %}")
    bad_syntax("{% for x in name %}unclosed")
    bad_syntax("{% for x in name %}{% endif %}")
    bad_syntax("{% for loop in name %}{% endfor %}")
    bad_syntax("{% for x name %}{% endfor %}")
    bad_syntax("{% set x %}")
    bad_syntax("{% set x.y = 1 %}")
    bad_syntax("{{ 1 not 2 }}")
    bad_syntax("{{ 1 and }}")
    bad_syntax("{{ 'and' 'or' }}")
    bad_render("{{ 1 / 0 }}")
    bad_render("{{ 1 // 0 }}")
    bad_render("{{ 1 % 0 }}")
    bad_render("{{ missing + 1 }}")
    bad_render("{{ none < 1 }}")
    bad_render("{{ 'x' + 1 }}")
    bad_render("{{ 1 in 2 }}")
    bad_render("{{ 'x'[true] }}")
    bad_render("{{ none.x }}")
    bad_render("{% for x in 1 %}bad{% endfor %}")
    bad_render("{% set x = missing %}")
    bad_render("{{ 9007199254740991 + 1 }}")
    auto source = ""
    for i in range(70):
        source = source + "{% if true %}"
    for i in range(70):
        source = source + "{% endif %}"
    bad_syntax(source)
    source = "{{ "
    for i in range(70):
        source = source + "("
    source = source + "1"
    for i in range(70):
        source = source + ")"
    bad_syntax(source + " }}")
    source = ""
    for i in range(10001):
        source = source + "{{0}}"
    bad_syntax(source)
    source = "x"
    for i in range(21):
        source = source + source
    bad_syntax(source)
    # Evaluation budget and output limits are independent of syntax limits.
    auto items = "[0"
    for i in range(400):
        items = items + ",0"
    items = items + "]"
    dict[str, JsonValue] context = {"items": json.loads(items)}
    auto caught = False
    try:
        auto output = templates.render(
            "{% for x in items %}{% for y in items %}{{x}}{% endfor %}{% endfor %}",
            context,
        )
    except Exception as e:
        assert "100000 steps" in str(e)
        caught = True
    assert caught
    auto huge = "x"
    for i in range(20):
        huge = huge + huge
    context["huge"] = JsonValue.Str(huge)
    caught = False
    try:
        auto output = templates.render("{{huge}}x", context)
    except Exception as e:
        assert "output exceeds" in str(e)
        caught = True
    assert caught
    print("errors and limits: PASS")
