# Chart-preview noteskin

The scrolling chart preview ([lib/components/song/notes/chart_scroller.dart](../lib/components/song/notes/chart_scroller.dart))
draws its notes through a pluggable [`Noteskin`](../lib/components/song/notes/noteskin.dart).

Two implementations exist:

- **`VectorNoteskin`** — the default fallback. Fully vector-drawn arrows,
  freeze/hold tubes, shock-arrow lightning bars, mines and receptors. Nothing
  external is bundled, so the preview looks good out of the box and there is no
  copyright question. Used whenever the sprite assets are absent.
- **`SpriteNoteskin`** — renders real DDR World arrow art from
  `assets/noteskin/` when present: four pre-coloured down-facing tap arrows
  (`arrow-note-down-{red,blue,yellow,green}.png`, rotated per lane), four
  direction-oriented freeze bodies/tails (`hold-{left,down,up,right}-{body,
  tail}.png`). Shocks use an optional `shock-row.png` animation (two columns by
  four rows), drawn once per pad over colour-matched tap glyphs. Their padded
  aura texture is cached once and reused across directions and zoom levels;
  older bundles retain the fallback.
  The freeze body ends at the top of
  the **tail** cap, which is centred on the tail's second like a tap, and its
  tiles hang from the cap so they scroll with the chart while the freeze is
  held. Rolls tint body and cap orange. Mines/receptors fall back to the vector
  skin.
  `SpriteNoteskin.tryLoad()` returns `null` when the sprites aren't bundled
  (fresh clone / lite build), and `ChartScroller` uses the vector skin in that
  case.

## Arrow colouring

Arrows are coloured by **note quantisation** (the fraction of a beat they land
on) — see `QuantColors`. QUANT COLORS gives the full reading palette (4ths red,
8ths blue, 12ths purple, 16ths yellow, 24ths pink, 32nds orange, finer green);
off, it's the cabinet's, where only 4ths, 8ths and 16ths keep a colour.
`SpriteNoteskin` tints a grey tap arrow to the exact colour, so every quant
shows.

## Note data

The preview consumes `assets/steps/<name>.json` (see the DDR-BPM-prep
`CODEBASE.md`, `steps_data`). Note-type codes: `0` tap, `1` hold, `2` roll,
`3` mine; holds/rolls carry `e`/`es` (tail beat + second). **Shock arrows** are
not a distinct type — they are a full row of mines sharing one second, and the
scroller detects them (`_detectShocks`, 3+ mines at the same time) and draws
them as lightning bars instead of individual mines.

## Official DDR World sprites

`assets/noteskin/` is registered in `pubspec.yaml` and git-ignored (copyrighted
Konami art, like the step charts and jackets). Present → `SpriteNoteskin`
renders real arrows; absent → `VectorNoteskin`. The app only ever loads PNGs.

The sprites below are pre-coloured and pre-shaded, and must be sourced by
hand.

### Sprite files the app consumes

```
assets/noteskin/
  arrow-note-down-red.png     # 60x60 down-facing tap arrow, one per
  arrow-note-down-blue.png    # quantisation colour; rotated per lane for
  arrow-note-down-yellow.png  # left/up/right (see the colour table above)
  arrow-note-down-green.png
  hold-left-body.png   hold-left-tail.png    # 120x256 / 120x120 freeze
  hold-down-body.png   hold-down-tail.png    # body (tiled down the lane) and
  hold-up-body.png     hold-up-tail.png      # end cap, pre-oriented per
  hold-right-body.png  hold-right-tail.png   # direction. The tail is modulated
                                             # to the freeze green (roll orange)
                                             # so its cap matches the body.
  hold-head.png        # 96x96 left-facing freeze head on note.png's grid
                       # (same 3px margin), rotated per lane like a tap; optional,
                       # older bundles draw the tinted tap arrow instead
  arrow-shock-left.png   arrow-shock-down.png    # 60x60 shock arrows,
  arrow-shock-up.png     arrow-shock-right.png   # pre-oriented per direction
  bomb.png             # 98x98 hit bursts with a 1px border: white for a
  bomb-freeze.png      # step, yellow for a completed freeze; optional,
                       # older bundles draw the blown-out arrow flash
```

Mines and receptors are not covered by this set; the vector skin draws those.

### Cabinet arrow art (optional)

With these two present, freezes use the cabinet's head, body and cropped tail.
BLINKING (on by default) also draws receptors and taps through their moving
cabinet palettes; off, they're the static sprites above. Under QUANT COLORS,
12ths, 24ths and 32nds get palettes of their own in the cabinet's shape
([ddr_atlas.dart](../lib/components/song/notes/ddr_atlas.dart)):

```
assets/noteskin/
  arrow-atlas.png      # 768x192 DDR World arrow sheet, unmodified: tap and
                       # freeze-head cells on top, the four freeze tails below,
                       # the four 96x192 freeze bodies on the right
  freeze-palette.png   # 16x16 freeze palette, row = fade step, column = band
```

The sheet is index-coloured: each texel's red value names a band, and the
band's colour comes from a palette, so it must be copied as-is (no resizing or
recolouring). Without either file the sprite skin draws as before.
