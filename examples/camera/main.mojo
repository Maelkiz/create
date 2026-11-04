"""A `Camera` over a world wider than the screen, and a label in
`canvas.overlay()` that stays put whatever the camera does.

The mouse is in screen space; `camera.to_world` says where it is in the
world. Zooming keeps the world point under the cursor where it is, and a
click drops a marker there, which then stays put in the world.

Left and Right pan, the mouse wheel zooms, a click drops a marker, C clears
them.
"""

from create import *

comptime _BACKGROUND = Color(18, 18, 24)
comptime _MARKER = Color(120, 210, 140)
comptime _TEXT = Color(200, 200, 212)
comptime _PAN_SPEED = 300.0
"""Screen units per second, so a pan feels the same at any zoom."""
comptime _ZOOM_STEP = 1.15
"""How much one notch of the wheel zooms in or out."""


@fieldwise_init
struct CameraDemo(Program):
    var camera: Camera
    var markers: List[Point2D]
    """Where the clicks landed, in world space."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> CameraDemo:
        return CameraDemo(Camera(), [])

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        ref input = context.input
        var pan = _PAN_SPEED * context.time.delta / self.camera.zoom
        if input.key_down(Key.RIGHT):
            self.camera.position += Vector2D(pan, 0.0)
        if input.key_down(Key.LEFT):
            self.camera.position -= Vector2D(pan, 0.0)

        # Zoom about the cursor: note the world point under it, zoom, then
        # move the camera so that point is back under the cursor.
        if input.mouse_wheel.y != 0.0:
            var before = self.camera.to_world(input.mouse)
            self.camera.zoom = clamp(
                self.camera.zoom * pow(_ZOOM_STEP, input.mouse_wheel.y),
                0.3,
                4.0,
            )
            self.camera.position += before - self.camera.to_world(input.mouse)

        if input.mouse_pressed():
            self.markers.append(self.camera.to_world(input.mouse))
        if input.key_pressed(Key.C):
            self.markers.clear()

        canvas.background(_BACKGROUND)
        canvas.camera(self.camera)

        # World content: a strip of posts stretching far past what any single
        # screen shows, and a marker at the world origin.
        canvas.outline_enabled(False)
        for i in range(-20, 20):
            var x = Float64(i) * 120.0
            var t = (sin(context.time.elapsed + Float64(i)) + 1.0) / 2.0
            canvas.fill(Color(60, 110, 210).lerp(Color(120, 210, 140), t))
            canvas.rectangle((x, 0.0), 40.0, 200.0)

        canvas.fill(Color(90, 170, 255))
        canvas.circle((0.0, 140.0), 14.0)

        # In world units, so a marker grows and shrinks with the zoom.
        with canvas.style(fill=_MARKER, outline=_TEXT, outline_thickness=2):
            for marker in self.markers:
                canvas.circle(marker, 10.0)

        # HUD: fixed to the screen regardless of where the camera looks or
        # how far it has zoomed.
        with canvas.overlay():
            with canvas.style(
                text_color=_TEXT, font_size=18, text_align=Align.TOP
            ):
                canvas.text(
                    "Left/Right pan, the wheel zooms, a click drops a marker, C"
                    + " clears",
                    (0.0, canvas.top() - 16.0),
                )
                var world = self.camera.to_world(input.mouse)
                canvas.text(
                    String(
                        "Zoom ",
                        round(self.camera.zoom, 2),
                        "x   Mouse in the world: (",
                        Int(world.x),
                        ", ",
                        Int(world.y),
                        ")",
                    ),
                    (0.0, canvas.top() - 44.0),
                )


def main() raises:
    run[CameraDemo]("Camera", width=800, height=600)
