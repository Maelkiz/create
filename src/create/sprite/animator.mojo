from std.memory import ArcPointer

from create.sprite.animation import SpriteAnimation


struct SpriteAnimator(Movable):
    """The playhead over one `SpriteAnimation`.

    An animation is the artwork and never moves; an animator is the frame a
    particular entity is on right now, so an entity owns one and several can
    share the same animation. Ticked once per frame with the frame delta:

    ```mojo
    def update(mut self, mut canvas: Canvas, input: Input) raises:
        self.animator.update(canvas.time.delta)
    ```

    Constructed stopped on frame 0 -- nothing advances until `play` or `loop`.
    `play` runs the animation once and holds the last frame; `loop` wraps
    forever. `pause` freezes where it is and `resume` continues from there,
    while `play` always restarts from the beginning, so the two are never
    confused with one another.
    """

    var animation: ArcPointer[SpriteAnimation]
    var frame_index: Int
    var _playing: Bool
    var _looping: Bool
    var _finished: Bool
    var _elapsed: Float64

    def __init__(out self, var animation: ArcPointer[SpriteAnimation]):
        """Hold `animation`, stopped on frame 0.

        An animator always has an animation, so there is no empty state to
        guard against when rendering.
        """
        self.animation = animation^
        self.frame_index = 0
        self._playing = False
        self._looping = False
        self._finished = False
        self._elapsed = 0.0

    def use(mut self, var animation: ArcPointer[SpriteAnimation]):
        """Switch to `animation`, rewound to frame 0 and stopped.

        Switching to the animation already held does nothing at all. That
        matters: the natural way to drive an animator is to call `use` every
        frame from the branch that decided which animation applies --

        ```mojo
        if self.velocity.x != 0.0:
            self.animator.loop(self.run.copy())
        else:
            self.animator.loop(self.idle.copy())
        ```

        -- and without this guard every frame would rewind to frame 0 and the
        animation would never visibly move.
        """
        if Pointer(to=self.animation[]) == Pointer(to=animation[]):
            return
        self.animation = animation^
        self.frame_index = 0
        self._playing = False
        self._looping = False
        self._finished = False
        self._elapsed = 0.0

    def play(mut self):
        """Play once from frame 0, holding the last frame at the end."""
        self.frame_index = 0
        self._elapsed = 0.0
        self._playing = True
        self._looping = False
        self._finished = False

    def play(mut self, var animation: ArcPointer[SpriteAnimation]):
        """`use` then `play` -- restarts even if the animation is unchanged."""
        self.use(animation^)
        self.play()

    def loop(mut self):
        """Play from frame 0, wrapping to the start forever."""
        self.play()
        self._looping = True

    def loop(mut self, var animation: ArcPointer[SpriteAnimation]):
        """`use` then `loop`, and a no-op restart-wise if already looping it."""
        if (
            Pointer(to=self.animation[]) == Pointer(to=animation[])
            and self._playing
            and self._looping
        ):
            return
        self.use(animation^)
        self.loop()

    def pause(mut self):
        """Freeze on the current frame. `resume` continues from here."""
        self._playing = False

    def resume(mut self):
        """Continue a paused animation without rewinding."""
        if not self._finished:
            self._playing = True

    def stop(mut self):
        """Halt and rewind to frame 0."""
        self.frame_index = 0
        self._elapsed = 0.0
        self._playing = False
        self._finished = False

    def update(mut self, dt: Float64):
        """Advance the playhead by `dt` seconds. Call once per frame.

        Frames are advanced in a loop rather than by one step, so a long frame
        skips ahead instead of falling behind the animation's own clock.
        """
        if not self._playing:
            return
        var duration = self.animation[].frame_duration()
        self._elapsed += dt
        while self._elapsed >= duration:
            self._elapsed -= duration
            if self.frame_index + 1 < self.animation[].count():
                self.frame_index += 1
            elif self._looping:
                self.frame_index = 0
            else:
                self._playing = False
                self._finished = True
                self._elapsed = 0.0
                return

    def is_playing(self) -> Bool:
        """True while the playhead is advancing -- false when stopped, paused
        or finished."""
        return self._playing

    def is_finished(self) -> Bool:
        """True once a `play` reached its last frame. Never true for `loop`."""
        return self._finished
