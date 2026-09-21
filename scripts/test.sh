#!/bin/sh
# Runs every tests/**/test_*.mojo file, several at a time.
#
# Each file is its own program, so the only shared state between them is the
# filesystem — and every scratch path is already namespaced per file, so the
# files are independent and the order they run in does not matter.
#
# Output is buffered per file and only printed in full when that file fails:
# interleaved PASS lines from a dozen concurrent runs are unreadable, and a
# failure is the only time the detail is wanted.
set -u

jobs=${1:-}
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

files=$(find tests -name 'test_*.mojo' | sort)
[ -z "$files" ] && { echo "No test files found."; exit 1; }

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
