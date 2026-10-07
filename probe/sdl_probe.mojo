from std.os import setenv
from std.time import perf_counter_ns

from create._library import load_library

comptime VIDEO: UInt32 = 0x20
comptime GAMEPAD: UInt32 = 0x2000


def ms(t0: Int) -> String:
    return String((perf_counter_ns() - t0) // 1000000) + " ms"


def main() raises:
    _ = setenv("SDL_VIDEODRIVER", "dummy", True)
    var sdl = load_library("libSDL3")
    var title = String("t")
    for round in range(3):
        var t = perf_counter_ns()
        _ = sdl.call["SDL_Init", Bool](VIDEO)
        print(round, "video init", ms(t))
        t = perf_counter_ns()
        _ = sdl.call["SDL_InitSubSystem", Bool](GAMEPAD)
        print(round, "gamepad init", ms(t))
        t = perf_counter_ns()
        var w = sdl.call["SDL_CreateWindow", Int](
            title.unsafe_ptr(), Int32(64), Int32(64), UInt64(0)
        )
        print(round, "create window", ms(t))
        t = perf_counter_ns()
        sdl.call["SDL_DestroyWindow"](w)
        sdl.call["SDL_QuitSubSystem"](GAMEPAD)
        print(round, "gamepad quit", ms(t))
        t = perf_counter_ns()
        sdl.call["SDL_QuitSubSystem"](VIDEO)
        print(round, "video quit", ms(t))
