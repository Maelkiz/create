from create.image.animation import Animation


struct Animator(Copyable, Movable, Writable):
    """The playhead over one `Animation`.

    An animation is the artwork and never moves; an animator is the frame a
    particular entity is on right now, so an entity owns one and several can
    share the same animation. Ticked once per frame with the frame delta:

    ```mojo
    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.animator.update(context.time.delta)
    ```

    Constructed stopped on frame 0 -- nothing advances until `play`, `loop`
    or `use`. Two kinds of call drive it:

    - **Commands**, for something that just happened (a key, a hit): `play`
      runs the animation once and holds the last frame, `loop` wraps forever,
      and both always start from frame 0, with or without a new animation, as
      `Tween.play` and `Audio.play` always start. `pause` freezes where it is
      and `resume` continues from there; `stop` rewinds.
    - **`use`**, for what should be showing now, called every frame from the
      branch that decides it. Naming the animation already held changes
      nothing, so it never rewinds a running loop or undoes a `pause`.

    ```mojo
    if context.input.key_pressed(Key.SPACE):
        self.animator.play(self.spin)    # a command: starts every time
    elif not self.spinning:
        self.animator.use(self.run if moving else self.idle)   # a state
    ```
    """

    var _animation: Animation
    var _frame_index: Int
    var _playing: Bool
    var _looping: Bool
    var _finished: Bool
    var _started: Bool
    """Whether `play`, `loop`, `use` or `resume` has set the playhead going
    since construction, the last `stop` or the last switch -- what tells a
    paused or finished animation, which `use` leaves be, from a stopped one,
    which it starts."""
    var _elapsed: Float64

    def __init__(out self, var animation: Animation):
        """Hold `animation`, stopped on frame 0.

        An animator always has an animation, so there is no empty state to
        guard against when rendering.
        """
        self._animation = animation^
        self._frame_index = 0
        self._playing = False
        self._looping = False
        self._finished = False
        self._started = False
        self._elapsed = 0.0

    def animation(self) -> Animation:
        """The animation being played, sharing its frames. Switch with `use`,
        `play` or `loop`."""
        return self._animation

    def frame_index(self) -> Int:
        """The frame showing, counted from 0."""
        return self._frame_index

    def write_to[W: Writer](self, mut writer: W):
        # The animation is a shared asset, not printable, so only the
        # playhead shows.
        writer.write("Animator(frame_index=", self._frame_index, ")")

    def use(mut self, var animation: Animation):
        """Show `animation`, looping: the call to make every frame from the
        branch that decides which animation applies.

        ```mojo
        if self.velocity.x != 0.0:
            self.animator.use(self.run)
        else:
            self.animator.use(self.idle)
        ```

        Naming the animation already held, once it has been started, does
        nothing at all: a loop keeps its place, a `pause` holds and a
        finished `play` stays on its last frame. Otherwise -- another
        animation, or this one stopped -- it starts `animation` looping from
        frame 0. A one-shot is a command, not a state: `play` it when the
        thing that triggers it happens.
        """
        if self._animation._is(animation) and self._started:
            return
        self.loop(animation^)

    def play(mut self):
        """Play once from frame 0, holding the last frame at the end."""
        self._frame_index = 0
        self._elapsed = 0.0
        self._playing = True
        self._looping = False
        self._finished = False
        self._started = True

    def play(mut self, var animation: Animation):
        """Switch to `animation` and play it once from frame 0 -- restarting
        it if it is the one already held."""
        self._animation = animation^
        self.play()

    def loop(mut self):
        """Play from frame 0, wrapping to the start forever."""
        self.play()
        self._looping = True

    def loop(mut self, var animation: Animation):
        """Switch to `animation` and loop it from frame 0 -- restarting it if
        it is the one already held. To keep a running loop's place, `use`
        it."""
        self._animation = animation^
        self.loop()

    def pause(mut self):
        """Freeze on the current frame. `resume` continues from here."""
        self._playing = False

    def resume(mut self):
        """Continue a paused animation without rewinding."""
        if not self._finished:
            self._playing = True
            self._started = True

    def stop(mut self):
        """Halt and rewind to frame 0."""
        self._frame_index = 0
        self._elapsed = 0.0
        self._playing = False
        self._finished = False
        self._started = False

    def update(mut self, dt: Float64):
        """Advance the playhead by `dt` seconds. Call once per frame.

        Frames are advanced in a loop rather than by one step, so a long frame
        skips ahead instead of falling behind the animation's own clock.
        """
        if not self._playing:
            return
        var duration = self._animation.frame_duration()
        self._elapsed += dt
        while self._elapsed >= duration:
            self._elapsed -= duration
            if self._frame_index + 1 < self._animation.frame_count():
                self._frame_index += 1
            elif self._looping:
                self._frame_index = 0
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
