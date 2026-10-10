# Pattern analysis v2 — plan

> **Status (what shipped differs from §6–7).** The Patterns card's counts are computed
> by the app's own engine ([parity.dart](../../lib/models/parity.dart) +
> [pattern_analysis.dart](../../lib/models/pattern_analysis.dart)) with the Default
> weights, offline by [tool/generate_patterns.dart](../../tool/generate_patterns.dart),
> not by an ITG-standard port in prep. They are DDR-tuned numbers, not comparable
> one-for-one with Simply Love or the spreadsheet. Prep's v1 `pattern_analysis` is
> dropped by `generate_songlist.sh` and not used. The ITG port (phases 0–2) hasn't
> been done.

Replace the prep repo's first-pass `PatternAnalyzer` with an analysis that reproduces
the community-standard tech counts (ITGmania / Simply Love), and add the part
nobody ships: **for every counted pattern, the rule that classified it and the reason
the footing went that way.**

## 1. What the spreadsheet actually is

The three Chart Data Spreadsheet exports come from two different sources:

| File | Source | Use here |
|---|---|---|
| `Single.csv` — Crossovers, Half/Full Crossovers, Footswitches, Up/Down Footswitches, Sideswitches, Jacks, Brackets, Doublesteps, Maximum Notes/Second, Total Stream | Hand-transcribed from **ITGmania / Simply Love's tech pane** (the author says so in [itgmania discussion #726](https://github.com/itgmania/itgmania/discussions/726)) | **Ground truth** for the reference engine |
| `Single (Chart Analyzer).csv` — the `(CO)` / `(DS)` turn, facing, ambiguity columns | The spreadsheet author's own Python scripts (crossover-style and doublestep-style readers, no lookahead) — already studied in [LANDPADDLE-SIGNALS.md](../parity/LANDPADDLE-SIGNALS.md) | Directional sanity check for turn/facing stats only |
| `Averages.csv` | Pivot of steps/jumps/holds/NPS by difficulty, rating, folder | Sanity check; superseded by our own per-level percentiles (§5.4) |

The ten tech columns map 1:1 onto ITGmania's `TechCountsCategory` enum, in the same order.

## 2. Validation spike: the reference is reproducible

A direct Python port of ITGmania v1.0.0's `StepParityGenerator` + `StepParityCost` +
`TechCounts::CalculateTechCountsFromRows` (singles), plus Simply Love's per-measure
stream and peak NPS, run over our 1,263 songs and matched to `Single.csv` on
title + difficulty + steps + jumps:

| Metric | Exact | ±1 | Our Σ | Sheet Σ |
|---|---:|---:|---:|---:|
| Crossovers | 96.4% | 99.6% | 41,627 | 41,648 |
| Half / Full Crossovers | 96.4% / 97.5% | 99.6% / 99.8% | | |
| Footswitches (Up / Down) | 95.9% (97.8 / 97.2) | 99.1% | 5,801 | 5,835 |
| Sideswitches | 99.0% | 99.8% | 944 | 943 |
| Jacks | 98.6% | 99.5% | 8,045 | 8,029 |
| Brackets | 99.0% | 99.9% | 9,426 | 9,420 |
| Doublesteps | 99.1% | 99.9% | 2,691 | 2,685 |
| **All ten exact on the same chart** | **89.9%** | | | |
| Peak NPS (±0.01) | 99.6% | | | |
| Total Stream (±0.05 pt) | 96.0% | | | |

3,770 of 5,338 analysed singles charts matched a sheet row; the rest are title/version
spelling differences, not failures. Runtime: ~105 s for all charts on a laptop.

For contrast, the current prep analyser gets crossovers exactly right on 24% of
charts (`prefer_alternation`) and 12% (`prefer_uncrossed`), MAE 3.6 / 10.9.

**Residuals (381 charts)** are almost all off by 1–2 on a single count and are not
timing problems (only 3 also disagree on peak NPS; stops/BPM changes are at their
base rate). They rise with rating (5% at levels 1–4, 22% at 15+), which fits
near-tie path choices: ITGmania accumulates path cost in 32-bit `float`, so
equal-ish paths can resolve differently than in a 64-bit port. A few are
transcription noise (one chart is off by 37).

## 3. The reference algorithm (what to port, exactly)

All from `itgmania/src` at tag `v1.0.0`. MIT-style licence, so keep the copyright
notice in the ported files.

**Rows** (`StepParityGenerator::CreateRows`): group non-fake notes by *time*. Mines
don't make rows; they attach to the next row (window `(prev, this]`). A hold is
"active" on a row if its head is earlier and its end beat ≥ the row's beat.

**State** per row: feet are `LEFT_HEEL, LEFT_TOE, RIGHT_HEEL, RIGHT_TOE`. Stage
coordinates (singles): L(0,1) D(1,0) U(1,2) R(2,1). A bracket is legal when the two
panels are ≤ √2 apart; a toe can't be placed without its heel. Every placement of
feet onto (notes ∪ held panels) is a candidate. Equal states within a row merge.

