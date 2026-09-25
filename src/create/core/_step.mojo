from create.render.canvas import Canvas, PersistentCanvasState
from create.render.context import Context
from .program import Program


def step[
    P: Program
](
    mut program: P,
    mut context: Context,
    var state: PersistentCanvasState,
) raises -> PersistentCanvasState:
    """Advance `program` by one frame and hand its recorded state back.

    The windowed and headless loops differ in how they get a frame started —
    one pumps SDL events and reads a clock, the other counts — but from here
    on they must not differ at all, so this is the one copy of what a frame
    *is*. It lives in its own module rather than in `run.mojo` because the
    headless path must not pull in the window.

    `state` travels in and out because a `Canvas` is a per-frame view: it is
    built for this frame and dropped before the frame is presented. `context`
    is borrowed rather than moved for the opposite reason — it is never a
    `Canvas`'s to own, which is what lets `update` be handed both at once.

    **The caller presents.** A frame ends with the recording complete and the
    state handed back; `state.backend.present(surface, scale)` is the caller's
    call, not this one's. That keeps the frame body target-agnostic — a GPU
    backend has no `Surface` to name — and it is why `step` grows no second
    target parameter, which is the failure mode Gotcha 4 describes. The
    windowed and headless loops both present through a `Surface` they alone
    know how to build; in the windowed case that is only valid after events
    have been pumped.
    """
    var canvas = Canvas(state^, context)
    program.update(context, canvas)
    # Recorded last, so it doubles as the clip for anything rendered out of
    # bounds — the replay honours the buffer's order.
    canvas._render_letterbox()
    return canvas^._release()
