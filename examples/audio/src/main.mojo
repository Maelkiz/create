"""Playing sounds: a one-shot chime and a looping ambience.

Space plays the chime; hold H to loop the ambience.
"""

from create import *


@fieldwise_init
struct AudioDemo(Program):
    var audio: Audio
    var chime: Sound
    var ambience: Sound
    var ambience_voice: Voice
    var looping: Bool

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> AudioDemo:
        var audio = Audio()
        var chime = Sound.load(source_path("../assets/chime.wav"))
        var ambience = Sound.load(source_path("../assets/ambience.wav"))
        return AudioDemo(audio^, chime, ambience, Voice.NONE, False)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.audio.update()

        if context.input.key_pressed(Key.SPACE):
            _ = self.audio.play(self.chime)

        if context.input.key_pressed(Key.H):
            self.ambience_voice = self.audio.loop(self.ambience)
            self.looping = True
        if context.input.key_released(Key.H):
            self.audio.stop(self.ambience_voice)
            self.looping = False

        canvas.background(Color.WHITE)
        canvas.text_color(Color.BLACK)
        canvas.font_size(24)
        canvas.text_align(Align.TOP)
        canvas.text("space: chime    hold h: loop ambience", (0, 20))
        canvas.text("looping: " + String(self.looping), (0, -20))


def main() raises:
    run[AudioDemo]("Audio", width=480, height=240)
