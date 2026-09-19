from create import *


@fieldwise_init
struct Transforms(Program):
    var elapsed: Float64
    var mouse_x: Int
    var mouse_y: Int

    @staticmethod
    def create(mut ctx: Context) raises -> Transforms:
        return Transforms(elapsed=0.0, mouse_x=0, mouse_y=0)

    def update(mut self, mut ctx: Context, input: Input) raises:
        self.elapsed = ctx.time.elapsed
        self.mouse_x = input.mouse_x
        self.mouse_y = input.mouse_y

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color(8, 8, 20))

        var planet_angle = self.elapsed * tau / 10.0
        var moon_angle = self.elapsed * tau / 3.5

        # Solar system: the sun sits at the origin, so it needs no transform of
        # its own — the nesting below is what the demo is about.
        # Hit-test the sun in the frame it is drawn in. `to_local` maps a world
        # position (which is what `input.mouse` already is) into that frame.
        var local = canvas.to_local(
            Float64(self.mouse_x), Float64(self.mouse_y)
        )
        var lx = local[0]
        var ly = local[1]
        var sun_hovered = lx * lx + ly * ly <= 40.0 * 40.0

        canvas.outline(enabled=False)
        canvas.fill(Color(30, 180, 230) if sun_hovered else Color(230, 180, 20))
        canvas.circle(0.0, 0.0, 40.0)

        # Planet — rotate then translate so it orbits the sun
        with canvas.transform(rotate(planet_angle) @ translate(160.0, 0.0)):
            # Thin orbit guide drawn in planet's frame before further nesting
            canvas.outline(Color(50, 50, 70), thickness=1)
            canvas.fill(enabled=False)
            canvas.circle(0.0, 0.0, 45.0)

            canvas.outline(enabled=False)
            canvas.fill(Color(60, 120, 220))
            canvas.circle(0.0, 0.0, 18.0)

            # Moon — orbits the planet
            with canvas.transform(rotate(moon_angle) @ translate(45.0, 0.0)):
                canvas.fill(Color(170, 170, 170))
                canvas.circle(0.0, 0.0, 8.0)

        # Spinning rect cluster: same transform pattern, different shape.
        # Below and left of centre, so both coordinates are negative.
        with canvas.transform(translate(-232.0, -165.0)):
            canvas.outline(enabled=False)
            canvas.fill(Color(60, 60, 80))
            canvas.circle(0.0, 0.0, 8.0)

            for i in range(6):
                var arm_angle = self.elapsed * 0.9 + Float64(i) * tau / 6.0
                # Arm rotates; rect counter-rotates so it stays axis-aligned in world space
                with canvas.transform(
                    rotate(arm_angle)
                    @ translate(70.0, 0.0)
                    @ rotate(-arm_angle)
                ):
                    var t = (sin(self.elapsed * 2.0 + Float64(i)) + 1.0) / 2.0
                    var r = UInt8(60 + Int(t * 180.0))
                    var b = UInt8(180 - Int(t * 100.0))
                    canvas.fill(Color(r, 80, b))
                    canvas.rectangle(0.0, 0.0, 36.0, 18.0)

        # Rotating triangle fan
        with canvas.transform(translate(232.0, -165.0)):
            for i in range(5):
                var a = self.elapsed * 0.6 + Float64(i) * tau / 5.0
                with canvas.transform(rotate(a)):
                    var g = UInt8(100 + Int(Float64(i) * 30.0))
                    canvas.outline(enabled=False)
                    canvas.fill(Color(40, g, 160))
                    canvas.triangle(0.0, 0.0, 60.0, 15.0, 60.0, -15.0)


def main() raises:
    run[Transforms]("Transform Demo", 800, 600)
