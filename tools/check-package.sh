#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
zap=${ZAP:-zap}
case "$zap" in
    /*) ;;
    */*) zap=$(cd "$(dirname "$zap")" && pwd)/$(basename "$zap") ;;
esac
build=$(mktemp -d "${TMPDIR:-/tmp}/templates-package.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
(cd "$root" && "$zap" publish --dry-run)
mkdir -p "$build/src"
cat > "$build/zap.toml" <<MANIFEST
[package]
name = "template_consumer"
version = "0.1.0"
[dependencies]
templates = { path = "$root" }
MANIFEST
cat > "$build/src/main.zap" <<'ZAP'
import templates

def main():
    dict[str, JsonValue] context = {"name": JsonValue.Str("<Ada>")}
    auto page = templates.compile("Hello {{name}}")
    assert templates.render_compiled(page, context) == "Hello &lt;Ada&gt;"
    assert templates.render("{{2 + 3}}", context) == "5"
    assert templates.render("{{name|safe}}", context) == "<Ada>"
    assert templates.render("{{name|safe|escape}}", context) == "<Ada>"
    assert templates.render("{{missing|default('ok')}}", context, True, True) == "ok"
    assert templates.render("{{name|length}}", context) == "5"
    dict[str, str] pages = {"base": "<{% block x %}base{% endblock %}>", "page": "{% extends 'base' %}{% block x %}{{name}}{% endblock %}"}
    auto env = templates.environment(pages)
    assert templates.render_named(env, "page", context) == "<&lt;Ada&gt;>"
    templates.set_source(env, "page", "{% macro f(x='ok') %}[{{x}}]{% endmacro %}{{f()}}")
    assert templates.render_named(env, "page", context) == "[ok]"
    print("package consumer: PASS")
ZAP
(cd "$build" && "$zap" zenv create --no-venv && ZAP_ZENV="$build/zenv" "$zap" run src/main.zap)
