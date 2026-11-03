import templates

def main():
    dict[str, JsonValue] context = {
        "name": JsonValue.Str("<Zoë 😀>"),
        "items": json.loads("[1,2,3]"),
        "user": json.loads("{\"name\":\"Ada\"}"),
    }
    assert templates.render("Hello {{ name }}!", context) == "Hello &lt;Zoë 😀&gt;!"
    assert templates.render("{{name}}", context, False) == "<Zoë 😀>"
    assert templates.render("{{user.name}}/{{ user['name'] }}", context) == "Ada/Ada"
    assert templates.render("{{items[-1]}}/{{name[5]}}", context) == "3/😀"
    assert templates.render("{{missing}}:{{missing.deep}}:{{none}}", context) == "::None"
    assert templates.render("{{ 1 + 2 * 3 }}:{{ (1 + 2) * 3 }}:{{ -7 // 3 }}:{{ -7 % 3 }}", context) == "7:9:-3:2"
    assert templates.render("{{ 1 < 2 < 3 }}:{{ 3 < 2 < missing.bad }}", context) == "True:False"
    assert templates.render("{{ false and (1 / 0) }}:{{ 'ok' or (1 / 0) }}", context) == "False:ok"
    assert templates.render("{{ not 1 > 2 }}:{{ 2 in items }}:{{ 4 not in items }}", context) == "True:True:True"
    assert templates.render("{{ 'or' }}:{{ 'not' }}:{{ '}}' }}", context) == "or:not:}}"
    assert templates.render("{{'a' ~ 1 ~ true}}", context) == "a1True"
    assert templates.render("a {# ignored {{ #} b", context) == "a  b"
    assert templates.render("a \n {{- 'b' -}} \n c", context) == "abc"
    assert templates.render("a \n {#- comment -#} \n b", context) == "ab"
    assert templates.render("{{'a\\nb\\t\\\"'}}", context) == "a\nb\t&#34;"
    assert templates.escape("&<>\"'") == "&amp;&lt;&gt;&#34;&#39;"
    assert templates.render("{% if missing %}bad{% elif user.name == 'Ada' %}yes{% else %}no{% endif %}", context) == "yes"
    assert templates.render("{% if true %}a{% if false %}b{% else %}c{% endif %}{% endif %}", context) == "ac"
    assert templates.render("{% for x in items %}{{loop.index}}={{x}};{% else %}empty{% endfor %}", context) == "1=1;2=2;3=3;"
    assert templates.render("{% for x in missing %}bad{% else %}empty{% endfor %}", context) == "empty"
    assert templates.render("{% for c in name %}{{c}}{% endfor %}", context) == "&lt;Zoë 😀&gt;"
    assert templates.render("{% for key in user %}{{key}}{% endfor %}", context) == "name"
    assert templates.render("{% set x = 7 %}{% for x in items %}{% set x = 9 %}{{x}}{% endfor %}{{x}}", context) == "9997"
    assert templates.render("{% if true %}{% set x = 4 %}{% endif %}{{x}}", context) == "4"
    assert not "x" in context
    assert not "loop" in context
    assert templates.render("{% for x in items %}{{loop.first}}/{{loop.last}}/{{loop.revindex}}/{{loop.length}};{% endfor %}", context) == "True/False/3/3;False/False/2/3;False/True/1/3;"
    assert templates.render("{% for x in items %}{% for y in items %}{{loop.index}}{% endfor %}{{loop.index}}{% endfor %}", context) == "123112321233"
    context["empty"] = json.loads("[]")
    context["a"] = json.loads("{\"x\":1,\"y\":[2]}")
    context["b"] = json.loads("{\"y\":[2.0],\"x\":1.0}")
    assert templates.render("{{a == b}}:{{true == 1}}:{{none == missing}}", context) == "True:False:False"
    assert templates.render("{{user.name in 'Ada Lovelace'}}:{{'name' in user}}", context) == "True:True"
    assert templates.render("{% set v = 5 %}{% for x in items %}{{v}}{% set v = 9 %}{% endfor %}{{v}}", context) == "5555"
    assert templates.render("{% set v = 5 %}{% for x in empty %}bad{% else %}{% set v = 9 %}{{v}}{% endfor %}{{v}}", context) == "95"
    assert templates.render("{{9223372036854775807 > 9223372036854775806}}", context) == "True"
    assert templates.render("{{9007199254740993 == 9007199254740992.0}}", context) == "False"
    auto indexed = templates.render(
        "{{name[-1]}}:{{items[99]}}:{{missing == other}}",
        context,
    )
    if indexed != "&gt;::True":
        raise "unexpected indexed/undefined result: " + indexed
    auto compiled = templates.compile("{{value}}")
    dict[str, JsonValue] first = {"value": JsonValue.Int(1)}
    dict[str, JsonValue] second = {"value": JsonValue.Int(2)}
    assert templates.render_compiled(compiled, first) == "1"
    assert templates.render_compiled(compiled, second) == "2"
    assert templates.render_compiled(compiled, first) == "1"
    auto recovering = templates.compile("{{ 4 / divisor }}")
    dict[str, JsonValue] zero = {"divisor": JsonValue.Int(0)}
    auto caught = False
    try:
        auto output = templates.render_compiled(recovering, zero)
    except Exception:
        caught = True
    assert caught
    dict[str, JsonValue] nonzero = {"divisor": JsonValue.Int(2)}
    assert templates.render_compiled(recovering, nonzero) == "2.0"
    print("rendering: PASS")
