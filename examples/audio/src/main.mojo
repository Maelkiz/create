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
    def create(mut options: Options) raises -> AudioDemo:
        options.quit_on_escape = True
        var audio = Audio()
        var chime = ArcPointer(
            Sound.load(script_dir() + "/../assets/chime.wav")
        )
        var ambience = ArcPointer(
            Sound.load(script_dir() + "/../assets/ambience.wav")
        )
        return AudioDemo(audio^, chime, ambience, 0, False)

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        self.audio.update()

        if frame.input.just_pressed("space"):
            _ = self.audio.play(self.chime)

        if frame.input.just_pressed("h"):
            self.loop_id = self.audio.play(self.ambience, loop=True)
            self.looping = True
        if frame.input.just_released("h"):
            self.audio.stop(self.loop_id)
            self.looping = False

        frame.background(Color.WHITE)
        frame.text_color(Color.BLACK)
        frame.font_size(24)
        frame.text_align(Align.TOP)
        frame.text("space: chime    hold h: loop ambience", 0, 20)
        frame.text("looping: " + String(self.looping), 0, -20)


def main() raises:
    run[AudioDemo]("Audio", width=480, height=240)
