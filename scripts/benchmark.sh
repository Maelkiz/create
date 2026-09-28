#!/usr/bin/env bash
# Resolve a benchmark name to a path and run it.
#
#   pixi run benchmark raster        -> benchmarks/raster.mojo
#   pixi run benchmark frame cpu     -> extra arguments are passed through
set -e

name="$1"
if [ -z "$name" ]; then
    echo "usage: pixi run benchmark <name> [args...]" >&2
    echo >&2
    ls benchmarks/*.mojo | sed 's|benchmarks/||; s|\.mojo$||' >&2
    exit 1
fi
shift

if [ ! -f "benchmarks/$name.mojo" ]; then
    echo "no such benchmark: $name" >&2
    exit 1
fi

exec mojo run -I src "benchmarks/$name.mojo" "$@"
