from std.collections import Dict
from std.math import max
from .align import Align
from .color import Color
from .font import Font, _GlyphInfo, FONT_DEFAULT_PATH, FONT_FALLBACK_PATH
from ._raster import blit_glyph
from ._style import Style
from .surface import Surface

comptime _GLYPH_CACHE_LIMIT = 4096
"""Cached masks kept before the cache is dropped whole.

Autoscale makes the pixel size a function of the window, so a window being
dragged larger mints a fresh size — and a fresh set of masks — every frame.
Unbounded, that grows without limit; dropping the lot on the rare occasion it
fills costs one repopulating frame and needs no recency bookkeeping.
"""


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
    """Font ownership and glyph layout, kept out of the drawing surface.

    Holds the loaded faces, so it is the other half of what has to survive a
    frame: reloading a font every frame would be absurd. Lays a string out in
    pixel space and hands each glyph's coverage mask to the rasteriser.
    """

    var _font: List[Font]
    var _fallback_font: List[Font]
    var _fallback_attempted: Bool
    var _glyphs: Dict[Int, _GlyphInfo]
    var font_generation: Int
    """Bumped whenever a cache key starts meaning a different bitmap.

    A key packs codepoint, pixel size and weight, so the eviction in
    `_ensure_glyph` re-renders identical masks and changes nothing — but
    `set_font` makes the same key a different face. A backend that caches
    glyphs of its own (the GL atlas does) watches this and drops them.
    """

    def __init__(out self):
        self._font = List[Font]()
        self._fallback_font = List[Font]()
        self._fallback_attempted = False
        self._glyphs = Dict[Int, _GlyphInfo]()
        self.font_generation = 0

    def set_font(mut self, var f: Font):
        self._font = List[Font]()
        self._font.append(f^)
        # Cached masks belong to the face that drew them, and the key says
        # nothing about which face that was — a swap has to drop them.
        self._glyphs.clear()
        self.font_generation += 1

    def _ensure_font(mut self, size: Int) raises:
        """Lazily load the packaged default/fallback fonts on first use.

        Construction never touches disk — a program that draws no text pays no
        freetype cost and can't fail on a missing default. The fallback load is
        attempted at most once; a missing fallback file just means no fallback
        glyphs, not a draw failure.
        """
        if len(self._font) == 0:
            self._font.append(Font(FONT_DEFAULT_PATH, size))
        if not self._fallback_attempted:
            self._fallback_attempted = True
            try:
                self._fallback_font.append(Font(FONT_FALLBACK_PATH, size))
            except:
                pass

    def _glyph_key(self, codepoint: Int, size: Int, weight: Int) -> Int:
        """Pack what a mask depends on into one key.

        A codepoint is 21 bits and a weight 10, so all three pack into an Int
        with room to spare.
        """
        return codepoint | (size << 21) | (weight << 37)

    def _ensure_glyph(
        mut self, codepoint: Int, size: Int, weight: Int
    ) raises -> Int:
        """Cache the mask for `(codepoint, size, weight)` and return its key.

        Every FreeType call in the text path is behind this miss: rasterising a
        glyph costs an `FT_Load_Char` and an `FT_Render_Glyph` over the C ABI,
        and choosing the face costs an `FT_Get_Char_Index` on top. Laying a
        string out reads each glyph twice — once to measure, once to draw — so
        uncached, a static line of text paid all three per character per frame.

        The mask is alpha only and the pen advance is a number, so nothing here
        depends on the fill, the position or the alignment; only these three
        inputs change what is stored.
        """
        var key = self._glyph_key(codepoint, size, weight)
        if key in self._glyphs:
            return key
        if len(self._glyphs) >= _GLYPH_CACHE_LIMIT:
            self._glyphs.clear()
        # Both faces are set to the requested weight here rather than at the
        # call site, because this is the only place either one rasterises.
        if len(self._fallback_font) > 0 and not self._font[0].has_glyph(
            codepoint
        ):
            self._fallback_font[0]._set_weight(weight)
            self._glyphs[key] = self._fallback_font[0].render(codepoint, size)
        else:
            self._font[0]._set_weight(weight)
            self._glyphs[key] = self._font[0].render(codepoint, size)
        return key

    def glyph_mask(self, key: Int) raises -> List[UInt8]:
        """A copy of a cached glyph's coverage mask, row-major, 8-bit.

        A copy because nothing in this Mojo version can hand back a reference
        to a `Dict` value across a function boundary (Gotcha 4). That is
        affordable only because the one caller — the GL atlas — reads a glyph
        exactly once, on upload; the CPU blit still reads it by reference from
        inside `draw`.
        """
        return self._glyphs[key].pixels.copy()

    def layout(
        mut self,
        s: String,
        tx: Float64,
        ty: Float64,
        style: Style,
        pixel_scale: Float64,
    ) raises -> List[PlacedGlyph]:
        """Place `s` around the already-mapped anchor `(tx, ty)`.

        The caller maps the anchor; glyphs lay out upright in pixel space, so
        `Align.TOP`/`BOTTOM` keep meaning the top and bottom of the text box
        however the world axes are oriented.

        Every glyph is in the cache when this returns, so a caller can read
        each one's mask by key without another FreeType call.
        """
        var size = max(Int(Float64(style.font_size) * pixel_scale + 0.5), 1)
        self._ensure_font(size)
        var weight = style.font_weight

        # Two passes: measure the total advance for alignment, then place.
        var tw = 0
        for cp in s.codepoints():
            var key = self._ensure_glyph(Int(cp), size, weight)
            tw += self._glyphs[key].advance_x

        var draw_x = Int(tx)
        var draw_y = Int(ty)
        var align = style.text_align
        if align._right():
            draw_x -= tw
        elif not align._left():
            draw_x -= tw // 2

        var asc = self._font[0].ascender
        var desc = self._font[0].descender
        var baseline_y = draw_y
        if align._top():
            baseline_y += asc
        elif align._bottom():
            baseline_y += desc
        else:
            baseline_y += (asc + desc) // 2

        var placed = List[PlacedGlyph]()
        var cx = draw_x
        for cp in s.codepoints():
            # Bound by reference: the mask stays in the cache rather than
            # being copied out of it once per character.
            ref g = self._glyphs[self._ensure_glyph(Int(cp), size, weight)]
            if g.width > 0 and g.height > 0:
                placed.append(
                    PlacedGlyph(
                        self._glyph_key(Int(cp), size, weight),
                        cx + g.bearing_x,
                        baseline_y - g.bearing_y,
                        g.width,
                        g.height,
                    )
                )
            cx += g.advance_x
        return placed^

    def draw[
        o: Origin[mut=True]
    ](
        mut self,
        surf: Surface[o],
        s: String,
        tx: Float64,
        ty: Float64,
        style: Style,
        pixel_scale: Float64,
    ) raises:
        """Blit `s` through `layout`, so the CPU and GL paths place a glyph
        with one function rather than two that have to agree."""
        var c = style.text_color
        for ref p in self.layout(s, tx, ty, style, pixel_scale):
            ref g = self._glyphs[p.key]
            blit_glyph(surf, g, p.x, p.y, c)
