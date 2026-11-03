#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/templates-tests.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
cp "$root/src/templates.zap" "$build/templates.zap"
mkdir -p "$build/templates"
for module in expression values filters; do
    cp "$root/src/$module.zap" "$build/templates/$module.zap"
done
for source in "$root"/tests/*_test.zap; do
    echo "Running $(basename "$source")"
    cp "$source" "$build/main.zap"
    if [ "${1:-}" = --check ]; then
        "${ZAP:-zap}" ir "$build/main.zap" > /dev/null
    else
        "${ZAP:-zap}" run "$build/main.zap"
    fi
done
