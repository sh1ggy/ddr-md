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
  tail}.png`), and four direction-oriented shock arrows
  (`arrow-shock-{left,down,up,right}.png`). The freeze **tail** sprite is
  modulated to the freeze green (roll orange for rolls) so its end cap matches
  the hold body's colour. Mines/receptors fall back to the vector skin.
  `SpriteNoteskin.tryLoad()` returns `null` when the sprites aren't bundled
  (fresh clone / lite build), and `ChartScroller` uses the vector skin in that
  case.

## Arrow colouring

Arrows are coloured by **note quantisation** (the fraction of a beat they land
on), the standard DDR/ITG reading palette — see `QuantColors`. Only 4 sprite
colours are extracted, so `SpriteNoteskin` maps the finer subdivisions onto
the nearest sprite (`_nearestSpriteColor`):

| Subdivision | Colour | Sprite used |
|---|---|---|
| 4th  | red | red |
| 8th  | blue | blue |
| 12th | purple | blue |
| 16th | yellow | yellow |
| 24th | pink | yellow |
| 32nd | orange | green |
| finer | green | green |

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
renders real arrows; absent → `VectorNoteskin`. No runtime `.arc` parsing is
involved — the app only ever loads PNGs.

An older extraction path (`DDR-BPM-prep/src/extract_noteskin.py`, `make
noteskin`) pulls a single **colourless grey** arrow plus a green hold body/tail
out of a DDR World arcade dump's `2d_arrow00.arc` atlas (see that script's
docstring for the `.arc`/`.dds` format details) and tints it per quantisation
at runtime. `SpriteNoteskin` no longer consumes that output — the sprites
below are the current, better-fidelity set (pre-coloured, pre-shaded, matching
the in-game glossy chevron look) and must be sourced by hand.

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
  arrow-shock-left.png   arrow-shock-down.png    # 60x60 shock arrows,
  arrow-shock-up.png     arrow-shock-right.png   # pre-oriented per direction
```

Mines and receptors are not covered by this set; the vector skin draws those.
