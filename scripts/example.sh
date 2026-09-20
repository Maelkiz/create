#!/usr/bin/env bash
# Resolve an example name to a path and run it.
#
#   pixi run example sketch          -> examples/sketch.mojo
#   pixi run example sidescroller    -> examples/sidescroller/src/main.mojo
#   pixi run example gl_bench cpu    -> extra arguments are passed through
#
# A path that exists as given is run as-is, so the long form still works.
set -e

name="$1"
if [ -z "$name" ]; then
    echo "usage: pixi run example <name> [args...]" >&2
    echo >&2
    ls examples/*.mojo | sed 's|examples/||; s|\.mojo$||' >&2
    ls -d examples/*/ | sed 's|examples/||; s|/$||' >&2
    exit 1
fi
shift

if [ -f "examples/$name.mojo" ]; then
    file="examples/$name.mojo"
elif [ -f "examples/$name/src/main.mojo" ]; then
    file="examples/$name/src/main.mojo"
elif [ -f "$name" ]; then
    file="$name"
else
    echo "no such example: $name" >&2
    exit 1
fi

exec mojo run -I src "$file" "$@"