**Search**: a layered graph, and the cheapest path wins. Ties go to the
lowest-numbered predecessor (strict `<` relaxation in node order), so candidate
enumeration order is part of the spec.

**Costs** (`StepParityCost.h`): DOUBLESTEP 850, FOOTSWITCH 325 (slow ones only,
0.2–0.4 s), SIDESWITCH 130, MISSED_FOOTSWITCH 500, JACK 30 (only under 0.1 s),
BRACKETJACK 20, BRACKETTAP 400, SLOW_BRACKET 300/s over 0.15 s, HOLDSWITCH 55 × distance,
FACING 2 × (backwardness^1.8 × 100), DISTANCE 6 × dist / elapsed, SPIN 1000,
TWISTED_FOOT 100000, MINE 10000. JUMP, OTHER and CROWDED_BRACKET exist but are off.

**Counting** (`TechCounts.cpp`), over consecutive rows of the chosen path:

| Count | Rule |
|---|---|
| Jack | both rows single-note, same foot, **same** panel, gap < 0.176 s |
| Doublestep | both rows single-note, same foot, **different** panel, gap < 0.235 s |
| Bracket | a row with ≥2 notes where one foot's heel and toe both hit |
| Footswitch (Up / Down) | same panel on consecutive rows, a different foot, gap < 0.3 s, on U or D |
| Sideswitch | the same, on L or R (not part of Footswitches) |
| Crossover | this row's stepping foot lands on the far side of the foot that stepped last row, and that foot didn't also step this row |
| Full vs half | full if the crossing foot started from its own side two rows ago (R→D→L style), half otherwise (U→D→L style) |

**Density** (Simply Love): notes per measure counts *rows* with a tap or hold head
(jumps = 1). Peak NPS = max over measures of rows ÷ measure duration (measures
under 0.12 s ignored). Stream measure = ≥ 16 rows. Total Stream = stream ÷ (stream +
breaks), where breaks under 2 measures are dropped. Breakdown text uses SL's
notation: `20 (2) 30-10|16/4`.

### Quirks to keep for parity (and tests that pin them)

- In `caclFootswitchCost` / `calcMissedFootswitchCost`, mine times are cast to
  `int`, so a mine in the first second of a chart never exempts a footswitch.
- Crossover detection reads only feet that *hit a note* on each row (it ignores
  held feet).
- `whereTheFeetAre[NONE]` gets written on rows with a blank placement. It's harmless,
  but match it.
- 32-bit float cost accumulation (§6, phase 1).

## 4. "Why" — rules for every occurrence

The counts say *what* happened. A player wants *why*: why this is a crossover and
not a doublestep, and whether that was forced or a coin flip. The graph already
holds the answer.

**Forward + backward pass.** After the forward DP (best cost *to* each node), run
one backward pass (best cost *from* each node to the end). For any node,
`through(n) = to(n) + from(n)` is the cheapest whole-chart reading that uses it. For
an occurrence at row *i*, the **margin** is

```
margin = min over nodes n at row i that read the note(s) differently (through(n)) − optimal
```

This is O(rows × states), a single extra pass, instead of the app's current re-solve
per flipped moment ([parity_labels.dart](../../lib/models/parity_labels.dart)).

**Reason.** Keep the per-term cost vector on each edge (ITGmania already labels
16 terms). Walk the best alternative path and diff its term totals against the
chosen path. The largest positive term is the reason:

| Pattern | Reason text template | Typical dominant term |
|---|---|---|
| Crossover | "Crossed: stepping around would need a doublestep at beat B (+850)" | DOUBLESTEP |
| Footswitch | "Switched feet: jacking it at this speed costs +X" / "…flow continues with the other foot" | JACK, DISTANCE |
| Sideswitch | "Switched on the side panel to stay facing forward" | FACING / SPIN |
| Jack | "Same foot: switching would be a slow footswitch (+X)" | FOOTSWITCH (slow) |
| Bracket | "Bracketed: two feet would need a big fast move" | DISTANCE |
| Doublestep | "Unavoidable doublestep: the alternative spins / crosses into a backward facing" | SPIN, FACING |

**Confidence** comes from the margin:
- **Forced:** the margin is at least about one DOUBLESTEP.
- **Clear:** in between.
- **Either works:** the margin is near 0, which is Landpaddle's "okay ambiguity".

The cutoffs between these bands come from the margin histogram, like the "torn"
threshold in commit 64c9938. "Either works" occurrences still count (that's what
the sheet does) but are shown as soft.

Each occurrence is emitted as
`{type, row, beat, second, foot, margin, confidence, reason: {term, delta, at_beat}}`.

## 5. Patterns beyond the ten tech counts

None of these exist in ITGmania. Define each on the **footing**, not on raw column
geometry, which is where v1's candle and staircase went wrong: they were panel
shapes, not how the chart is danced. Every definition is a written rule with a unit
test.

