from std.math import clamp

from .easing import Easing, ease
from .util import lerp, fmod


struct Tween(Copyable, ImplicitlyCopyable, Movable):
    """A value moving from one number to another over a fixed duration.

    A tween is a playhead, in the same sense as `SpriteAnimator`: the program
    owns one per thing being animated and ticks it once per frame with the
    frame delta.

    ```mojo
    def create(out self):
        self.fade = Tween(0.0, 1.0, 0.4, Easing.OUT_CUBIC)

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.fade.update(frame.time.delta)
        if input.key_pressed(Key.SPACE):
            self.fade.play()
        frame.fill(Color(255, 255, 255, Int(255 * self.fade.value)))
    ```

    Unlike an animation, a tween carries no shared artwork -- its whole
    definition is four numbers -- so there is no asset to hold by `ArcPointer`
    and every entity simply owns its own.

    **Tweening something that is not a number.** `Tween(duration)` runs 0 to 1,
    which is exactly what `Vector2D.lerp` and `Color.lerp` take, so one scalar
    tween drives a position or a colour without a second type:

    ```mojo
    self.slide = Tween(0.3, Easing.OUT_CUBIC)      # in create
    ...
    self.pos = self.from_pos.lerp(self.to_pos, self.slide.value)
    ```

    Constructed stopped at `start` -- nothing moves until `play`, `loop` or
    `ping_pong`. The verbs mean what they mean on `SpriteAnimator`: `play`
    always restarts from the beginning, `pause` freezes where it is and
    `resume` continues from there.
    """

    var value: Float64
    """The eased value, between `start` and `end`. Read this after `update`.

    A field rather than a method so `render`, which takes an immutable `self`,
    can read it without the tween being mutable there.
    """

    var progress: Float64
    """How far through the duration, 0 to 1, *before* easing.

    The raw time fraction, so it is what a progress bar wants to render -- and
    what `value` is derived from. While ping-ponging it runs back down to 0.
    """

    var start: Float64
    """The value at `progress` 0."""

    var end: Float64
    """The value at `progress` 1."""

    var duration: Float64
    """Seconds for a full run, start to end."""

    var curve: Easing
    """The easing curve applied to `progress` to get `value`."""

    var _playing: Bool
    var _finished: Bool
    var _looping: Bool
    var _ping_pong: Bool
    var _reversed: Bool

    def __init__(
        out self,
        start: Float64,
        end: Float64,
        duration: Float64,
        curve: Easing = Easing.LINEAR,
    ):
        """A tween from `start` to `end` over `duration` seconds."""
        debug_assert(
            duration > 0.0, "Tween: duration must be greater than zero"
        )
        self.value = start
        self.progress = 0.0
        self.start = start
        self.end = end
        self.duration = duration
        self.curve = curve
        self._playing = False
        self._finished = False
        self._looping = False
        self._ping_pong = False
        self._reversed = False

    def __init__(out self, duration: Float64, curve: Easing = Easing.LINEAR):
        """A tween from 0 to 1 -- the fraction `Vector2D.lerp` and `Color.lerp`
        take, and the form to reach for when animating anything that is not a
        plain number."""
        self = Self(0.0, 1.0, duration, curve)

    def play(mut self):
        """Run once from the start, holding `end` at the finish."""
        self.progress = 0.0
        self._playing = True
        self._finished = False
        self._looping = False
        self._ping_pong = False
        self._reversed = False
        self._apply()

    def loop(mut self):
        """Run from the start, snapping back and repeating forever.

        The snap is visible whenever `start` and `end` differ, which is what
        `ping_pong` exists to avoid -- reach for this only when the value wraps
        naturally, like a rotation through a full turn.
        """
        self.play()
        self._looping = True

    def ping_pong(mut self):
        """Run to `end`, back to `start`, forever -- the usual way to loop a
        tween, since it never snaps.

        `progress` runs back down on the return leg, so the easing curve is
        travelled backwards too and a `Easing.OUT_CUBIC` pulse decelerates into
        both ends rather than into one.
        """
        self.play()
        self._looping = True
        self._ping_pong = True

    def pause(mut self):
        """Freeze at the current value. `resume` continues from here."""
        self._playing = False

    def resume(mut self):
        """Continue a paused tween without rewinding."""
        if not self._finished:
            self._playing = True

    def stop(mut self):
        """Halt and rewind, putting `value` back to `start`."""
        self.progress = 0.0
        self._playing = False
        self._finished = False
        self._reversed = False
        self._apply()

    def update(mut self, dt: Float64):
        """Advance the playhead by `dt` seconds. Call once per frame.

        Nothing else moves a tween, so a tween never ticked is a tween stuck at
        `start` -- the same failure mode as a `SpriteAnimator` that is never
        updated.
        """
        if not self._playing:
            return

        var step = dt / self.duration
        self.progress += -step if self._reversed else step

        if self.progress > 1.0:
            if self._ping_pong:
                # Reflect the overshoot back down so a long frame loses no
                # time. Clamped because a frame longer than the whole duration
                # would reflect past the far end.
                self.progress = clamp(2.0 - self.progress, 0.0, 1.0)
                self._reversed = True
            elif self._looping:
                self.progress = fmod(self.progress, 1.0)
            else:
                self.progress = 1.0
                self._playing = False
                self._finished = True
        elif self.progress < 0.0:
            # Only reachable on a ping-pong return leg, which always loops.
            self.progress = clamp(-self.progress, 0.0, 1.0)
            self._reversed = False

        self._apply()

    def is_playing(self) -> Bool:
        """True while the playhead is advancing -- false when stopped, paused
        or finished."""
        return self._playing

    def is_finished(self) -> Bool:
        """True once a `play` reached `end`. Never true for `loop` or
        `ping_pong`, which have no end to reach."""
        return self._finished

    def _apply(mut self):
        self.value = lerp(self.start, self.end, ease(self.curve, self.progress))
