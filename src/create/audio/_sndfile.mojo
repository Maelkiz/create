"""Raw `libsndfile` bindings via `std.ffi._DLHandle`, decoding OGG/FLAC/MP3
(anything but WAV, which stays on the zero-dependency `SDL_LoadWAV` path in
`_sdl_audio.mojo`). Same idiom as that file: opaque `Int` handles, own
`_DLHandle`, raise with the library's own error string on every failure.

`SF_INFO` (from `sndfile.h`) is
`{ sf_count_t frames; int samplerate; int channels; int format; int sections; int seekable; }`
-- `sf_count_t` is `int64_t`, so `frames` sits at offset 0 (8 bytes),
`samplerate`/`channels`/`format`/`sections`/`seekable` are 4-byte `int`s
starting at offset 8, and the struct is 8-byte aligned (32 bytes total, one
int's worth of trailing padding).
"""

from std.ffi import _DLHandle

from create._bytes import cstr as _cstr
from create._library import load_library

comptime SFM_READ: Int32 = 0x10
comptime _SF_INFO_SIZE = 32
comptime _OFF_FRAMES = 0
comptime _OFF_SAMPLERATE = 8
comptime _OFF_CHANNELS = 12


struct SndFile:
    var lib: _DLHandle

    def __init__(out self) raises:
        self.lib = load_library("libsndfile")

    def load(self, path: String) raises -> Tuple[List[Int16], Int32, Int32]:
        """Decode an audio file to interleaved S16 PCM. Returns (samples, channels, freq).
        """
        var info = List[UInt8](length=_SF_INFO_SIZE, fill=0)
        var cpath = _cstr(path)
        var handle = self.lib.call["sf_open", Int](
            cpath.unsafe_ptr(), SFM_READ, info.unsafe_ptr()
        )
        if handle == 0:
            var err = self.lib.call[
                "sf_strerror", Pointer[UInt8, MutUntrackedOrigin]
            ](Int(0))
            raise Error("sf_open failed: " + String(unsafe_from_utf8_ptr=err))

        var frames = (
            info.unsafe_ptr()
            .unsafe_offset(_OFF_FRAMES)
            .unsafe_bitcast[Int64]()[]
        )
        var samplerate = (
            info.unsafe_ptr()
            .unsafe_offset(_OFF_SAMPLERATE)
            .unsafe_bitcast[Int32]()[]
        )
        var channels = (
            info.unsafe_ptr()
            .unsafe_offset(_OFF_CHANNELS)
            .unsafe_bitcast[Int32]()[]
        )

        var samples = List[Int16](length=Int(frames) * Int(channels), fill=0)
        var read_frames = self.lib.call["sf_readf_short", Int64](
            handle, samples.unsafe_ptr(), frames
        )
        _ = self.lib.call["sf_close", Int32](handle)

        if read_frames < frames:
            var actual = List[Int16](
                length=Int(read_frames) * Int(channels), fill=0
            )
            var src = samples.unsafe_ptr()
            var dst = actual.unsafe_ptr()
            for i in range(len(actual)):
                dst[unsafe_offset=i] = src[unsafe_offset=i]
            return actual^, channels, samplerate

        return samples^, channels, samplerate
