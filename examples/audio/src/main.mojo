from std.memory import ArcPointer

from create import *


@fieldwise_init
struct AudioDemo(Program):
    var audio: Audio
    var chime: ArcPointer[Sound]
    var ambience: ArcPointer[Sound]
    var loop_id: Int
    var looping: Bool

    @staticmethod
    def create(mut context: Context) raises -> AudioDemo:
        context.quit_on_escape = True
        var audio = Audio()
        var chime = ArcPointer(Sound.load(source_path("../assets/chime.wav")))
        var ambience = ArcPointer(
            Sound.load(source_path("../assets/ambience.wav"))
        )
        return AudioDemo(audio^, chime, ambience, 0, False)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.audio.update()

        if context.input.just_pressed("space"):
            _ = self.audio.play(self.chime)

        if context.input.just_pressed("h"):
            self.loop_id = self.audio.play(self.ambience, loop=True)
            self.looping = True
        if context.input.just_released("h"):
            self.audio.stop(self.loop_id)
            self.looping = False

        canvas.background(Color.WHITE)
        canvas.text_color(Color.BLACK)
        canvas.font_size(24)
        canvas.text_align(Align.TOP)
        canvas.text("space: chime    hold h: loop ambience", (0, 20))
        canvas.text("looping: " + String(self.looping), (0, -20))


def main() raises:
    run[AudioDemo]("Audio", width=480, height=240)
