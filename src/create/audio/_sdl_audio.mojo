"""Raw SDL3 audio bindings via `std.ffi._DLHandle`.

Internal only — nothing here is re-exported from the package `__init__`.
Mirrors the FFI idiom of `create/_window/_sdl.mojo`: opaque `Int` handles
for everything SDL returns a pointer for, `get_error()` on every failure, and
its own `_DLHandle("libSDL3.so")` rather than importing the window's, since
`audio` has no business depending on the platform window. A second `dlopen`
of the same shared object returns the same handle, and SDL ref-counts
`SDL_InitSubSystem`/`SDL_QuitSubSystem` per subsystem, so `SDL_INIT_AUDIO`
here coexists safely with the window's `SDL_INIT_VIDEO`.

`SDL_AudioSpec` is `{ SDL_AudioFormat format; int channels; int freq; }` —
three packed 4-byte fields, no padding (verified against
`SDL3/SDL_audio.h`). Everywhere a `SDL_AudioSpec*` is needed, a
`List[Int32](length=3)` stands in for it.

`SDL_LoadWAV`'s `Uint8 **audio_buf` out-param is a pointer-to-pointer, one
level deeper than any existing binding handles. It's read back with
`Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=...)`, the same
raw-address-to-Pointer idiom `_window/gl_window.mojo` uses for
`SDL_GL_GetProcAddress` results.
"""

from std.ffi import _DLHandle

from create._bytes import cstr as _cstr

comptime SDL_INIT_AUDIO: UInt32 = 0x00000010
comptime SDL_AUDIO_S16: Int32 = 0x8010
comptime SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK: UInt32 = 0xFFFFFFFF


struct SDLAudio:
    """Thin wrapper over the dynamically-loaded SDL3 library's audio API."""

    var lib: _DLHandle

    def __init__(out self) raises:
        self.lib = _DLHandle("libSDL3.so")

    def get_error(self) raises -> String:
        var ptr = self.lib.call[
            "SDL_GetError", Pointer[UInt8, MutUntrackedOrigin]
        ]()
        return String(unsafe_from_utf8_ptr=ptr)

    def init(self) raises:
        if not self.lib.call["SDL_InitSubSystem", Bool](SDL_INIT_AUDIO):
            raise Error(
                "SDL_InitSubSystem(SDL_INIT_AUDIO) failed: " + self.get_error()
            )

    def quit(self) raises:
        self.lib.call["SDL_QuitSubSystem"](SDL_INIT_AUDIO)

    def load_wav(
        self, path: String
    ) raises -> Tuple[List[UInt8], Int32, Int32, Int32]:
        """Load a WAV file. Returns (pcm, format, channels, freq)."""
        var spec = List[Int32](length=3, fill=0)
        var buf_out = List[Int](length=1, fill=0)
        var len_out = List[Int32](length=1, fill=0)
        var cpath = _cstr(path)

        if not self.lib.call["SDL_LoadWAV", Bool](
            cpath.unsafe_ptr(),
            spec.unsafe_ptr(),
            buf_out.unsafe_ptr(),
            len_out.unsafe_ptr(),
        ):
            raise Error("SDL_LoadWAV failed: " + self.get_error())

        var audio_len = Int(len_out[0])
        var src = Pointer[UInt8, MutUntrackedOrigin](
            unsafe_from_address=buf_out[0]
        )
        var pcm = List[UInt8](length=audio_len, fill=0)
        var dst = pcm.unsafe_ptr()
        for i in range(audio_len):
            dst[unsafe_offset=i] = src[unsafe_offset=i]
        self.lib.call["SDL_free"](buf_out[0])

        return pcm^, spec[0], spec[1], spec[2]

    def open_device_stream(
        self, format: Int32, channels: Int32, freq: Int32
    ) raises -> Int:
        var spec = List[Int32](length=3, fill=0)
        spec[0] = format
        spec[1] = channels
        spec[2] = freq
        var stream = self.lib.call["SDL_OpenAudioDeviceStream", Int](
            SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, spec.unsafe_ptr(), Int(0), Int(0)
        )
        if stream == 0:
            raise Error("SDL_OpenAudioDeviceStream failed: " + self.get_error())
        return stream

    def put_data(self, stream: Int, data: Pointer[UInt8, _], len: Int32) raises:
        if not self.lib.call["SDL_PutAudioStreamData", Bool](stream, data, len):
            raise Error("SDL_PutAudioStreamData failed: " + self.get_error())

    def resume_stream(self, stream: Int) raises:
        if not self.lib.call["SDL_ResumeAudioStreamDevice", Bool](stream):
            raise Error(
                "SDL_ResumeAudioStreamDevice failed: " + self.get_error()
            )

    def pause_stream(self, stream: Int) raises:
        if not self.lib.call["SDL_PauseAudioStreamDevice", Bool](stream):
            raise Error(
                "SDL_PauseAudioStreamDevice failed: " + self.get_error()
            )

    def set_gain(self, stream: Int, gain: Float32) raises:
        if not self.lib.call["SDL_SetAudioStreamGain", Bool](stream, gain):
            raise Error("SDL_SetAudioStreamGain failed: " + self.get_error())

    def available(self, stream: Int) raises -> Int32:
        return self.lib.call["SDL_GetAudioStreamAvailable", Int32](stream)

    def clear_stream(self, stream: Int) raises:
        if not self.lib.call["SDL_ClearAudioStream", Bool](stream):
            raise Error("SDL_ClearAudioStream failed: " + self.get_error())

    def destroy_stream(self, stream: Int) raises:
        self.lib.call["SDL_DestroyAudioStream"](stream)
