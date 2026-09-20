from create.render.frame import Frame, PersistentFrameState
from create.render.options import Options
from create.render.input import Input
from .program import Program


def step[
    P: Program
](
    mut program: P,
    mut options: Options,
    input: Input,
    var state: PersistentFrameState,
) raises -> PersistentFrameState:
    """Advance `program` by one frame and hand its recorded state back.

    The windowed and headless loops differ in how they get a frame started —
    one pumps SDL events and reads a clock, the other counts — but from here
    on they must not differ at all, so this is the one copy of what a frame
    *is*. It lives in its own module rather than in `run.mojo` because the
    headless path must not pull in the window.

    `state` travels in and out because a `Frame` is a per-frame view: it is
    built for this frame and dropped before the frame is presented. `options`
    is borrowed rather than moved for the opposite reason — it is never a
    `Frame`'s to own, which is what lets `update` be handed both at once.
    `input` is borrowed and copied onto the frame: the loop owns the one that
    persists across frames, and the program reads this frame's snapshot as
    `frame.input`.

    **The caller presents.** A frame ends with the recording complete and the
    state handed back; `state.backend.present(surface, scale)` is the caller's
    call, not this one's. That keeps the frame body target-agnostic — a GPU
    backend has no `Surface` to name — and it is why `step` grows no second
    target parameter, which is the failure mode Gotcha 4 describes. The
    windowed and headless loops both present through a `Surface` they alone
    know how to build; in the windowed case that is only valid after events
    have been pumped.
    """
    var frame = Frame(state^, options, input)
    program.update(options, frame)
    # Recorded last, so it doubles as the clip for anything drawn out of
    # bounds — the replay honours the buffer's order.
    frame._draw_letterbox()
    return frame^._release()
