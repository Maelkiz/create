from create.render.frame import Frame
from .input import Input


trait Program(Deinitable, Movable):
    """What `run` and `run_headless` drive: `create`, then `update` once per
    frame.

    One per-frame method, not two. A separate `render` would have to be handed
    a frame it may not write to and no `Input` at all, which is what forced a
    program to smuggle a decision from one into the other through a field —
    reading a key in `update` to file a screenshot in `render`, or caching a
    framerate reading to draw it. Deciding and drawing are the same frame's
    work, so they are the same method's.

    There are no event callbacks. Input arrives as `update`'s parameter and
    nothing else, so there is one place a frame's decisions are made and no
    ordering question between a callback and the frame body.
    """

    @staticmethod
    def create(mut frame: Frame) raises -> Self:
        """Build the program, before the first frame.

        Where resources the program drives on its own schedule are
        constructed — sprites, fonts, sounds, an `Audio` device — and where
        `frame.design` or `frame.autoscale` is set if the defaults don't suit.

        This frame is **never presented**: it exists so `create` can read the
        geometry and turn the dials, and whatever it draws is discarded.
        """
        ...

    def update(mut self, mut frame: Frame, input: Input) raises:
        """Advance the program by one frame, and draw it.

        `frame` is mutable because the program both draws on it and writes
        back to it — `quit()`, `autoscale`, `quit_on_escape`. `input` is not:
        the run loop is its only writer, so borrowing it read-only makes that
        one-way flow a compile error to violate rather than a convention to
        remember.

        The `frame` is built fresh for this frame and dropped after, so it
        must not be stored anywhere.
        """
        ...
