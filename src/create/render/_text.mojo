from std.collections import Dict, Optional
from std.math import max, min
from .align import Align
from create.color.color import Color
from create.text.font import (
    Font,
    _GlyphInfo,
    default_font_path,
    fallback_font_path,
)
from ._blur import blur_alpha
from ._raster import blit_glyph
from .style import Style
from .surface import Surface

comptime _MAX_SIZE = 4095
"""The largest pixel size text is rasterised at: 12 bits of the glyph key."""
comptime _MAX_WEIGHT = 1023
"""The largest weight a key can hold, 10 bits; faces stop at 900 anyway."""
comptime _MAX_BLUR = 1023
"""The widest shadow blur, in pixels, a glyph mask is made for: 10 bits."""
comptime _FONT_SLOTS = 1024
"""Faces one renderer keys glyphs for before it starts over: 10 bits."""

comptime _GLYPH_CACHE_LIMIT = 4096
"""Cached masks kept before the cache is dropped whole.

Autoscale makes the pixel size a function of the window, so a window being
dragged larger mints a fresh size — and a fresh set of masks — every frame.
Unbounded, that grows without limit; dropping the lot on the rare occasion it
fills costs one repopulating frame and needs no recency bookkeeping.
"""


def _pixel_size(style: Style, pixel_scale: Float64) -> Int:
    """The font size in pixels: world units scaled, at least one and at most
    `_MAX_SIZE`."""
    return min(
        max(Int(Float64(style.font_size) * pixel_scale + 0.5), 1), _MAX_SIZE
    )


def _key_weight(style: Style) -> Int:
    """The style's weight, clamped into the glyph key's 10 bits."""
    return min(max(style.font_weight, 0), _MAX_WEIGHT)


struct PlacedGlyph(Copyable, Movable):
    """One glyph of a laid-out string, positioned in device pixels.

    What `layout` returns and both backends consume: the CPU replay blits the
    cached mask at `(x, y)`, the GL one packs that same mask into its atlas and
    emits a quad there. Neither re-derives a pen position, so alignment cannot
    drift between them.

    `key` indexes `TextRenderer`'s cache rather than carrying the mask, because
    a mask is a `List[UInt8]` and copying one per character per frame is the
    cost the cache exists to avoid.
    """

    var key: Int
    """`_ensure_glyph`'s key — already cached by the time this is returned."""
    var x: Int
    """Device x of the mask's left edge."""
    var y: Int
    """Device y of the mask's top edge."""
    var width: Int
    var height: Int

    def __init__(out self, key: Int, x: Int, y: Int, width: Int, height: Int):
        self.key = key
        self.x = x
        self.y = y
        self.width = width
        self.height = height


