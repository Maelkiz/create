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
# failure is the only time the detail is wanted.
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
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] \
    && [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export SDL_VIDEODRIVER=offscreen
fi

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

echo "$files" | xargs -P "$jobs" -I{} sh -c '
    log="$LOGS/$(echo "{}" | tr / _).log"
    if mojo run -I src "{}" > "$log" 2>&1; then
        echo "PASS {}"
    else
        echo "FAIL {}"
        touch "$log.failed"
    fi'

failed=$(ls "$logs" | grep '\.failed$' || true)
[ -z "$failed" ] && { echo "All test files passed."; exit 0; }

for f in $failed; do
    echo
    echo "=== ${f%.log.failed} ==="
    cat "$logs/${f%.failed}"
done
exit 1