1. **Stream breakdown.** Use SL's 16-row measure rule, for comparability. DDR players
   also care about 8th-note runs at high BPM (MAX 300 is 0% "stream"), so add a
   second, NPS-normalised run measure: measures whose rows/sec ≥ a fixed threshold.
   Label the two separately.
2. **Candle.** One foot's consecutive steps go U→D or D→U (it travels across the
   centre) while the other foot holds a side panel. Report how many were played
   crossed.
3. **Turns.** The body angle per row is the angle between the two feet's positions
   (ITGmania's `getPlayerAngle`). Bucket each row-to-row change into 0/45/90/135°,
   left and right, as in [LANDPADDLE-SIGNALS.md §2](../parity/LANDPADDLE-SIGNALS.md).
   Check direction against the `(CO)` columns, but don't expect exact matches: their
   reader has no lookahead.
4. **Drills, trills, staircases, gallops, jumpstream.** Keep v1's timing rules, but
   require alternating feet from the footing (a "trill" danced as a jack isn't one).
5. **Context.** For each count, its percentile among all charts of the same level in
   our own library ("29 crossovers: top 15% of level 11s"). This replaces the
   Averages.csv ratio, which only had steps, jumps and holds.

## 6. Phases

| # | Work | Where | Done when |
|---|---|---|---|
| 0 | Productionise the spike as `TechAnalyzer.py`, replacing `PatternAnalyzer`'s footwork and structural parts (keep its plain counts, density and quantisation) | DDR-BPM-prep | A regression test against `Single.csv` (skipped if the CSV is absent) passes ≥ 89% all-exact; hand-built fixture rows pin each rule in §3 |
| 1 | Close the residual: float32 cost accumulation, then diff the worst 50 mismatches | prep | All-exact ≥ 95%, or every remaining class explained in the doc |
| 2 | Forward/backward pass, per-term cost vectors, occurrence list with margin, confidence and reason | prep | Reasons read right on a hand-checked set (PARANOiA, ABSOLUTE, Pluto The First, MAX 300, CHAOS Expert/Challenge) |
| 3 | §5 patterns, each with a rule and a test | prep | |
| 4 | `pattern_analysis` schema 2 → `assets/patterns/<name>.json`, plus per-level percentile tables | prep + `generate_songlist.sh` | |
| 5 | Patterns card v2: the six headline counts as in SL's tech pane, stream breakdown, peak NPS, and percentile chips. Tapping a count lists its occurrences with reason and confidence; tapping one opens the chart preview at that beat | app | |
| 6 | (Later) Run the same counting on the app's own engine, giving "your footing" counts beside the ITG-standard counts in the chart preview. Doubles stays experimental: ITGmania has a layout, but its author calls it unvalidated and there's no DP ground truth | app | |

## 7. Decisions this plan makes

- **The card shows ITG-standard numbers, not the app engine's.** The app's
  [parity.dart](../../lib/models/parity.dart) is deliberately retuned for DDR (bracket
  surcharge, same-panel penalty, sideswitch 50, spin 3000), so its counts can't match
  the sheet. Keep it for the preview's footing and personal style. Label the card's
  numbers as the shared standard, so they're comparable with Simply Love and the
  spreadsheet.
- **Compute offline in prep, ship results.** The graph search is too slow to run on
  every song page, and the numbers never change per user. Only phase 6 runs on
  device, and only for one chart at a time.
- **No NPS or stream.** Stream notation, stream % and notes/second are ITG
  vocabulary; DDR players read a chart by its patterns, so the card and the
  preview show only those (§5.1 and the stream/NPS parts of phase 5 are dropped).
- **Count every occurrence, even "either works" ones.** Matching the reference wins.
  Ambiguity is shown, not subtracted.
- **Where a count overlaps the cabinet's own, use the cabinet's rule**
  (per the arcade reference kept locally): a jump is one
  step, a jump-freeze is one freeze, and shock rows are neither steps nor jumps. In
  Doubles a shock can cover one pad only. When comparing against cabinet note
  positions, snap to 1/48 beat, because cabinet triplets sit a hair off the exact third.

## 8. Sources

- ITGmania v1.0.0 release notes ("Tech Analysis") — <https://github.com/itgmania/itgmania/releases/tag/v1.0.0>
- `src/StepParityGenerator.cpp`, `StepParityCost.{h,cpp}`, `StepParityDatastructs.{h,cpp}`, `TechCounts.cpp`, `MeasureInfo.cpp` at tag `v1.0.0`
- Simply Love `Scripts/SL-ChartParserHelpers.lua` (`GetStreamSequences`, `GetTotalStreamAndBreakMeasures`)
- M. Votaw, "Predicting Foot Placement for 4-Panel Dance Games" — <https://mjvotaw.github.io/posts/step-annotation/step-annotations/>
- itgmania discussion #726 (spreadsheet provenance; the author's notes on reliability, doubles, turniness and forced doublesteps) — <https://github.com/itgmania/itgmania/discussions/726>
- Not reviewed here, but cited in #726 for turniness: B. Blum's ITG chart-analysis papers (`contrib.andrew.cmu.edu/~bblum/itg*.pdf`)
