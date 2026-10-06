from create.render.canvas import Canvas
from create.core.context import Context


trait Program(Deinitable, Movable):
    """What `run` and `run_headless` drive: `create`, which draws the first
    frame, then `update` once per frame after it.

    One per-frame method, not two. A separate `render` would have to be handed
    a canvas it may not write to and no input at all, which is what forced a
    program to smuggle a decision from one into the other through a field —
    reading a key in `update` to file a screenshot in `render`, or caching a
    frame rate reading to render it. Deciding and rendering are the same frame's
    work, so they are the same method's.

    There are no event callbacks. Input arrives on the context, as
    `context.input`, and nowhere else — so there is one place a frame's
    decisions are made and no ordering question between a callback and the
    frame body.
    """

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Self:
        """Build the program and draw frame 1, as Processing's `setup` does.

        Where resources the program drives on its own schedule are
        constructed — images, fonts, sounds, an `Audio` device — and where
        canvas settings that outlive the frame, such as `canvas.autoclear`,
        are set once.

        `canvas` is a real frame, presented like every later one: what is
        drawn here shows, and geometry is as valid as on any first frame (see
        Gotcha 3). The design size and autoscale mode are `run`'s arguments,
        already in place; `context.design_size` or `context.autoscale`
        called here applies from the next frame, like any dial. `context.time`
        is zero and `context.input` is empty; `context.frame_count()` is 1.

        Drawing that needs the program's own fields builds `Self` into a
        local first, draws, then returns it.
        """
        ...

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        """Advance the program by one frame, and render it.

        Two parameters, two lifetimes. `context` is the run's state: it
        outlives the frame, carries what the loop measured for this one —
        `context.time`, `context.input` — and takes the dials for the *next*
        one — the autoscale mode, the clear, `quit()`. `canvas` is where this
        frame is drawn: it is built fresh, rendered on, and dropped before
        presentation, so it must not be stored anywhere. The first `update`
        draws frame 2; `create` drew frame 1.
        """
        ...
