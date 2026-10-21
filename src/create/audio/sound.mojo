from std.memory import ArcPointer

from ._sdl_audio import SDLAudio, SDL_AUDIO_S16
from ._sndfile import SndFile


struct Sound(Copyable, ImplicitlyCopyable, Movable):
    """Decoded PCM plus the format it is in — the asset, not a playing voice.

    Decoding happens once, at load; `Audio.play` reads the buffer without
    touching the file again. Copying one is cheap, like copying an `Image`:
    the copies share the samples, and so does every voice playing it.
    """

    var _pcm: ArcPointer[List[UInt8]]
    var format: Int32
    var channels: Int32
    var sample_rate: Int32

    def __init__(
        out self,
        var pcm: List[UInt8],
        format: Int32,
        channels: Int32,
        sample_rate: Int32,
    ):
        self._pcm = ArcPointer(pcm^)
        self.format = format
        self.channels = channels
        self.sample_rate = sample_rate

    @staticmethod
    def load(path: String) raises -> Sound:
        """Load a WAV, OGG, FLAC, or MP3 file. Dispatches on the file's magic
        bytes, not its extension: `RIFF` (WAV) decodes via the zero-dependency
        `SDL_LoadWAV` path; everything else goes through `libsndfile`."""
        var header: List[UInt8]
        with open(path, "r") as f:
            header = f.read_bytes(4)
        if (
            len(header) == 4
            and header[0] == 82
            and header[1] == 73
            and header[2] == 70
            and header[3] == 70
        ):
            var result = SDLAudio().load_wav(path)
            return Sound(result[0].copy(), result[1], result[2], result[3])

        var decoded = SndFile().load(path)
        return Sound.from_pcm(decoded[0].copy(), decoded[1], decoded[2])

    @staticmethod
    def from_pcm(
        data: List[Int16], channels: Int32 = 1, sample_rate: Int32 = 44100
    ) -> Sound:
        """Build a Sound from raw S16LE samples, e.g. a synthesized waveform."""
        var pcm = List[UInt8](length=len(data) * 2, fill=0)
        var dst = pcm.unsafe_ptr()
        for i in range(len(data)):
            var sample = data[i]
            dst[unsafe_offset=i * 2] = UInt8(sample & 0xFF)
            dst[unsafe_offset=i * 2 + 1] = UInt8((sample >> 8) & 0xFF)
        return Sound(pcm^, SDL_AUDIO_S16, channels, sample_rate)
