from create.render.canvas import Canvas
from .context import Context
from .input import Input


trait Program(Deinitable, Movable):
    """What `run` and `run_headless` drive: `create`, then `update` and
    `render` once per frame.

    Only `create` and `render` have to be written — `update` defaults to doing
    nothing, which is enough for a program that only draws.

    There are no event callbacks. Input arrives as `update`'s parameter and
    nothing else, so there is one place a frame's decisions are made and no
    ordering question between a callback and the frame body.
    """

    @staticmethod
    def create(mut ctx: Context) raises -> Self:
        """Build the program, before the first frame.

        Where resources the program drives on its own schedule are
        constructed — sprites, fonts, sounds, an `Audio` device — and where
        `ctx.design` or `ctx.autoscale` is set if the defaults don't suit.
        """
        ...

    def update(mut self, mut ctx: Context, input: Input) raises:
        """Advance the program by one frame.

        `ctx` is mutable because the program writes back to it — `quit()`,
        `autoscale`, `quit_on_escape`. `input` is not: the run loop is its only
        writer, so borrowing it read-only makes that one-way flow a compile
        error to violate rather than a convention to remember.
        """
        pass

    def render(self, mut canvas: Canvas) raises:
        """Draw one frame.

        `self` is immutable: rendering reads the state `update` produced. The
        `canvas` is built fresh for this frame and dropped after, so it must
        not be stored anywhere.
        """
        pass
