#!/bin/sh
# Builds every example and benchmark entrypoint, several at a time.
#
#   pixi run build-examples
#
# A consumer build type-checks only the `def` bodies it reaches, so this
# catches API drift in examples and benchmarks that neither precompile nor
# the tests see. --emit llvm stops after type-checking and IR generation:
# the binaries were never used, and skipping optimisation and linking saves
# about a third.
set -u

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

entrypoints=$(grep -rlE '^def main' examples benchmarks --include='*.mojo' \
    | sort)
if [ -z "$entrypoints" ]; then
    echo "No example or benchmark entrypoints found." >&2
    exit 1
fi
jobs=$(nproc 2>/dev/null || echo 4)
[ "$jobs" -gt 8 ] && jobs=8
export OUT="$out"
# Each path reaches the worker as $1 rather than through -I: BSD xargs (macOS)
# caps a command assembled by -I at 255 bytes, and this one is longer.
echo "$entrypoints" | xargs -n 1 -P "$jobs" sh -c '
    name=$(echo "$1" | tr / _)
    if mojo build -I src --emit llvm "$1" -o "$OUT/$name.ll" \
        > "$OUT/$name.log" 2>&1; then
        echo "PASS $1"
    else
        echo "FAIL $1"
        cat "$OUT/$name.log"
        exit 1
    fi' sh
