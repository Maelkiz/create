from create.render.frame import Frame
from create.render.options import Options


trait Program(Deinitable, Movable):
    """What `run` and `run_headless` drive: `create`, then `update` once per
    frame.

    One per-frame method, not two. A separate `render` would have to be handed
    a frame it may not write to and no input at all, which is what forced a
    program to smuggle a decision from one into the other through a field —
    reading a key in `update` to file a screenshot in `render`, or caching a
    framerate reading to draw it. Deciding and drawing are the same frame's
    work, so they are the same method's.

    There are no event callbacks. Input arrives on the frame, as
    `frame.input`, and nowhere else — so there is one place a frame's
    decisions are made and no ordering question between a callback and the
    frame body.
    """

    @staticmethod
    def create(mut options: Options) raises -> Self:
        """Build the program, before the first frame.

        Where resources the program drives on its own schedule are
        constructed — sprites, fonts, sounds, an `Audio` device — and where
        `options.design_resolution` or `options.autoscale` is set if the
        defaults don't suit.

        No `Frame`: there is no frame yet, and one handed over here could only
        be a frame nothing presents. So the dials are all `create` is given,
        and a draw call it cannot make is a draw call that cannot silently go
        nowhere. Geometry is not readable here either, which is deliberate —
        a window does not report its real size until it has been shown (see
        Gotcha 3), so a layout measured here would be measured against a lie.
        """
        ...

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        """Advance the program by one frame, and draw it.

        Two parameters, two lifetimes. `options` outlives the frame and is
        written for the *next* one — the autoscale mode, the clear, `quit()`.
        `frame` is this frame alone: it is built fresh, drawn on, and dropped
        before presentation, so it must not be stored anywhere. Keyboard and
        mouse are `frame.input`, alongside `frame.time`, so a sketch that
        reads neither names neither.
        """
        ...
