# DDR WORLD speed system — verified semantics

Source: reverse-engineered from a DDR WORLD dump's `gamemdx.dll`
(`ddr::player::Option` and the selectmusic option UI), July 2026. The chart
preview's speed pane ([chart_scroller.dart](../lib/components/song/notes/chart_scroller.dart))
implements exactly this model. Addresses below are VAs in that binary
(32-bit, image base 0x10000000) for re-verification.

The disassembly claims here were re-checked directly against
`modules/gamemdx.dll` from a WORLD dump (4,120,728 bytes, 2025-07-15; PE
machine 0x014c, image base 0x10000000, `.text` VA 0x1000 → raw 0x400), so the
VAs map to file offsets as `va - 0x10000000 - 0x1000 + 0x400`. The dump is not
in this repo and must not be committed.

The BPM semantics were cross-checked against the game's own
`data/gamedata/musicdb.xml`: each record carries only `bpmmin`/`bpmmax` (both
`u16`, matching the getters' `movzx word`), no third BPM value. This is what
establishes that the `+0x6c` divisor is the curated `bpmmax` and NOT a
mechanical note-stream peak — decisively, SMASH is stored `bpmmax=160` while
its chart soflans to 320 (see the SCROLL SPEED section). `bpmmax` is
editorial, so it agrees with this repo's `dominant_bpm` on the plurality of
soflan songs and with `true_max` on the rest; `dominant_bpm` is the proxy the
app divides by.

## SPEED TYPE

WORLD reworked the pre-WORLD SPEED option into a two-type system
(`SetSpeedType` @ 0x10184c50, values 0–2). The option stores **two
independent values** — switching type does not convert one into the other:

- **HI-SPEED** (`Hispeed`, UI asset `speed_rate` / `magnification`)
- **SCROLL SPEED** (`ScrollSpeed`, UI asset `real_speed` / `scroll_speed`)

## HI-SPEED

- Stored as an int in **hundredths**: 25–800 = x0.25–x8.00.
- `SetHispeed` @ 0x10184d60 clamps to [25, 800] then snaps to a **multiple
  of 5 (x0.05)**: it floors to the multiple, but a floored result below 100
  (x1.00) bumps back up one step — i.e. sub-x1 values round UP.
- In-song quick adjust: vtable inc/dec handlers @ 0x10185360/0x101853b0 step
  **±25 (x0.25)**, clamped to the same range.
- Display format string: `"x %.2lf"` — always two decimals.
- The UI's magnification choice list is built 25→800 step **1** (loop @
  0x10119041, init 25 @ 0x10119037) so it can render the x0.01-granular
  multipliers that SCROLL SPEED mode derives (below); manual dialling still
  lands only on the 0.05 grid because of the setter snap.

## SCROLL SPEED ("real speed")

- The dialled value is a target scroll rate. Choice list built **10→1000
  step 10** (loop @ 0x10118d10, init 10 @ 0x10118c3e).
- The effective multiplier is derived, not dialled
  (`SetScrollSpeed` @ 0x10184c80):

  ```
  hundredths = round(scrollSpeed × 100 / bpmmax), clamped to [25, 800]
  ```

  **NOT snapped to 0.05** — real-speed mode reaches x0.01 multipliers that
  HI-SPEED mode can't express.
