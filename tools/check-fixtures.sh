#!/bin/sh
# Generation-only check; not required for native tests or package consumers.
set -eu
case "${1:---check}" in
    --check|--write) ;;
    *) echo 'usage: check-fixtures.sh [--check|--write]' >&2; exit 2 ;;
esac
root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/templates-fixtures.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
mkdir -p "$build/tools" "$build/tests/fixtures"
for kind in core filter composition; do
    cp "$root/tools/generate-$kind-fixtures.py" "$build/tools/"
    "${FIXTURE_PYTHON:-python3}" "$build/tools/generate-$kind-fixtures.py"
done
"${ZAP:-zap}" fmt "$build/tests"
for kind in core filters composition; do
    for path in "tests/fixtures/$kind.json" "tests/${kind}_fixtures_test.zap"; do
        if [ "${1:---check}" = --write ]; then
            cp "$build/$path" "$root/$path"
        else
            diff -u "$root/$path" "$build/$path"
        fi
    done
done
echo 'fixture regeneration: PASS'
