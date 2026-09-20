from std.collections import Optional

from create.render.frame import Frame, PersistentFrameState
from .input import Input
from .program import Program


def step[
    P: Program
](
    mut program: P,
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
    built for this frame and dropped before the frame is presented, so anything
    longer-lived than a frame rides in `PersistentFrameState`.

    **The caller presents.** A frame ends with the recording complete and the
    state handed back; `state.backend.present(surface, scale)` is the caller's
    call, not this one's. That keeps the frame body target-agnostic — a GPU
    backend has no `Surface` to name — and it is why `step` grows no second
    target parameter, which is the failure mode Gotcha 4 describes. The
    windowed and headless loops both present through a `Surface` they alone
    know how to build; in the windowed case that is only valid after events
    have been pumped.
    """
    var frame = Frame(state^)
    program.update(frame, input)
    # Recorded last, so it doubles as the clip for anything drawn out of
    # bounds — the replay honours the buffer's order.
    frame._draw_letterbox()
    return frame^._release()


def create_program[
    P: Program
](
    var state: PersistentFrameState,
    mut program: Optional[P],
) raises -> PersistentFrameState:
    """Build the program over a frame that is never presented.

    Here beside `step`, and for the same reason: `create` is a frame body the
    four loops must not each reimplement. Its one non-obvious step is the
    discard — the frame handed to `create` is the only one the loop never
    presents, so a draw call or a filed capture would otherwise leak into
    frame one. See `Backend._discard_recording`.

    The program leaves through `program` rather than a second return value
    because a `Tuple` of move-only values cannot be unpacked in this Mojo
    version; the state flows in and out exactly as it does through `step`.
    """
    var frame = Frame(state^)
    program = Optional(P.create(frame))
    var out_state = frame^._release()
    out_state.backend._discard_recording()
    return out_state^
