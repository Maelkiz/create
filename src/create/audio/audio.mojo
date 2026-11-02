from ._sdl_audio import SDLAudio
from .sound import Sound

comptime _GEN_SHIFT = 32
comptime _INDEX_MASK: Int = 0xFFFFFFFF


struct _Voice(Movable):
    """One playback slot. `stream == 0` means free.

    `loop_sound` holds a copy of the playing `Sound` -- sharing its samples,
    not copying them -- and is only populated for looping voices, since a
    one-shot voice never needs its PCM again after the initial `put_data`.
    """

    var stream: Int
    var generation: Int
    # This voice's own volume, from `volume(id, ...)`; it plays at this times
    # `Audio`'s volume.
    var gain: Float64
    var paused: Bool
    var looping: Bool
    var loop_sound: Optional[Sound]

    def __init__(out self):
        self.stream = 0
        # Starts at 1, not 0: id 0 would otherwise be indistinguishable from
        # a zero-initialised `Int` field, so `_encode(0, 0) == 0` must never
        # be issuable. `reset` already bumps a recycled slot's generation, so
        # this only needs to hold for the append path.
        self.generation = 1
        self.gain = 1.0
        self.paused = False
        self.looping = False
        self.loop_sound = None

    def reset(mut self):
        """Return this slot to the free state, bumping its generation so
        stale ids from before the reset fail `_valid`."""
        self.stream = 0
        self.generation += 1
        self.gain = 1.0
        self.paused = False
        self.looping = False
        self.loop_sound = None


struct Voice(Copyable, Equatable, ImplicitlyCopyable, Movable):
    """One playback of a `Sound`, as `audio.play` and `audio.loop` return it:
    the handle `stop`, `pause`, `resume`, `volume` and `is_playing` take.

    A `Sound` can play as several voices at once. A voice that has ended or
    been stopped is stale: every call on it does nothing, even after its slot
    plays another sound. `Voice.NONE` is no voice, for a field before
    anything plays. A handle, like `Sound`, so not printable.
    """

    var _id: Int
    """The slot index and its generation, as `Audio._encode` packs them."""

    comptime NONE = Voice(_id=0)

    def __init__(out self, *, _id: Int):
        self._id = _id

    def __eq__(self, other: Voice) -> Bool:
        return self._id == other._id

    def __ne__(self, other: Voice) -> Bool:
        return self._id != other._id


