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
    print("package consumer: PASS")
ZAP
(cd "$build" && "$zap" zenv create --no-venv && ZAP_ZENV="$build/zenv" "$zap" run src/main.zap)
