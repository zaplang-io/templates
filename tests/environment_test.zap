import templates

def bad_name(str name):
    auto caught = False
    try:
        auto normalized = templates.normalize_name(name)
    except Exception as e:
        assert "TemplateError" in str(e)
        caught = True
    if not caught:
        raise "unsafe name accepted: " + name

def bad_render(dict[str, str] sources, str root, str message):
    auto env = templates.environment(sources)
    dict[str, JsonValue] context = {}
    auto caught = False
    try:
        auto output = templates.render_named(env, root, context)
    except Exception as e:
        if not message in str(e):
            raise "expected error label [" + message + "] in [" + str(e) + "]"
        caught = True
    if not caught:
        raise "expected composition error: " + root

def main():
    dict[str, JsonValue] empty = {}
    assert templates.normalize_name("./dir//page.html") == "dir/page.html"
    bad_name("")
    bad_name(".")
    bad_name("..")
    bad_name("../outside")
    bad_name("dir/../../outside")
    bad_name("/etc/passwd")
    bad_name("C:/windows")
    bad_name("https://example.com/page")
    bad_name("dir\\outside")
    bad_name("bad\x00name")
    bad_name("bad\nname")
    dict[str, str] sources = {"main": "{% include 'part' %}", "part": "A"}
    auto env = templates.environment(sources)
    # Source dictionaries are copied on environment construction.
    sources["part"] = "changed outside"
    assert templates.render_named(env, "main", empty) == "A"
    assert len(env.cache) == 2
    templates.set_source(env, "part", "B")
    assert len(env.cache) == 0
    assert templates.render_named(env, "./main", empty) == "B"
    assert len(env.cache) == 2
    templates.invalidate(env)
    assert len(env.cache) == 0
    env.globals["global_value"] = JsonValue.Str("<G>")
    templates.set_source(env, "main", "{{global_value}}/{{local|default('none')}}")
    dict[str, JsonValue] context = {"local": JsonValue.Str("L")}
    assert templates.render_named(env, "main", context) == "&lt;G&gt;/L"
    assert templates.render_named(env, "main", empty) == "&lt;G&gt;/none"
    context["global_value"] = JsonValue.Str("override")
    assert templates.render_named(env, "main", context) == "override/L"
    assert not "global_value" in empty
    templates.set_source(env, "lib", "{% macro f() %}{{global_value}}{% endmacro %}")
    templates.set_source(env, "main", "{% import 'lib' as lib %}{{lib.f()}}")
    assert templates.render_named(env, "main", context) == "&lt;G&gt;"
    templates.set_source(
        env,
        "main",
        "{% import 'lib' as lib with context %}{{lib.f()}}",
    )
    assert templates.render_named(env, "main", context) == "override"
    bad_render({"main": "{% include '../outside' ignore missing %}"}, "main", "root")
    bad_render({"main": "{% include '/etc/passwd' ignore missing %}"}, "main", "unsafe")
    bad_render({"main": "{% extends 'main' %}"}, "main", "cycle")
    bad_render(
        {"main": "{% extends 'b' %}", "b": "{% extends 'main' %}"},
        "main",
        "cycle",
    )
    bad_render({"main": "{% include 'main' %}"}, "main", "cycle")
    bad_render(
        {"main": "{% import 'b' as b %}", "b": "{% import 'main' as a %}"},
        "main",
        "cycle",
    )
    bad_render(
        {"main": "{% include 'bad' ignore missing %}", "bad": "{% if %}"},
        "main",
        "bad",
    )
    bad_render({"main": "{% macro f() %}{{f()}}{% endmacro %}{{f()}}"}, "main", "64")
    bad_render({"main": "{{ host() }}"}, "main", "only template macros")
    bad_render(
        {"main": "{% macro f(x) %}{{x}}{% endmacro %}{{f(x=1,x=2)}}"},
        "main",
        "duplicate",
    )
    bad_render(
        {"main": "{% macro f(x) %}{{x}}{% endmacro %}{{f(x=1,2)}}"},
        "main",
        "positional",
    )
    bad_render(
        {"main": "{% from 'lib' import missing %}", "lib": ""},
        "main",
        "does not export",
    )
    bad_render(
        {
            "main": "{% import 'lib' as lib %}{{lib._hidden()}}",
            "lib": "{% macro _hidden() %}X{% endmacro %}",
        },
        "main",
        "only template macros",
    )
    # Error recovery must not retain closures or namespaces in the compiled cache.
    templates.set_source(
        env,
        "main",
        "{% macro f(x) %}{{4/x}}{% endmacro %}{{f(divisor)}}",
    )
    context["divisor"] = JsonValue.Int(0)
    auto caught = False
    try:
        auto output = templates.render_named(env, "main", context)
    except Exception:
        caught = True
    assert caught
    context["divisor"] = JsonValue.Int(2)
    assert templates.render_named(env, "main", context) == "2.0"
    context["divisor"] = JsonValue.Int(4)
    assert templates.render_named(env, "main", context) == "1.0"
    # Filesystem loader caches compiled snapshots until explicit invalidation.
    auto root = fs.mkdtemp()
    fs.write_file(
        os.path_join(root, "base.html"),
        "<b>{% block body %}base{% endblock %}</b>",
    )
    fs.write_file(
        os.path_join(root, "page.html"),
        "{% extends 'base.html' %}{% block body %}{{name}}{% endblock %}",
    )
    auto files = templates.filesystem_environment(root)
    dict[str, JsonValue] person = {"name": JsonValue.Str("<Ada>")}
    assert templates.render_named(files, "page.html", person) == "<b>&lt;Ada&gt;</b>"
    fs.write_file(os.path_join(root, "page.html"), "{{name|upper}}")
    assert templates.render_named(files, "page.html", person) == "<b>&lt;Ada&gt;</b>"
    templates.invalidate(files)
    assert templates.render_named(files, "page.html", person) == "&lt;ADA&gt;"
    templates.set_source(files, "page.html", "override")
    assert templates.render_named(files, "page.html", person) == "override"
    os.remove(os.path_join(root, "base.html"))
    os.remove(os.path_join(root, "page.html"))
    os.rmdir(root)
    print("environments, filesystem, caches, cycles, recovery: PASS")
