struct Time(Copyable, Movable, Writable):
    """Per-frame timing, ticked once per frame by the run loop.

    Owns the previous tick stamp so the frame delta is derived in one place.
    `_start` must seed that stamp before the first `_tick`: the window clock
    counts from process start, not from zero, so an unseeded first frame would
    report the whole uptime as its delta and spike anything integrating it.
    """

    var frame_count: Int
    """Frames rendered so far. 1 during the first `update`."""

    var delta: Float64
    """Seconds since the previous frame — multiply motion by this."""

    var delta_millis: Int
    """Milliseconds since the previous frame, unrounded by float division."""

    var elapsed: Float64
    """Seconds accumulated since the first frame."""

    var elapsed_millis: Int
    """Milliseconds accumulated since the first frame."""

    var _last: Int

    def __init__(out self):
        self.frame_count = 0
        self.delta = 0.0
        self.delta_millis = 0
        self.elapsed = 0.0
        self.elapsed_millis = 0
        self._last = 0

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "Time(frame_count=",
            self.frame_count,
            ", delta=",
            self.delta,
            ", delta_millis=",
            self.delta_millis,
            ", elapsed=",
            self.elapsed,
            ", elapsed_millis=",
            self.elapsed_millis,
            ")",
        )

    def _start(mut self, now: Int):
        """Seed the tick stamp so the first frame's delta is a frame, not the
        window clock's whole history."""
        self._last = now

    def _tick(mut self, now: Int):
        self.delta_millis = now - self._last
        self.delta = Float64(self.delta_millis) / 1000.0
        self.elapsed_millis += self.delta_millis
        self.elapsed = Float64(self.elapsed_millis) / 1000.0
        self.frame_count += 1
        self._last = now
