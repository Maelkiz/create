"""Playing sounds: a one-shot chime, and a looping ambience to pause, resume
and turn up or down.

Each `play` or `loop` returns a `Voice`, the handle that playback of that one
sound is controlled by; the `Audio` itself holds the overall volume, which
scales every voice's own. `audio.update()` runs every frame, or looping
voices stall.

Space plays the chime. L starts or stops the ambience, P pauses and resumes
it, Up and Down set its volume, Left and Right the overall volume.
"""

from create import *

comptime _BACKGROUND = Color(40, 40, 44)
comptime _TRACK = Color(62, 62, 68)
comptime _LEVEL = Color(98, 104, 168)
comptime _CHIME = Color(226, 46, 56)
comptime _TEXT = Color(240, 236, 222)
comptime _HINT = Color(176, 172, 162)
comptime _BAR_WIDTH = 360.0
comptime _VOLUME_STEP = 0.6
"""How far a held arrow key turns a volume, per second."""


def _volume_bar(mut canvas: Canvas, label: String, level: Float64, y: Float64):
    """A labelled bar, filled to `level` of its width."""
    var left = -_BAR_WIDTH / 2.0
    with canvas.style(outline_enabled=False):
        canvas.fill(_TRACK)
        canvas.rectangle((0.0, y), _BAR_WIDTH, 14.0, corner_radius=7)
        if level > 0.0:
            canvas.fill(_LEVEL)
            var w = _BAR_WIDTH * level
            canvas.rectangle((left + w / 2.0, y), w, 14.0, corner_radius=7)
    with canvas.style(text_color=_TEXT, font_size=18, text_align=Align.RIGHT):
        canvas.text(label, (left - 20.0, y))
    with canvas.style(text_color=_TEXT, font_size=18, text_align=Align.LEFT):
        canvas.text(String(Int(level * 100.0 + 0.5), "%"), (-left + 20.0, y))


@fieldwise_init
struct AudioDemo(Program):
    var audio: Audio
    var chime: Sound
    var ambience: Sound
    var ambience_voice: Voice
    """The looping ambience, or `Voice.NONE` while it is stopped."""
    var ambience_volume: Float64
    """Kept here as well as on the voice, so a restarted loop keeps it."""
    var chimed_at: Float64
    """When the chime last played, to flash the circle."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> AudioDemo:
        return AudioDemo(
            audio=Audio(),
            chime=Sound.load(source_path("assets/chime.wav")),
            ambience=Sound.load(source_path("assets/ambience.wav")),
            ambience_voice=Voice.NONE,
            ambience_volume=0.8,
            chimed_at=-10.0,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.audio.update()
        ref input = context.input
        var step = _VOLUME_STEP * context.time.delta

        if input.key_pressed(Key.SPACE):
            _ = self.audio.play(self.chime)
            self.chimed_at = context.time.elapsed

        if input.key_pressed(Key.L):
            if self.ambience_voice == Voice.NONE:
                self.ambience_voice = self.audio.loop(self.ambience)
                self.audio.volume(self.ambience_voice, self.ambience_volume)
            else:
                self.audio.stop(self.ambience_voice)
                self.ambience_voice = Voice.NONE
        if input.key_pressed(Key.P) and self.ambience_voice != Voice.NONE:
            if self.audio.is_playing(self.ambience_voice):
                self.audio.pause(self.ambience_voice)
            else:
                self.audio.resume(self.ambience_voice)

        if input.key_down(Key.UP) or input.key_down(Key.DOWN):
            var change = step if input.key_down(Key.UP) else -step
            self.ambience_volume = clamp(
                self.ambience_volume + change, 0.0, 1.0
            )
            self.audio.volume(self.ambience_voice, self.ambience_volume)
        if input.key_down(Key.RIGHT):
            self.audio.volume(clamp(self.audio.volume() + step, 0.0, 1.0))
        if input.key_down(Key.LEFT):
            self.audio.volume(clamp(self.audio.volume() - step, 0.0, 1.0))

        canvas.background(_BACKGROUND)

        # The chime's flash, fading over half a second.
        var since = context.time.elapsed - self.chimed_at
        var flash = clamp(1.0 - since / 0.5, 0.0, 1.0)
        with canvas.style(
            fill=_TRACK.lerp(_CHIME, flash), outline_enabled=False
        ):
            canvas.circle((-250.0, 40.0), 40.0 + 12.0 * flash)
        with canvas.style(text_color=_HINT, font_size=18):
            canvas.text("Space: chime", (-250.0, -30.0))

        var state: String
        if self.ambience_voice == Voice.NONE:
            state = "stopped"
        elif self.audio.is_playing(self.ambience_voice):
            state = "playing"
        else:
            state = "paused"
        with canvas.style(text_color=_TEXT, font_size=26):
            canvas.text("Ambience " + state, (120.0, 60.0))
        with canvas.style(text_color=_HINT, font_size=18):
            canvas.text("L: start/stop   P: pause/resume", (120.0, 20.0))

        _volume_bar(canvas, "Ambience", self.ambience_volume, -90.0)
        _volume_bar(canvas, "Overall", self.audio.volume(), -140.0)
        with canvas.style(text_color=_HINT, font_size=18):
            canvas.text(
                "Up/Down: ambience volume   Left/Right: overall volume",
                (0.0, -200.0),
            )

        with canvas.style(text_color=_TEXT, font_size=30, text_align=Align.TOP):
            canvas.text("Audio", (0, canvas.top() - 20.0))


def main() raises:
    run[AudioDemo]("Audio", width=800, height=500)
