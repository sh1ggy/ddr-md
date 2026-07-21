# Chart-preview noteskin

The scrolling chart preview ([lib/components/song/notes/chart_scroller.dart](../lib/components/song/notes/chart_scroller.dart))
draws its notes through a pluggable [`Noteskin`](../lib/components/song/notes/noteskin.dart).

Two implementations exist:

- **`VectorNoteskin`** — the default fallback. Fully vector-drawn arrows,
  freeze/hold tubes, shock-arrow lightning bars, mines and receptors. Nothing
  external is bundled, so the preview looks good out of the box and there is no
  copyright question. Used whenever the sprite assets are absent.
- **`SpriteNoteskin`** — renders real DDR World arrow art from
  `assets/noteskin/` when present: the grey `note.png` tinted per quantisation,
  and `hold_body.png` / `hold_head.png` for freezes. Mines/shock/receptors fall
  back to the vector skin. `SpriteNoteskin.tryLoad()` returns `null` when the
  sprites aren't bundled (fresh clone / lite build), and `ChartScroller` uses
  the vector skin in that case.

## Arrow colouring

Arrows are coloured by **note quantisation** (the fraction of a beat they land
on), the standard DDR/ITG reading palette — see `QuantColors`:

| Subdivision | Colour |
|---|---|
| 4th  | red |
| 8th  | blue |
| 12th | purple |
| 16th | yellow |
| 24th | pink |
| 32nd | orange |
| finer | green |

## Note data

The preview consumes `assets/steps/<name>.json` (see the DDR-BPM-prep
`CODEBASE.md`, `steps_data`). Note-type codes: `0` tap, `1` hold, `2` roll,
`3` mine; holds/rolls carry `e`/`es` (tail beat + second). **Shock arrows** are
not a distinct type — they are a full row of mines sharing one second, and the
scroller detects them (`_detectShocks`, 3+ mines at the same time) and draws
them as lightning bars instead of individual mines.

## Official DDR World sprites (extraction)

The real arrow textures live in a DDR World arcade dump under
`data/arc/2d/2d_arrow00.arc … 2d_arrow07.arc`. Each is a Konami `.arc`
container (magic `0x19751120`) wrapping a **BEMANI/firebeat LZ77**-compressed
32-bit BGRA `.dds`. `DDR-BPM-prep/src/classes/ArcExtractor.py` decompresses and
decodes these with no external image deps (clean-room, stdlib only).

Findings from the real assets:

- Every `2d_arrow0N.arc` is a **768×192 atlas**, a grid of 96×96 cells.
- The 8 files are **animation/state variants, all one green palette** — DDR
  World colours arrows **by direction** in-game, *not* by note quantisation.
  So there is no per-quantisation sprite to pull; instead cell **(0,0) is a
  colourless GREY arrow**, which the app tints per quantisation.
- Cell **(4,0)** is the tiled freeze **body**; cell **(0,1)** is the freeze
  **tail/end cap** used to mark where the hold releases. The arrow points
  **left**; the app rotates it per lane.

### Extracting

With a dump symlinked/copied into `DDR-BPM-prep/data/arcade/`:

```
make noteskin        # -> DDR-BPM-prep/build/noteskin/{note,hold_body,hold_tail}.png
```

(No dump → polite no-op.) Then copy the three PNGs into the app's
**git-ignored** `assets/noteskin/`:

```
cp DDR-BPM-prep/build/noteskin/*.png <app>/assets/noteskin/
```

`assets/noteskin/` is registered in `pubspec.yaml` and git-ignored (copyrighted
Konami art, like the step charts and jackets). Present → `SpriteNoteskin`
renders real arrows; absent → `VectorNoteskin`. No runtime `.arc` parsing is
involved — the app only ever loads PNGs.

### Sprite files the app consumes

```
assets/noteskin/
  note.png       # 96x96 grey left arrow, tinted per quantisation in-app
                 # (used for taps AND freeze heads)
  hold_body.png  # 96x96 green freeze body, tiled down the lane
  hold_tail.png  # 96x96 freeze tail/end cap from the atlas
```

Shock arrows (`data/arc/bm2d/dance_shock_arrow_v*.arc`, an uncompressed `.ifs`)
and mines/receptors are not extracted; the vector skin draws those.
