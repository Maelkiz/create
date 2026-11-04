#!/usr/bin/env bash
# Resolve an example name to a path and run it.
#
#   pixi run example sketch          -> examples/sketch/main.mojo
#   pixi run example shadows gpu     -> extra arguments are passed through
#
# Every example is a folder of that name, run from its main.mojo, beside any
# modules and assets of its own.
#
# A path that exists as given is run as-is, so the long form still works.
#
# It runs against build/create.mojoc, which the pixi task rebuilds first only
# when the library changed, so the library is not recompiled on every run.
set -e

name="$1"
if [ -z "$name" ]; then
    echo "usage: pixi run example <name> [args...]" >&2
    echo >&2
    ls -d examples/*/ | sed 's|examples/||; s|/$||' >&2
    exit 1
fi
shift

if [ -f "examples/$name/main.mojo" ]; then
    file="examples/$name/main.mojo"
elif [ -f "$name" ]; then
    file="$name"
else
    echo "no such example: $name" >&2
    exit 1
fi

exec mojo run -I build "$file" "$@"
