#!/bin/sh
# Runs tests/**/test_*.mojo files, several at a time.
#
#   pixi run test                  -> every test file
#   pixi run test render           -> tests/render/
#   pixi run test render audio     -> both
#   pixi run test canvas           -> tests/**/test_canvas.mojo
#   pixi run test tests/math/test_tween.mojo
#   pixi run test --jobs 4 render  -> pin the worker count (default nproc, max 8)
#   pixi run test -j 4 render      -> the same
#
# A target is resolved as a path that exists as given, then as a subpackage
# directory under tests/, then as a test file name without its test_ prefix.
#
# Each file is its own program, so the only shared state between them is the
# filesystem — and every scratch path is already namespaced per file, so the
# files are independent and the order they run in does not matter.
#
# Output is buffered per file and only printed in full when that file fails:
# interleaved PASS lines from a dozen concurrent runs are unreadable, and a
# failure is the only time the detail is wanted. The exception is a SKIP line
# from a passing file (a GL test with no context): it is printed under the
# PASS, since a skipped test passing silently looks like a tested one.
set -u

jobs=
case "${1:-}" in
    -j|--jobs)
        [ -n "${2:-}" ] || { echo "$1 needs a worker count" >&2; exit 1; }
        jobs=$2
        shift 2
        ;;
esac
if [ -z "$jobs" ]; then
    jobs=$(nproc 2>/dev/null || echo 4)
    [ "$jobs" -gt 8 ] && jobs=8
fi

export SDL_AUDIO_DRIVER=dummy

logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
export LOGS="$logs"

[ $# -eq 0 ] && set -- tests
files=
for target in "$@"; do
    if [ -e "$target" ]; then
        found=$(find "$target" -name 'test_*.mojo')
    elif [ -d "tests/$target" ]; then
        found=$(find "tests/$target" -name 'test_*.mojo')
    else
        found=$(find tests -name "test_$target.mojo")
    fi
    if [ -z "$found" ]; then
        echo "no tests for: $target" >&2
        echo "subpackages: $(ls -d tests/*/ | sed 's|tests/||; s|/$||' \
            | grep -vx 'fixtures\|assets' | tr '\n' ' ')" >&2
        exit 1
    fi
    files="$files
$found"
done
files=$(echo "$files" | sed '/^$/d' | sort -u)

# The library is compiled once, here, and every test file imports the
# result. Against src each file would parse and elaborate the whole package
# again — most of a render test's build time. Built fresh on every run, so it
# is never stale.
if ! mojo precompile src/create -o "$logs/create.mojoc" > "$logs/precompile" 2>&1
then
    cat "$logs/precompile"
    echo "The library does not compile; no tests were run."
    exit 1
fi

# Each path reaches the worker as $1 rather than through -I: BSD xargs (macOS)
# caps a command assembled by -I at 255 bytes, and this one is longer.
if ! echo "$files" | xargs -n 1 -P "$jobs" sh -c '
    log="$LOGS/$(echo "$1" | tr / _).log"
    if mojo run -I "$LOGS" "$1" > "$log" 2>&1; then
        skips=$(grep "SKIP" "$log" | sed "s/^/    /")
        # One write, so a concurrent worker cannot land between the lines.
        printf "PASS %s%s\n" "$1" "${skips:+
$skips}"
    else
        echo "FAIL $1"
        touch "$log.failed"
    fi' sh
then
    # A worker never fails (a failing test is a .failed file), so this is
    # xargs itself: nothing reliable ran.
    echo "The test runner failed; the results above are incomplete."
    exit 1
fi

failed=$(ls "$logs" | grep '\.failed$' || true)
[ -z "$failed" ] && { echo "All test files passed."; exit 0; }

for f in $failed; do
    echo
    echo "=== ${f%.log.failed} ==="
    cat "$logs/${f%.failed}"
done
exit 1
