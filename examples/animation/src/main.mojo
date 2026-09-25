from std.memory import ArcPointer

from create import *

comptime _SIZE = 128
comptime _GROUND = -140.0

# Transparent rows under the feet in the source cell, at the rendered scale.
comptime _FOOT_PAD = 12.0


@fieldwise_init
struct Game(Program):
    """Two ways to build an animation, and the three playback modes.

    `idle` and `run` are cut out of one sprite sheet -- row 0 and row 1 of the
    same PNG -- while `spin` is loaded from a folder of numbered frames. Both
    end up as the same type, so nothing downstream cares which path was used.
    """

    var idle: ArcPointer[SpriteAnimation]
    var run: ArcPointer[SpriteAnimation]
    var spin: ArcPointer[SpriteAnimation]
    var animator: SpriteAnimator
    var x: Float64
    var spinning: Bool

    @staticmethod
    def create(mut context: Context) raises -> Game:
        var sheet = Sprite.load(source_path("../assets/character.png"))

        # Row-major: the first four cells are the idle cycle, the next four
        # the run cycle. One sheet, two animations, no SpriteSheet type.
        var idle = ArcPointer(
            SpriteAnimation.from_sheet(sheet, 32, 32, start=0, count=4, fps=6.0)
        )
        var run = ArcPointer(
            SpriteAnimation.from_sheet(
                sheet, 32, 32, start=4, count=4, fps=12.0
            )
        )

        # spin_1.png .. spin_8.png, ordered by their trailing number rather
        # than lexicographically, so spin_10 would follow spin_9.
        var spin = ArcPointer(
            SpriteAnimation.from_folder(source_path("../assets/spin"), fps=16.0)
        )

        var animator = SpriteAnimator(idle.copy())
        animator.loop()
        return Game(idle^, run^, spin^, animator^, 0.0, False)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var speed = 240.0 * context.time.delta

        if context.input.just_pressed("space") and not self.spinning:
            # A one-shot: it holds its last frame and reports is_finished().
            self.animator.play(self.spin.copy())
            self.spinning = True

        if self.spinning:
            if self.animator.is_finished():
                self.spinning = False
        else:
            var dx = 0.0
            if context.input.is_key_down("a") or context.input.is_key_down(
                "left"
            ):
                dx -= speed
            if context.input.is_key_down("d") or context.input.is_key_down(
                "right"
            ):
                dx += speed
            self.x += dx

            # Called every single frame with whichever animation applies.
            # Switching to the one already playing is a no-op by design, so
            # this does not rewind to frame 0 sixty times a second.
            if dx != 0.0:
                self.animator.loop(self.run.copy())
            else:
                self.animator.loop(self.idle.copy())

        if context.input.just_pressed("p"):
            if self.animator.is_playing():
                self.animator.pause()
            else:
                self.animator.resume()

        var margin = Float64(_SIZE) / 2.0
        self.x = clamp(self.x, canvas.left() + margin, canvas.right() - margin)
        self.animator.update(context.time.delta)

        canvas.background(Color(24, 26, 34))

        canvas.outline_enabled(False)

        # The ground runs from its surface all the way to the bottom edge, so
        # it never floats over the background however tall the window is.
        var height = _GROUND - canvas.bottom()
        canvas.fill(Color(38, 42, 54))
        canvas.rectangle(
            (0.0, canvas.bottom() + height / 2.0), canvas.right() * 2.0, height
        )

        # Rendered four times the 32x32 source size -- pixel art wants to be
        # scaled up, and the sized overload does it without touching the asset.
        canvas.sprite(
            self.animator,
            (self.x, _GROUND + _SIZE / 2.0 - _FOOT_PAD),
            _SIZE,
            _SIZE,
        )

        canvas.text_color(Color(150, 160, 180))
        canvas.text_align(Align.TOP)
        canvas.font_size(20)
        canvas.text(
            "A / D to run  -  SPACE to spin  -  P to pause spin animation",
            (0.0, 140.0),
        )


def main() raises:
    run[Game]("Animation Example", width=800, height=600)
