# How chart tiers work

## What the number means

**14.90 means near the hard end of level 14 for scoring well.** The official
level stays 14. It is not your predicted score or chance of clearing, and does
not mean exactly 90% of level-14 charts are easier.

## The calculation

1. **Measure the chart:** pace, busy sections, rhythm changes, jumps, holds,
   shocks, footwork, stops and speed changes. For example, 12 step rows in two
   seconds is 6 rows/second; a row may contain several arrows.
2. **Compare at the same level:** use both the raw measurements and where they
   sit among a frozen reference set of charts at that official level.
3. **Predict a position:** models trained against 3icecream reference tiers
   estimate where the chart belongs within its level. They learn combinations
   of measurements; there is no fixed “one crossover adds 0.05” rule.
4. **Display a tier:** add that position to the official level, rounding the
   position **down** in 0.05 steps. Level 19 uses 0.10 steps. Clamp the result
   between the official level and 0.05 below the next level (0.10 for level 19).

**Example:** level 14 + predicted position 0.927 → **14.90**.

Personal scores, title and artist are not prediction inputs. Calculation happens
offline; the app reads the result from song metadata. Adding a song does not
re-rank existing charts because references stay frozen. Supports Singles 1–19.

## Exact blend: scoring-v31

`F` = movement/footwork model blend; `R` = rhythm/density model blend;
`T` = model including timing/visibility; `P` = short-passage model.

```text
Levels 1–7: position = F

Levels 8–19:
  B = (F + R) / 2
  B = (B + level_correction(B)) / 2     # levels 8–18 only
  position = 0.90 × (T + B) / 2 + 0.10 × P

s = 0.05 (0.10 for level 19)
tier = official level + clamp(floor(position / s) × s, 0, 1 − s)
```

The correction is a fitted straight line reducing bias for that level. These
weights combine overlapping models; they are not independent skill ratings or
percentages explaining an individual chart.

## Ready-to-use app wording

Tap the tier to open **About tiers**:

> **14.90 · Scoring difficulty**
>
> Near the hard end of level 14. Estimated from the chart's pace, rhythms,
> footwork and timing changes using a model trained against community tiers.
> Your scores do not affect it.
>
> Compare charts at the same level. Small differences are approximate; your
> strengths can change which chart feels harder.

Expandable **How it works**: **Measure chart → Compare at this level → Estimate
tier**. Keep the official level prominent. Current metadata cannot support
per-chart contribution percentages or confidence ranges.

Implementation: `inference.py` applies frozen comparisons/models;
`fingerprint.py::tier_for` converts position to tier. Weights and corrections
live in the frozen bundle.
