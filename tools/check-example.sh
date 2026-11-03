#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
zap=${ZAP:-zap}
case "$zap" in
    /*) ;;
    */*) zap=$(cd "$(dirname "$zap")" && pwd)/$(basename "$zap") ;;
esac
build=$(mktemp -d "${TMPDIR:-/tmp}/templates-example.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
cp -R "$root/examples/html_app/src" "$root/examples/html_app/pages" "$build/"
cat > "$build/zap.toml" <<MANIFEST
[package]
name = "template_html_app"
version = "0.1.0"
[dependencies]
templates = { path = "$root" }
MANIFEST
(cd "$build" && "$zap" zenv create --no-venv)
if [ "${1:-}" = --check ]; then
    (cd "$build" && ZAP_ZENV="$build/zenv" "$zap" ir src/main.zap > /dev/null)
else
    (cd "$build" && ZAP_ZENV="$build/zenv" "$zap" run src/main.zap)
fi
