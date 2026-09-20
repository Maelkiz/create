from create import *


@fieldwise_init
struct CameraDemo(Program):
    var cam: Camera
    var elapsed: Float64

    @staticmethod
    def create(mut frame: Frame) raises -> CameraDemo:
        return CameraDemo(Camera(), 0.0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.elapsed = frame.time.elapsed
        var speed = 300.0 * frame.time.delta
        if input.is_key_down("right"):
            self.cam.position += Vector2D(speed, 0.0)
        if input.is_key_down("left"):
            self.cam.position += Vector2D(-speed, 0.0)
        if input.is_key_down("up"):
            self.cam.zoom = min(3.0, self.cam.zoom + 1.0 * frame.time.delta)
        if input.is_key_down("down"):
            self.cam.zoom = max(0.3, self.cam.zoom - 1.0 * frame.time.delta)

    def render(self, mut frame: Frame) raises:
        frame.background(Color(15, 15, 25))
        frame.camera(self.cam)

        # World content: a strip of posts stretching far past what any single
        # screen shows, plus a marker at the world origin — panning the
        # camera with left/right scrolls this whole strip underneath it.
        frame.outline(enabled=False)
        for i in range(-20, 20):
            var x = Float64(i) * 120.0
            var t = (sin(self.elapsed + Float64(i)) + 1.0) / 2.0
            frame.fill(Color(UInt8(60 + Int(t * 150.0)), 90, 160))
            frame.rectangle(x, 0.0, 40.0, 200.0)

        frame.fill(Color(230, 190, 40))
        frame.circle(0.0, 140.0, 14.0)

        # HUD: fixed to the screen regardless of where the camera looks or
        # how far it has zoomed.
        with frame.overlay():
            frame.outline(enabled=False)
            frame.fill(Color(230, 230, 230))
            frame.rectangle(0.0, frame.top() - 20.0, 300.0, 30.0)
            frame.text_color(Color(20, 20, 20))
            frame.text_align(Align.CENTER)
            frame.text(
                "left/right pan, up/down zoom", (0.0, frame.top() - 20.0)
            )


def main() raises:
    run[CameraDemo]("Camera Demo", 800, 600)
