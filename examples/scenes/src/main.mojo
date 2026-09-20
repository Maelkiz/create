# Multi-scene composition, not a scene machine.
#
# `Program` stays exactly `create`/`update`. A scene switch is nothing more
# than an int field and an if/elif in `update` —
# `Menu` and `Draw` are plain structs in the same shape as `Program`, not
# `Program`s themselves, which is what lets them take a shared field
# (nothing shared here, but see AGENTS.md's "Program can own Programs").
# See AGENTS.md for why this beats a generic scene-router: no dynamic trait
# dispatch in Mojo, and a router would have nowhere to plug shared state in
# anyway.

from create import *
from menu import Menu
from draw import Draw

comptime MENU = 0
comptime DRAWING = 1


@fieldwise_init
struct App(Program):
    var scene: Int
    var menu: Menu
    var draw: Draw

    @staticmethod
    def create(mut options: Options) raises -> App:
        options.autoscale = AutoScale.FIT
        # The drawing scene accumulates ink across frames, so the per-frame
        # clear is off for the whole program: `Menu` paints its own background
        # every frame, and `Draw` clears once on entry.
        options.autoclear = False
        return App(MENU, Menu(False), Draw(False, False, False, Point2D(0, 0)))

    def update(
        mut self, mut options: Options, mut frame: Frame, input: Input
    ) raises:
        if self.scene == MENU:
            self.menu.update(frame, input)
            if self.menu.start_pressed:
                self.draw.enter()
                self.scene = DRAWING
        else:
            self.draw.update(frame, input)
            if self.draw.back_pressed:
                self.scene = MENU


def main() raises:
    run[App]("Scenes", width=800, height=600)