struct Audio(Movable):
    """Program-owned playback device. Construct once, hold as a Program field,
    call `play` from `update`.

    Call `update` once per frame (e.g. from `Program.update`) -- it reaps
    finished one-shot voices and refills looping ones. SDL keeps playing
    whatever was last queued and never tells this struct a stream finished on
    its own, so skipping `update` silently stalls a loop after its first
    buffer drains, and leaks one-shot voice slots forever.
    """

    var _sdl: SDLAudio
    var _voices: List[_Voice]
    var _volume: Float64

    def __init__(out self) raises:
        self._sdl = SDLAudio()
        self._sdl.init()
        self._voices = List[_Voice]()
        self._volume = 1.0

    def volume(self) -> Float64:
        """The volume every voice plays at, `1.0` unless set."""
        return self._volume

    def volume(mut self, volume: Float64) raises:
        """Set the volume every voice plays at, `0.0` silent and `1.0` as
        recorded. Applies at once, to the voices already playing as well as
        later ones; each voice's own `volume(id, ...)` scales it."""
        self._volume = volume
        for i in range(len(self._voices)):
            if self._voices[i].stream != 0:
                self._apply_gain(i)

    def _apply_gain(mut self, index: Int) raises:
        # SDL takes its gain as a Float32; the API stays in Float64 like
        # every other fraction, and narrows here, at the boundary.
        self._sdl.set_gain(
            self._voices[index].stream,
            Float32(self._volume * self._voices[index].gain),
        )

    @staticmethod
    def _encode(index: Int, generation: Int) -> Int:
        return (generation << _GEN_SHIFT) | index

    @staticmethod
    def _decode(id: Int) -> Tuple[Int, Int]:
        return id & _INDEX_MASK, id >> _GEN_SHIFT

    def _valid(self, id: Int) -> Bool:
        var parts = Self._decode(id)
        var index = parts[0]
        var generation = parts[1]
        return (
            index >= 0
            and index < len(self._voices)
            and self._voices[index].generation == generation
            and self._voices[index].stream != 0
        )

    def play(mut self, sound: Sound) raises -> Voice:
        """Play `sound` once, as a new `Voice`; it frees itself when the
        sound ends."""
        return self._start(sound, loop=False)

    def loop(mut self, sound: Sound) raises -> Voice:
        """Play `sound` over and over until stopped, as a new `Voice`, as
        `Animator.loop` and `Tween.loop` repeat. The voice is refilled by
        `update`, from a copy of `sound` that shares its samples.
        """
        return self._start(sound, loop=True)

    def _start(mut self, sound: Sound, loop: Bool) raises -> Voice:
        var stream = self._sdl.open_device_stream(
            sound._format, Int32(sound._channels), Int32(sound._sample_rate)
        )
        self._sdl.set_gain(stream, Float32(self._volume))
        self._sdl.put_data(
            stream, sound._pcm[].unsafe_ptr(), Int32(len(sound._pcm[]))
        )
        self._sdl.resume_stream(stream)
        var loop_sound = Optional(sound) if loop else None

        var index = -1
        for i in range(len(self._voices)):
            if self._voices[i].stream == 0:
                index = i
                break

        if index == -1:
            var voice = _Voice()
            voice.stream = stream
            voice.looping = loop
            voice.loop_sound = loop_sound
            self._voices.append(voice^)
            index = len(self._voices) - 1
        else:
            self._voices[index].stream = stream
            self._voices[index].paused = False
            self._voices[index].looping = loop
            self._voices[index].loop_sound = loop_sound

        return Voice(_id=Self._encode(index, self._voices[index].generation))

    def _free_slot(mut self, index: Int) raises:
        self._sdl.destroy_stream(self._voices[index].stream)
        self._voices[index].reset()

    def stop(mut self, voice: Voice) raises:
        """Stop and release `voice`. No-op if it is already stale."""
        var id = voice._id
        if not self._valid(id):
            return
        self._free_slot(Self._decode(id)[0])

    def stop_all(mut self) raises:
        for i in range(len(self._voices)):
            if self._voices[i].stream != 0:
                self._free_slot(i)

    def pause(mut self, voice: Voice) raises:
        """Hold `voice` where it is; `resume` continues it."""
        var id = voice._id
        if not self._valid(id):
            return
        var index = Self._decode(id)[0]
        self._sdl.pause_stream(self._voices[index].stream)
        self._voices[index].paused = True

    def volume(self, voice: Voice) -> Float64:
        """`voice`'s own volume, `1.0` unless set; `0.0` once it is stale."""
        if not self._valid(voice._id):
            return 0.0
        return self._voices[Self._decode(voice._id)[0]].gain

    def volume(mut self, voice: Voice, volume: Float64) raises:
        """Set `voice`'s own volume, which `volume()` scales: a voice at
        `0.5` under a volume of `0.5` plays at a quarter. No-op if stale."""
        var id = voice._id
        if not self._valid(id):
            return
        var index = Self._decode(id)[0]
        self._voices[index].gain = volume
        self._apply_gain(index)

    def resume(mut self, voice: Voice) raises:
        """Continue a paused `voice` from where it was held."""
        var id = voice._id
        if not self._valid(id):
            return
        var index = Self._decode(id)[0]
        self._sdl.resume_stream(self._voices[index].stream)
        self._voices[index].paused = False

    def is_playing(self, voice: Voice) -> Bool:
        """Whether `voice` is sounding: false once paused or stale."""
        var id = voice._id
        if not self._valid(id):
            return False
        return not self._voices[Self._decode(id)[0]].paused

    def update(mut self) raises:
        """Reap finished one-shot voices and top up looping ones.

        Looping voices are topped up *before* the queue drains (once queued
        audio drops below one loop's worth), not after `available()` hits 0
        -- by then the device has already gone silent and the refill lands
        late, audible as a click/pop at every loop boundary.
        """
        for i in range(len(self._voices)):
            if self._voices[i].stream == 0:
                continue
            if self._voices[i].looping:
                var pcm_len = len(self._voices[i].loop_sound.value()._pcm[])
                if self._sdl.available(self._voices[i].stream) < Int32(pcm_len):
                    self._sdl.put_data(
                        self._voices[i].stream,
                        self._voices[i].loop_sound.value()._pcm[].unsafe_ptr(),
                        Int32(pcm_len),
                    )
            elif self._sdl.available(self._voices[i].stream) == 0:
                self._free_slot(i)

    def __deinit__(deinit self):
        try:
            self.stop_all()
            self._sdl.quit()
        except:
            pass
