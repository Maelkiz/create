from create import *


@fieldwise_init
struct CameraDemo(Program):
    var cam: Camera
    var elapsed: Float64

    @staticmethod
    def create(mut context: Context) raises -> CameraDemo:
        return CameraDemo(Camera(), 0.0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.elapsed = context.time.elapsed
        var speed = 300.0 * context.time.delta
        if context.input.is_key_down("right"):
            self.cam.position += Vector2D(speed, 0.0)
        if context.input.is_key_down("left"):
            self.cam.position += Vector2D(-speed, 0.0)
        if context.input.is_key_down("up"):
            self.cam.zoom = min(3.0, self.cam.zoom + 1.0 * context.time.delta)
        if context.input.is_key_down("down"):
            self.cam.zoom = max(0.3, self.cam.zoom - 1.0 * context.time.delta)

        canvas.background(Color(15, 15, 25))
        canvas.camera(self.cam)

        # World content: a strip of posts stretching far past what any single
        # screen shows, plus a marker at the world origin — panning the
        # camera with left/right scrolls this whole strip underneath it.
        canvas.outline_enabled(False)
        for i in range(-20, 20):
            var x = Float64(i) * 120.0
            var t = (sin(self.elapsed + Float64(i)) + 1.0) / 2.0
            canvas.fill(Color(UInt8(60 + Int(t * 150.0)), 90, 160))
            canvas.rectangle(x, 0.0, 40.0, 200.0)

        canvas.fill(Color(230, 190, 40))
        canvas.circle(0.0, 140.0, 14.0)

        # HUD: fixed to the screen regardless of where the camera looks or
        # how far it has zoomed.
        with canvas.overlay():
            canvas.outline_enabled(False)
            canvas.fill(Color(230, 230, 230))
            canvas.rectangle(0.0, canvas.top() - 20.0, 300.0, 30.0)
            canvas.text_color(Color(20, 20, 20))
            canvas.text_align(Align.CENTER)
            canvas.text(
                "left/right pan, up/down zoom", (0.0, canvas.top() - 20.0)
            )


def main() raises:
    run[CameraDemo]("Camera Demo", width=800, height=600)