struct TextRenderer(Movable):
    """Font ownership and glyph layout, kept out of the rendering surface.

    Holds the loaded faces, so it is the other half of what has to survive a
    frame: reloading a font every frame would be absurd. Lays a string out in
    pixel space and hands each glyph's coverage mask to the rasteriser.
    """

    var _default: Optional[Font]
    """Noto Sans, loaded on first use."""
    var _fallback_font: List[Font]
    var _fallback_attempted: Bool
    var _fonts: Dict[Int, Font]
    """The faces glyphs have been cached for, by slot: the number a glyph
    key carries to say which face drew it. Held so a slot keeps naming its
    face for as long as its keys are cached."""
    var _font_slots: Dict[Int, Int]
    """`Font._id` to its slot."""
    var _glyphs: Dict[Int, _GlyphInfo]
    var atlas_generation: Int
    """Bumped whenever a glyph key starts meaning a different bitmap — only
    when the slots run out and are handed out afresh. A backend that caches
    glyphs of its own (the GL atlas does) watches this and drops them.
    Switching fonts does not bump it: each face has keys of its own."""

    def __init__(out self):
        self._default = None
        self._fallback_font = List[Font]()
        self._fallback_attempted = False
        self._fonts = Dict[Int, Font]()
        self._font_slots = Dict[Int, Int]()
        self._glyphs = Dict[Int, _GlyphInfo]()
        self.atlas_generation = 0

    def _ensure_font(mut self) raises:
        """Lazily load the packaged default/fallback fonts on first use.

        Construction never touches disk — a program that renders no text pays no
        freetype cost and can't fail on a missing default. The fallback load is
        attempted at most once; a missing fallback file just means no fallback
        glyphs, not a render failure.
        """
        if not self._default:
            self._default = Font.load(default_font_path())
        if not self._fallback_attempted:
            self._fallback_attempted = True
            try:
                self._fallback_font.append(Font.load(fallback_font_path()))
            except:
                pass

    def _face(mut self, style: Style) raises -> Font:
        """The face `style` draws text in: its own, or the packaged
        default, and its italic if the style asks for one. The italic has an
        identity of its own, so it takes a slot of its own."""
        self._ensure_font()
        var f = (
            style.font.value().copy() if style.font else self._default.value()
        )
        if style.font_italic:
            return f._italic()
        return f^

    def _slot(mut self, f: Font) -> Int:
        """The slot `f`'s glyphs are keyed by, assigned on first sight.

        Slots are 10 bits of the key. A renderer that has seen that many
        faces starts over: every cached glyph goes, and `atlas_generation`
        tells the GL atlas its keys now mean something else.
        """
        if f._id in self._font_slots:
            try:
                return self._font_slots[f._id]
            except:
                pass  # unreachable: just checked
        if len(self._fonts) >= _FONT_SLOTS:
            self._fonts.clear()
            self._font_slots.clear()
            self._glyphs.clear()
            self.atlas_generation += 1
        var slot = len(self._fonts)
        self._fonts[slot] = f.copy()
        self._font_slots[f._id] = slot
        return slot

    def _glyph_key(
        self, slot: Int, codepoint: Int, size: Int, weight: Int, blur: Int = 0
    ) -> Int:
        """Pack what a mask depends on into one key: 21 bits of codepoint,
        12 of size, 10 of weight, 10 of blur and 10 of font slot. Size, weight
        and blur are clamped into theirs where they enter (`_MAX_SIZE`,
        `_MAX_WEIGHT`, `_MAX_BLUR`)."""
        return (
            codepoint
            | (size << 21)
            | (weight << 33)
            | (blur << 43)
            | (slot << 53)
        )

    def _ensure_glyph(
        mut self,
        slot: Int,
        codepoint: Int,
        size: Int,
        weight: Int,
        blur: Int = 0,
    ) raises -> Int:
        """Cache the mask for `(codepoint, size, weight, blur)` in the face
        in `slot`, and return its key.

        A `blur` above 0 is a shadow's: the plain mask blurred with sigma
        `blur / 2` pixels, grown by the blur's reach and moved back by it, so
        it lays out exactly where the plain glyph does. `blur` is a whole
        number of pixels so that a zooming camera, which changes it
        continuously, mints a new mask only once per pixel.

        Every FreeType call in the text path is behind this miss: rasterising a
        glyph costs an `FT_Load_Char` and an `FT_Render_Glyph` over the C ABI,
        and choosing the face costs an `FT_Get_Char_Index` on top. Laying a
        string out reads each glyph twice — once to measure, once to render — so
        uncached, a static line of text paid all three per character per frame.

        The mask is alpha only and the pen advance is a number, so nothing here
        depends on the fill, the position or the alignment; only these three
        inputs change what is stored.
        """
        var key = self._glyph_key(slot, codepoint, size, weight, blur)
        if key in self._glyphs:
            return key
        if blur > 0:
            var plain = self._ensure_glyph(slot, codepoint, size, weight)
            ref g = self._glyphs[plain]
            var mask = blur_alpha(
                g.pixels, g.width, g.height, Float64(blur) / 2.0
            )
            var blurred = _GlyphInfo(
                mask.width,
                mask.height,
                g.bearing_x - mask.pad,
                g.bearing_y + mask.pad,
                g.advance_x,
            )
            blurred.pixels = mask.pixels.copy()
            if len(self._glyphs) >= _GLYPH_CACHE_LIMIT:
                self._glyphs.clear()
            self._glyphs[key] = blurred^
            return key
        if len(self._glyphs) >= _GLYPH_CACHE_LIMIT:
            self._glyphs.clear()
        # Both faces are set to the requested weight here rather than at the
        # call site, because this is the only place either one rasterises.
        # A copy shares the face, so this is where it rasterises.
        var face = self._fonts[slot].copy()
        if len(self._fallback_font) > 0 and not face.has_glyph(codepoint):
            # Italic text falls back to the fallback's italic. The key names
            # the primary face's slot, so the two never share an entry.
            var fallback = self._fallback_font[0].copy()
            if face._draws_italic:
                fallback = fallback._italic()
            fallback._set_weight(weight)
            self._glyphs[key] = fallback.render(codepoint, size)
        else:
            face._set_weight(weight)
            self._glyphs[key] = face.render(codepoint, size)
        return key

    def glyph_mask(self, key: Int) raises -> List[UInt8]:
        """A copy of a cached glyph's coverage mask, row-major, 8-bit.

        A copy because nothing in this Mojo version can hand back a reference
        to a `Dict` value across a function boundary (Gotcha 4). That is
        affordable only because the one caller — the GL atlas — reads a glyph
        exactly once, on upload; the CPU blit still reads it by reference from
        inside `render`.
        """
        return self._glyphs[key].pixels.copy()

    def _advance(
        mut self, slot: Int, s: String, size: Int, weight: Int, blur: Int
    ) raises -> Int:
        """The pen advance across `s` in pixels: its width as laid out, since
        glyphs are placed advance to advance with no kerning."""
        var advance = 0
        for cp in s.codepoints():
            var key = self._ensure_glyph(slot, Int(cp), size, weight, blur)
            advance += self._glyphs[key].advance_x
        return advance

    def width(
        mut self, s: String, style: Style, pixel_scale: Float64
    ) raises -> Int:
        """How wide `layout` makes `s`, in pixels, without placing it."""
        var size = _pixel_size(style, pixel_scale)
        var slot = self._slot(self._face(style))
        return self._advance(slot, s, size, _key_weight(style), 0)

    def layout(
        mut self,
        s: String,
        tx: Float64,
        ty: Float64,
        style: Style,
        pixel_scale: Float64,
        blur: Int = 0,
    ) raises -> List[PlacedGlyph]:
        """Place `s` around the already-mapped anchor `(tx, ty)`, as masks
        blurred by `blur` pixels (see `_ensure_glyph`).

        The caller maps the anchor; glyphs lay out upright in pixel space, so
        `Align.TOP`/`BOTTOM` keep meaning the top and bottom of the text box
        however the world axes are oriented.

        Every glyph is in the cache when this returns, so a caller can read
        each one's mask by key without another FreeType call.
        """
        var size = _pixel_size(style, pixel_scale)
        var face = self._face(style)
        var slot = self._slot(face)
        var weight = _key_weight(style)
        var blur_px = min(max(blur, 0), _MAX_BLUR)

        # Two passes: measure the total advance for alignment, then place.
        var tw = self._advance(slot, s, size, weight, blur_px)

        var pen_x = Int(tx)
        var pen_y = Int(ty)
        var align = style.text_align
        if align._right():
            pen_x -= tw
        elif not align._left():
            pen_x -= tw // 2

        # Set the size first: with every glyph cached, nothing above did.
        face._set_size(size)
        var asc = face.ascender()
        var desc = face.descender()
        var baseline_y = pen_y
        if align._top():
            baseline_y += asc
        elif align._bottom():
            baseline_y += desc
        else:
            baseline_y += (asc + desc) // 2

        var placed = List[PlacedGlyph]()
        var cx = pen_x
        for cp in s.codepoints():
            # Bound by reference: the mask stays in the cache rather than
            # being copied out of it once per character.
            var key = self._ensure_glyph(slot, Int(cp), size, weight, blur_px)
            ref g = self._glyphs[key]
            if g.width > 0 and g.height > 0:
                placed.append(
                    PlacedGlyph(
                        key,
                        cx + g.bearing_x,
                        baseline_y - g.bearing_y,
                        g.width,
                        g.height,
                    )
                )
            cx += g.advance_x
        return placed^

    def render[
        o: Origin[mut=True]
    ](
        mut self,
        surf: Surface[o],
        s: String,
        tx: Float64,
        ty: Float64,
        style: Style,
        pixel_scale: Float64,
        blur: Int = 0,
    ) raises:
        """Blit `s` through `layout`, so the CPU and GL paths place a glyph
        with one function rather than two that have to agree."""
        var c = style.text_color
        for ref p in self.layout(s, tx, ty, style, pixel_scale, blur):
            ref g = self._glyphs[p.key]
            blit_glyph(surf, g, p.x, p.y, c)
