# DDR WORLD speed system — verified semantics

Source: reverse-engineered from a DDR WORLD dump's `gamemdx.dll`
(`ddr::player::Option` and the selectmusic option UI), July 2026. The chart
preview's speed pane ([chart_scroller.dart](../lib/components/song/notes/chart_scroller.dart))
implements exactly this model. Addresses below are VAs in that binary
(32-bit, image base 0x10000000) for re-verification.

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
  hundredths = round(scrollSpeed × 100 / maxBPM), clamped to [25, 800]
  ```

  **NOT snapped to 0.05** — real-speed mode reaches x0.01 multipliers that
  HI-SPEED mode can't express.
- The divisor is the chart's **max BPM**: the BPM setter (vtable +0x5c,
  @ 0x10184c10) receives (min, core, max) — confirmed by its caller
  @ 0x1011db8f, which fetches min/core/max via the same getters the
  `speed_num` display uses (0x100c5960/0x100c5a70/0x100c5b00 ↔
  `num_min_usr`/`num_core_usr`/`num_max_usr`) — and the derivation divides by
  the third (max). So the dialled number pins the chart's **fastest**
  section; slower sections read proportionally below it.
- No usable BPM (max ≤ 0) ⇒ multiplier falls back to x1.00.

## Readouts

The speed option shows the resulting scroll speeds next to the dial
(display fn @ 0x10116240): `num_min`/`num_core`/`num_max` = min/core/max BPM
× current multiplier, rounded. In SCROLL SPEED mode `num_max` therefore
equals (approximately) the dialled value itself.
