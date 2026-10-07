#!/bin/sh
# Builds the smoke test into a binary and runs it outside the pixi
# environment, as a `mojo build` program is run: no CONDA_PREFIX, no pixi
# PATH. It draws text, so it has to find FreeType through `load_library`'s
# fallbacks rather than the environment variable pixi sets.
#
#   pixi run check-standalone
set -eu

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

mojo build -I src tests/core/test_smoke.mojo -o "$out/smoke"
env -i HOME="$HOME" PATH=/usr/bin:/bin SDL_VIDEODRIVER=dummy "$out/smoke"
