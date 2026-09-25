struct AutoScale(Copyable, Equatable, ImplicitlyCopyable, Movable):
    """How the program's design resolution maps onto the window.

    The design resolution is the coordinate space a program is authored in --
    the size passed to `run`, or pinned by `context.design_resolution`. It is a property of
    the program, not of the display, and a resize or a fullscreen toggle never
    changes it. What changes is how it lands on the window:

    - `FIT` scales uniformly by `min(w, h)`, centres the design, and paints the
      leftover with `context.letterbox` after the frame is rendered -- which also
      clips anything rendered past the design bounds. `canvas.width`/`height` never
      move, so a layout written against them survives any window size.
    - `EXTEND` uses the same scale factor but anchors at the origin and paints
      no bars, so the leftover becomes extra world: `canvas.width`/`height` grow
      with the window. Layout must anchor to the origin or to
      `canvas.left()`/`right()`/`bottom()`/`top()`, since design coordinates no
      longer describe the edges.
    - `OFF` does not scale at all -- `canvas.width`/`height` are window pixels
      and the design resolution goes unused, so layout has to survive any
      window size on its own.

    `run` starts programs in `FIT`, because `OFF` punishes the obvious way to
    write a program: coordinates laid out against the size the author had,
    silently rearranged on any other display. `create` can set `context.autoscale`
    to either other mode.

    `FIT` pins `canvas.width`/`height` to the design size, so a rectangle at a
    fixed x is always inside the world by the same margin. `EXTEND` and `OFF`
    let a resize move `right()`/`left()`/`top()`/`bottom()` themselves, which
    can carry them past an entity between frames — code that reacts to a
    boundary under either mode must set an entity's state (position, sign of
    velocity) from the boundary, not toggle it, or a window shrunk past the
    entity toggles it every frame forever instead of correcting it.
    """

    var value: Int

    comptime OFF = AutoScale(0)
    # the window is the world; a resize moves the extent
    comptime FIT = AutoScale(1)
    # uniform scale to fit, centred, bars on the short axis
    comptime EXTEND = AutoScale(2)
    # same scale as FIT, no bars — leftover becomes extra world

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: AutoScale) -> Bool:
        return self.value == other.value

    def __ne__(self, other: AutoScale) -> Bool:
        return self.value != other.value