- The divisor is the record's **`bpmmax`** — and the crucial point is what
  `bpmmax` actually is: the game's single **curated headline BPM** for the
  song, NOT a mechanical peak of the chart's note stream. Traced end-to-end:
  - `SetScrollSpeed` @ 0x10184c80 computes `scrollSpeed × 100` (`imul …,
    0x64` @ 0x10184cff) and divides by a single stored BPM at `[obj+0x90]`
    (`fdiv` @ 0x10184d0a), guarded to ≥ 1.0.
  - `[obj+0x90]` is written by the BPM setter (vtable +0x5c, @ 0x10184c10)
    from its **3rd** double argument (`[ebp+0x18]` → `[ecx+0x90]` @
    0x10184c30); the 1st/2nd go to `[+0x80]`/`[+0x88]`.
  - **The play-side setup (@ 0x1004daf0) confirms the divisor independently.**
    It reads three consecutive u16 record fields — `+0x94`, `+0xbc`, `+0x6c`
    (`movzx word` @ 0x1004dae4 / 0x1004daec / 0x1004daf4) — and stages them
    into the same BPM setter via fixed-slot `fstp`s. Field `+0x6c` lands in
    arg3 = `[+0x90]` (staged at 0x1004db17 → 0x1004db1e → 0x1004db28), so
    `+0x6c` is the divisor. The option-UI caller @ 0x1011db8f does the same via
    getters 0x100c5960 / 0x100c5a70 / **0x100c5b00** (the last reads `+0x6c`),
    filled into slots `[esp]` / `[esp+8]` / `[esp+0x10]` — *not* cdecl pushes;
    re-verify via the slot writes.
  - Those same three getters feed the num_min/num_core/num_max readout (calls
    @ 0x101162e0 / 0x101162f6 / 0x1011630c inside the display fn @
    0x10116240), so field `+0x6c` is the **third/highest** displayed value.
  - **What that field holds — checked against the game's own data.** The WORLD
    dump's `data/gamedata/musicdb.xml` gives each song only `bpmmin` and
    `bpmmax` (both u16, matching the `movzx word` getters), no third BPM value
    anywhere in 1,239 records. The `+0x6c` divisor resolves from `bpmmax`. And
    `bpmmax` is *editorially chosen*, not computed: **SMASH** is stored
    `bpmmin=80 / bpmmax=160` even though its chart soflans to 320. So the
    divisor for SMASH is **160**, and REAL SPEED 600 there gives
    round(600×100/160)=x3.75 → reads 600, matching HI-SPEED x3.75.
  - Consequence: the dialled number pins the song's **headline** tempo, and a
    soflan section faster than the headline genuinely reads faster (uncapped).
    It does NOT pin the mechanical peak — an earlier revision of this doc
    concluded "divisor = mechanical max," which halved read speed on big
    soflans (SMASH read ~300). That was wrong: the disassembly facts were
    right but `bpmmax` ≠ the note-stream peak.
- No usable BPM ⇒ multiplier falls back to x1.00.

### App reconstruction of `bpmmax` — the sustained-peak rule

DDR MD doesn't carry the cabinet's `bpmmax` field; its per-chart data has
`true_min` / `dominant_bpm` / `true_max` plus the timed BPM segment list. But
`bpmmax` is **not** editorial guesswork — it decomposes into a deterministic
rule, measured against `musicdb.xml` over the 1,159 shared songs:

> **`bpmmax` = the highest BPM the chart SUSTAINS for ≥ 2 seconds.**

i.e. the fastest tempo you actually read at, with momentary soflan spikes
excluded. Accuracy of that rule vs the cabinet's stored `bpmmax`:

| predictor | exact match |
|---|---|
| `dominant_bpm` alone | 95% |
| raw note-stream peak (`true_max`) | ~4% on soflans (the old bug) |
| **sustained peak (≥2s)** | **98%** |

The residual ~2% is almost entirely (a) BPM-octave notation differences — the
parser calling a section 190 where the cabinet calls it 380, same music — and
(b) a handful of genuine BPM-gimmick charts (ΔMAX, Hella Deep, London EVOLVED
ver.B) where even a human would debate the headline number. Rounding (±2 BPM,
e.g. ECSTASY 150 vs 145) reads identically and isn't counted as a miss.

So [chart_scroller.dart](../lib/components/song/notes/chart_scroller.dart)'s
`_scrollDivisorBpm` walks `widget.bpms`, sums each tempo's held duration, and
divides REAL SPEED by the fastest tempo held ≥ `_sustainedBpmMinSeconds` (2.0),
falling back to `dominant_bpm` when the chart is too short for any segment to
qualify. For SMASH the 320 flash is sub-2s, so the divisor is 160 and REAL
SPEED 600 reads 600. Locked in by
[test/chart_scroller_speed_type_test.dart](../test/chart_scroller_speed_type_test.dart).

