"""Mojo Create — a creative coding library for rapid prototyping and
interactive graphics.

`from create import *` is the import a program needs. It brings in the whole
public surface: the `Program` trait and the run loops, `Options`, `Frame` and the
drawing types, the vector and matrix maths, sprites, audio, and a re-export of
`std.math` so `sin`, `cos` and `pi` are there without a second import.

```mojo
from create import *


@fieldwise_init
struct Sketch(Program):
    var angle: Float64

    @staticmethod
    def create(mut options: Options) raises -> Self:
        return Self(0.0)

    def update(
        mut self, mut options: Options, mut frame: Frame, input: Input
    ) raises:
        self.angle += frame.time.delta
        frame.background(Color.BLACK)
        frame.circle((100 * cos(self.angle), 100 * sin(self.angle)), 20)


def main() raises:
    run[Sketch]("Sketch", width=1280, height=720)
```

The subpackages stay importable on their own — `from create.render import *`
gives the drawing stack with no run loop, which is what `run_headless` is built
on — so this module is a convenience, not a layer.

**What this module re-exports is the union of the subpackages.** Each of them
exports the names it owns and nothing from a layer below — `create.core` names
`Frame` and `Rectangle` in its signatures but exports neither — so a single
subpackage star is never a preamble; this module is. It re-exports everything
public by star-importing all five, so a name added to `math/__init__.mojo`
appears here with no second edit and the two cannot drift apart.

Code that wants less than the whole surface imports by name from the package
that defines it (`from create.math import overlaps`), rather than starring one
subpackage.

The stars widen nothing on their own. A star import skips `_`-prefixed
declarations and reaches only what a package's `__init__.mojo` lists, so
`_raster`'s `blend`, `_bytes`'s `le_uint` and `font.mojo`'s `_GlyphInfo` stay
internal here exactly as they are one level down.
"""

from create.core import *
from create.math import *
from create.render import *
from create.sprite import *
from create.audio import *
