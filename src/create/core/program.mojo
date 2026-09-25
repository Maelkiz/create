from create.render.canvas import Canvas
from create.render.context import Context


trait Program(Deinitable, Movable):
    """What `run` and `run_headless` drive: `create`, then `update` once per
    frame.

    One per-frame method, not two. A separate `render` would have to be handed
    a canvas it may not write to and no input at all, which is what forced a
    program to smuggle a decision from one into the other through a field —
    reading a key in `update` to file a screenshot in `render`, or caching a
    framerate reading to render it. Deciding and rendering are the same frame's
    work, so they are the same method's.

    There are no event callbacks. Input arrives on the context, as
    `context.input`, and nowhere else — so there is one place a frame's
    decisions are made and no ordering question between a callback and the
    frame body.
    """

    @staticmethod
    def create(mut context: Context) raises -> Self:
        """Build the program, before the first frame.

        Where resources the program drives on its own schedule are
        constructed — sprites, fonts, sounds, an `Audio` device — and where
        `context.design_resolution` or `context.autoscale` is set if the
        defaults don't suit.

        No `Canvas`: there is no frame yet, and one handed over here could only
        be a frame nothing presents. So the dials are all `create` is given,
        and a render call it cannot make is a render call that cannot silently go
        nowhere. Geometry is not readable here either, which is deliberate —
        a window does not report its real size until it has been shown (see
        Gotcha 3), so a layout measured here would be measured against a lie.
        """
        ...

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        """Advance the program by one frame, and render it.

        Two parameters, two lifetimes. `context` is the run's state: it
        outlives the frame, carries what the loop measured for this one —
        `context.time`, `context.input` — and takes the dials for the *next*
        one — the autoscale mode, the clear, `quit()`. `canvas` is where this
        frame is drawn: it is built fresh, rendered on, and dropped before
        presentation, so it must not be stored anywhere.
        """
        ...
