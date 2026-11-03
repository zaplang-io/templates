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
    auto compiled = templates.compile("{{value}}")
    dict[str, JsonValue] first = {"value": JsonValue.Int(1)}
    dict[str, JsonValue] second = {"value": JsonValue.Int(2)}
    assert templates.render_compiled(compiled, first) == "1"
    assert templates.render_compiled(compiled, second) == "2"
    assert templates.render_compiled(compiled, first) == "1"
    print("rendering: PASS")
