"""Test-only helpers for building raw SDL_Event byte buffers.

Field offsets are imported from `create._window._sdl` rather than duplicated here,
so these helpers stay pinned to the same ABI layout `Window.events()` reads.
"""

from create._window._sdl import SDL_EVENT_SIZE


def new_event_buffer(kind: UInt32) -> Array[UInt8, SDL_EVENT_SIZE]:
    var buf = Array[UInt8, SDL_EVENT_SIZE](fill=0)
    buf.unsafe_ptr().unsafe_bitcast[UInt32]()[] = kind
    return buf^


def write_u8(mut buf: Array[UInt8, SDL_EVENT_SIZE], offset: Int, value: UInt8):
    buf.unsafe_ptr().unsafe_offset(offset).unsafe_bitcast[UInt8]()[] = value


def write_u32(
    mut buf: Array[UInt8, SDL_EVENT_SIZE], offset: Int, value: UInt32
):
    buf.unsafe_ptr().unsafe_offset(offset).unsafe_bitcast[UInt32]()[] = value


def write_i32(mut buf: Array[UInt8, SDL_EVENT_SIZE], offset: Int, value: Int32):
    buf.unsafe_ptr().unsafe_offset(offset).unsafe_bitcast[Int32]()[] = value


def write_f32(
    mut buf: Array[UInt8, SDL_EVENT_SIZE], offset: Int, value: Float32
):
    buf.unsafe_ptr().unsafe_offset(offset).unsafe_bitcast[Float32]()[] = value