**`true_max` is deliberately preserved and untouched** — it's the real
unreported peak (the cabinet hides it, which is arguably worse), still shown as
chart metadata elsewhere. It is simply not the scroll divisor.

The one thing this rule can't recover is a `bpmmax` the cabinet set *higher*
than anything the chart sustains (e.g. 888, whose parsed stream tops out at
444). Those need the real `bpmmax` imported from `musicdb.xml` — a possible
future data-pipeline step, not required for the 98%.

## Readouts

The speed option shows the resulting scroll speeds next to the dial
(display fn @ 0x10116240): three values = the record's three BPM fields
(`+0xbc`/`+0x94`/`+0x6c`) × current multiplier, rounded. Since those fields
resolve from `bpmmin`/`bpmmax` (the record has no third BPM), and `+0x6c` =
`bpmmax` is the divisor, in SCROLL SPEED mode the top value ≈ the dialled
number itself.

### REAL SPEED vs the equivalent HI-SPEED agree on the headline tempo

Because the divisor is `bpmmax` (the app's sustained-peak reconstruction), REAL
SPEED and HI-SPEED read the **same** at the song's headline tempo. On SMASH
(`bpmmin=80 / bpmmax=160`, chart soflans to 320):

| dialled | derivation | multiplier | reads at the 160 headline section |
|---|---|---|---|
| REAL SPEED 600 | round(600 × 100 / **160**) | x3.75 | **600** |
| HI-SPEED x3.75 | dialled directly | x3.75 | **600** |

They match — which is the whole point of REAL SPEED being "the read speed you
dialled." A 320 soflan section then genuinely reads *faster* (320 × 3.75 =
1200), uncapped, exactly as on a cabinet. Locked in by
[test/chart_scroller_speed_type_test.dart](../test/chart_scroller_speed_type_test.dart).

An earlier revision divided by the note stream's mechanical peak (320 for
SMASH), producing x1.88 → reads ~300, i.e. half the dialled number. That is
the "feels completely wrong vs the arcade" bug: the cabinet has no 320 for
SMASH, so it never halves. Fixed by dividing by dominant.

### App readout

