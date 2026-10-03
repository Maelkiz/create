"""What both windowed loops do once a frame is presented, whatever window
they present through. Separate from `_step.mojo`, which the headless loops
import and which must not pull in a window."""

from std.time import sleep

from create._window import NativeWindow
from create.core.context import Context


def _finish_frame[
    W: NativeWindow
](mut win: W, context: Context, frame_start: Int) raises:
    """Hand this frame's `context.rumble` calls to the pads, then sleep off
    whatever is left of the target frame duration, if any."""
    for rumble in context._rumbles:
        win.rumble_gamepad(
            rumble.id,
            rumble.low_frequency,
            rumble.high_frequency,
            rumble.seconds,
        )
    if context._max_frame_rate <= 0:
        return
    var worked_ms = win.ticks() - frame_start
    var target_ms = 1000.0 / Float64(context._max_frame_rate)
    var remaining_ms = target_ms - Float64(worked_ms)
    if remaining_ms > 0.0:
        sleep(remaining_ms / 1000.0)
