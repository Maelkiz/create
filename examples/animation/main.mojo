"""Two ways to build an animation, and the three playback modes.

`idle` and `run` are cut out of one sprite sheet -- row 0 and row 1 of the
same PNG -- while `spin` is loaded from a folder of numbered frames. Both
end up as the same type, so nothing downstream cares which path was used.

A and D (or Left and Right) run, Space spins, P pauses.
"""

from create import *

comptime _SIZE = 128
comptime _GROUND = -140.0

# Transparent rows under the feet in the source cell, at the rendered scale.
comptime _FOOT_PAD = 12.0


@fieldwise_init
struct Game(Program):
    var idle: Animation
    var run: Animation
    var spin: Animation
    var animator: Animator
    var x: Float64
    var spinning: Bool

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Game:
        var sheet = Image.load(source_path("assets/character.png"))

        # Row-major: the first four cells are the idle cycle, the next four
        # the run cycle. One sheet, two animations, no sheet type.
        var idle = Animation.from_sheet(
            sheet, 32, 32, start=0, count=4, fps=6.0
        )
        var run = Animation.from_sheet(
            sheet, 32, 32, start=4, count=4, fps=12.0
        )

        # spin_1.png .. spin_8.png, ordered by their trailing number rather
        # than lexicographically, so spin_10 would follow spin_9.
        var spin = Animation.from_folder(source_path("assets/spin"), fps=16.0)

        var animator = Animator(idle)
        animator.loop()
        return Game(idle^, run^, spin^, animator^, 0.0, False)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var speed = 240.0 * context.time.delta

        if context.input.key_pressed(Key.SPACE) and not self.spinning:
            # A one-shot: it holds its last frame and reports is_finished().
            self.animator.play(self.spin)
            self.spinning = True

        if self.spinning:
            if self.animator.is_finished():
                self.spinning = False
        else:
            var dx = 0.0
            if context.input.key_down(Key.A) or context.input.key_down(
                Key.LEFT
            ):
                dx -= speed
            if context.input.key_down(Key.D) or context.input.key_down(
                Key.RIGHT
            ):
                dx += speed
            self.x += dx

            # Called every single frame with whichever animation applies.
            # `use` of the one already showing is a no-op, so this neither
            # rewinds to frame 0 sixty times a second nor undoes a pause;
            # `loop(...)` here would restart it every frame.
            if dx != 0.0:
                self.animator.use(self.run)
            else:
                self.animator.use(self.idle)

        if context.input.key_pressed(Key.P):
            if self.animator.is_playing():
                self.animator.pause()
            else:
                self.animator.resume()

        var margin = Float64(_SIZE) / 2.0
        self.x = clamp(self.x, canvas.left() + margin, canvas.right() - margin)
        self.animator.update(context.time.delta)

        canvas.background(Color(40, 40, 44))

        canvas.outline_enabled(False)

        # The ground runs from its surface all the way to the bottom edge, so
        # it never floats over the background however tall the window is.
        var height = _GROUND - canvas.bottom()
        canvas.fill(Color(30, 30, 33))
        canvas.rectangle(
            (0.0, canvas.bottom() + height / 2.0), canvas.right() * 2.0, height
        )

        # Rendered four times the 32x32 source size -- pixel art wants to be
        # scaled up, and the sized overload does it without touching the asset.
        canvas.image(
            self.animator,
            (self.x, _GROUND + _SIZE / 2.0 - _FOOT_PAD),
            _SIZE,
            _SIZE,
        )

        canvas.text_color(Color(176, 172, 162))
        canvas.text_align(Align.TOP)
        canvas.font_size(20)
        canvas.text(
            "A/D: run   Space: spin   P: pause",
            (0.0, 140.0),
        )


def main() raises:
    run[Game]("Animation", width=800, height=600)