The compact transport speed pane prints the resulting scroll-speed span under
the dialled number — `min → dominant` × the multiplier (i.e. `bpmmin`/`bpmmax`
scaled, the cabinet's two-value model), collapsing to one number on
constant-BPM charts. The mechanical soflan peak is deliberately **not** shown
there: it isn't the divisor and the cabinet doesn't display it either.

## Play-side: the multiplier reaching the field

Confirmed at 0x1004db41–0x1004dbc6 (gameplay object init). The play code:

1. calls the BPM setter (Option vtable +0x5c) with the record's three BPM
   fields (`+0xbc`/`+0x94`/`+0x6c`, i.e. min / mid / bpmmax),
2. reads the resulting speed back — via getter `[+0x108]` when CONSTANT is
   engaged, or the Hispeed getter `[+0x104]` otherwise,
3. **divides by 100.0** (`fdiv` @ 0x1004db64 / 0x1004dbac) and stores the
   result as the scroll multiplier at `[obj+0x1e8]`/`[+0x1ec]`, with the raw
   hundredths kept at `[obj+0x1f4]`.

So the effective multiplier really is `hundredths / 100` — the derivation in
[chart_scroller.dart](../lib/components/song/notes/chart_scroller.dart) matches
the cabinet exactly. The object's ctor (@ 0x1004c790) initialises these
fields to `1.0` (`fld1`) and the hundredths to `0x64` (100).

## CONSTANT

`SetConstantValue` @ 0x10184eb0: the display time is clamped to **100–3000 ms**
and snapped to a multiple of **10** (same round-up-below-the-threshold quirk
as HI-SPEED, here below 1000). The UI's choice list is built 100→3000 step 10
(loop @ 0x1011a04a, init @ 0x10119fbd).

Critically, **there is no BPM term anywhere in CONSTANT's storage or list
build**. CONSTANT is literally "an arrow is visible for N milliseconds",
which makes it the cleanest statement of the game's speed↔time law.

### CONSTANT does not change scroll speed (verified)

CONSTANT is a **visibility** modifier, not a speed one. Two independent
confirmations in the binary:

- **Play-side multiplier is identical on/off.** The gameplay speed setup
  (0x1004db41–0x1004dbc6) reads the active speed type's multiplier through
  getters at Option vtable +0x108 (CONSTANT on) / +0x104 (CONSTANT off), and
  *both* getters (@ 0x10185640 / 0x10185670) branch on SpeedType and return
  the same field — `[opt+0xc]` (Hispeed) or `[opt+0x10]` (ScrollSpeed). The
  +0x108/+0x104 split is only value-vs-pointer calling convention; the
  resulting multiplier is the same either way. So turning CONSTANT on does
  not alter scroll velocity.
- **The speed readout never reads the CONSTANT value.** The num_min/core/max
  display (@ 0x10116240) makes no reference to the CONSTANT display-time
  field (Option+0x28). The cabinet presents scroll speed and CONSTANT as two
  independent numbers.

Consequence for the app: the tempo badge shows `localBpm × mod` and is never
CONSTANT-prefixed. A prior revision synthesised a `max(localRead,
windowEquivalent)` "C###" read-speed floor and showed it on the badge — that
floor is not a cabinet behaviour and made CONSTANT + a speed type read wrong.
CONSTANT lives on its own chip (a display-time in ms), exactly as the cabinet
stores it. The one place the app *does* translate the window into a read
speed is a study aid on that chip (`≈ C###`), computed live as
`max(dialledRead, windowEquivalent)` so it tracks the current speed type
rather than sitting frozen — deliberately more than the cabinet shows, but
clearly scoped to the CONSTANT control.

### The travel constant

Because CONSTANT pins the travel time that a read speed would otherwise
produce, read speed R and display time are the same axis:

```
travel seconds = k / R          ⇔          R = k × 1000 / ms
```

The preview uses **k = 370** (`_arcadeTravelConstant`). This comes from
measurements of DDR WORLD's CONSTANT guideline, and three independently
reported points agree exactly — which is what distinguishes it from a
folklore guess:

| display time | ↔ SPEED | k = SPEED × seconds |
|---|---|---|
| 925 ms | 400 | 370 |
| 740 ms | 500 | 370 |
| 1000 ms | 370 | 370 |

So at read speed 600 an arrow is on screen ~0.62 s, and CONSTANT's 1000 ms
default reads like SPEED 370. The field's scroll velocity and the
CONSTANT-equivalent read speed are both derived from this one constant, so
CONSTANT-on and CONSTANT-off are a single speed system — switching CONSTANT
on at its equivalent read speed leaves the scroll rate unchanged rather than
jumping.

**Why k can't come from the binary.** WORLD stores the CONSTANT option value
(100–3000 ms) and the speed multiplier, but the geometry that turns those
into an on-screen travel *time* — receptor Y and field height — lives in the
`.arc` layout blobs (`data/arc/2d/`), not in `gamemdx.dll`. So the travel
constant is necessarily measured from the running game, not disassembled.

A wrong-turn worth recording: an earlier revision set **k = 180**, reasoning
"370 isn't in the binary, so it's folklore." That was mistaken twice over —
the binary *cannot* contain k (see above), and 180 makes arrows ~2× too fast
(travel 0.30 s at R = 600). It shipped a field that scrolled visibly quicker
than a cabinet before being corrected back to 370.

### Field geometry

The preview scales velocity by its own field's travel distance (bottom edge
→ receptor line, `_ChartPainter.receptorBase` below the top inset) so that
the *travel time* at a given read speed matches the cabinet on any screen
size, rather than every device sharing a fixed px/s and giving taller phones
a longer read.

Not extracted: the cabinet's own playfield geometry (it renders to 720×1280,
but the receptor Y / field height live in the `.arc` layout blobs under
`data/arc/2d/`, not the DLL), and the per-note `Y = f(time, speed)` layout
inside `GamePlayActor`. Neither is needed for the law above, and the
arcade's absolute pixel numbers wouldn't transfer to a resizable field
anyway.
