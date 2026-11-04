"""Multi-scene composition, not a scene machine.

`Program` stays exactly `create`/`update`. A scene switch is nothing more
than an int field and an if/elif in `update`. `Menu` and `Paint` are plain
structs, not `Program`s, so each `update` takes only what it uses and a
switch can hand over whatever it carries (`enter`). AGENTS.md's "Multiple
screens" says why this beats a generic scene router: Mojo has no dynamic
trait dispatch, and one shared trait would force a single `update`
signature on every scene.
"""

from create import *
from menu import Menu
from paint import Paint

comptime _MENU = 0
comptime _DRAWING = 1


@fieldwise_init
struct App(Program):
    var scene: Int
    var menu: Menu
    var paint: Paint

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        # The painting scene accumulates ink across frames, so the per-frame
        # clear is off for the whole program: `Menu` paints its own background
        # every frame, and `Paint` clears once on entry.
        canvas.autoclear(False)
        return App(_MENU, Menu(False), Paint(False, False))

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        if self.scene == _MENU:
            self.menu.update(context, canvas)
            if self.menu.start_pressed:
                self.paint.enter()
                self.scene = _DRAWING
        else:
            self.paint.update(context, canvas)
            if self.paint.back_pressed:
                self.scene = _MENU


def main() raises:
    run[App]("Scenes", width=800, height=600)
