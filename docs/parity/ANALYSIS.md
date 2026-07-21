# Parity deep-dive: why crossovers & footswitches misfire, and how SMEditor solves it

This is a study of your current `FootAssigner` ([steps_model.dart:149](../../lib/models/steps_model.dart#L149))
against SMEditor's parity engine (files downloaded to this folder). The goal: understand *why*
crossovers and footswitches come out wrong, and what a port would need.

---

## 1. The root cause in one sentence

**Your solver is greedy and column-based; crossovers and footswitches are only
identifiable with lookahead over a physical model of the pad.** Those two facts
are the whole story. Everything below unpacks them.

---

## 2. Where your current solver breaks

### 2a. It commits per-note with no lookahead

`FootAssigner.assign` walks groups in time order and, at each group, picks the
locally cheapest foot (`_chooseSingle` / `_pickGroup`), then **commits it
permanently** and moves on ([steps_model.dart:209-229](../../lib/models/steps_model.dart#L209-L229)).

A crossover is *defined by what comes after it*. Consider `L D L R` (columns 0,1,0,3)
as a fast run. The correct reading is often L-R-L-R, where the 2nd note (Down)
is hit by the **right** foot crossed over the body, because the run continues to
the right. But at the moment you reach the Down arrow, greedy scoring sees "right
foot is far, left foot is close" and keeps the left foot home — killing the
crossover before it starts. You literally cannot know the Down was a crossover
until you see the notes after it resolve to the right. **No amount of weight
tuning fixes a greedy solver here** — the information needed isn't available yet
at decision time.

Footswitches are worse: a footswitch is *the same column hit by alternating feet*
(`L L` on one arrow, danced R-then-L). Your `_reusePenalty` and `_sameFootBonus`
actively push *against* switching feet on a repeated column — they'll pick a jack
(same foot twice) because that scores lower locally, which is exactly the wrong
call when the surrounding flow demands a switch.

### 2b. It has no physical model of the pad

Your state is two integers: `leftCol`, `rightCol` ([steps_model.dart:164-165](../../lib/models/steps_model.dart#L164-L165)).
A "crossover" is inferred by a fuzzy `col >= rightCol` heuristic (`_crossSideBonus`).
But "crossed over" is a *geometric* fact: the right foot is physically to the
**left** of the left foot. Column index can't express that — column 0 (Left) and
column 3 (Right) are just numbers; the engine has no idea they're on opposite
sides of the body, or that hitting Up (col 2) while your other foot is on Left
(col 0) requires a body rotation. Facing direction, spins, and "twisted foot"
are all invisible to you.

### 2c. Feet are atomic — no heel/toe

Your `Foot` enum is `{left, right}`. There is no way to represent a **bracket**
(one foot on two arrows) because that needs the foot split into heel + toe. Your
`_pickGroup` treats a jump as "two arrows, ideally one foot each" and can never
say "the left foot covers both of these."

---

## 3. How SMEditor models it (the four extractable files)

The author explicitly wrote `ParityInternals`, `ParityDataTypes`, `ParityCost`,
and `StageLayouts` to be DOM-free and portable. Here's the architecture.

### 3a. Feet have parts (`ParityDataTypes.ts:3`)

```
enum Foot { NONE, LEFT_HEEL, LEFT_TOE, RIGHT_HEEL, RIGHT_TOE }
```

Four "feet". A single step uses a heel; a bracket uses heel+toe of the same side.
`OTHER_PART_OF_FOOT` maps heel<->toe so cost functions can ask "is this the same
physical foot?" cheaply. This is what makes brackets first-class.

### 3b. The pad is physical geometry (`StageLayouts.ts:214`)

Each column is a point with `{x, y, rotation}`:

```
dance-single: Left(-1,0)  Down(0,-1)  Up(0,1)  Right(1,0)
```

From this the engine derives **real quantities**:
- `getPlayerAngle(left, right)` — the body's rotation via `atan2` of the vector
  between the feet. This is the crossover/spin detector.
- `bracketCheck(a,b)` — two columns are bracketable iff squared distance ≤ 2
  (adjacent, not across the pad).
- `averagePoint` — a foot's position (heel/toe midpoint) as a real coordinate.
- `sideArrows = [0,3]` — Left/Right are the "side" panels (footswitch vs sideswitch).

Crossed-over is now a *fact*, not a heuristic: `rightPos.x < leftPos.x`
(`ParityCost.ts:276`). The right foot is literally left of the left foot.

### 3c. A weighted cost model (`ParityDataTypes.ts:67`)

Every transition between two states is scored by ~18 named penalties:

```
DOUBLESTEP 750   FOOTSWITCH 325   MISSED_FOOTSWITCH 500   SIDESWITCH 130
JACK 40          BRACKETJACK 60   SLOW_BRACKET 300        BRACKETTAP 400
FACING 3         DISTANCE 6       SPIN 3000               TWISTED_FOOT 100000
XO_BR 200        HOLDSWITCH 55    MINE 10000              START_XO 10000
```

Read these as a *priority order*. TWISTED_FOOT (100000) means "physically
impossible, never do this." DOUBLESTEP (750) is heavily discouraged, so the solver
will happily choose a **crossover** (which only costs some FACING) over stepping
twice with one foot. That's the crux: **crossovers emerge because they're cheaper
than the alternatives**, not because a rule says "insert crossover here."

Key cost functions that produce the tech you care about:

- **Crossovers** — `calcFacingCost` (`ParityCost.ts:370`). Facing backward
  (heel vector pointing `-x`) costs `(-heelFacing)^7.2 * 200 * FACING`. The power
  of 7.2 means small turns are nearly free but deep crossovers ramp up sharply —
  yet still far cheaper than a doublestep, so the solver picks the crossover.
- **Footswitches** — `calcSlowFootswitchCost` (`ParityCost.ts:422`). A footswitch
  itself is *free* when fast (≤ 0.2s ≈ 8th @150bpm); only *slow* ones get penalized,
  scaled by how slow. So the solver naturally alternates feet on a repeated arrow
  in a stream. Contrast your solver, which penalizes exactly this.
- **Doublestep** — `calcDoublestepCost` (`ParityCost.ts:286`). Same foot on two
  *different* consecutive arrows = 750, unless a hold/mine "allows" it. This is the
  pressure that forces feet to alternate and thus produces crossovers/switches.
- **Jacks** — `calcJackCost`. Same foot, *same* arrow, penalized only when fast.
- **Spins** — `calcSpinCost` (`ParityCost.ts:387`). Crossing the 180° facing line
  while the front foot changes = 3000. Distinguishes a legal crossover from an
  illegal full spin.
- **Distance** — `calcDistanceCost`. Moving a foot far in little time costs
  `dist * 6 / elapsedTime`. This is what makes fast runs prefer nearby feet.

### 3d. The solver is a shortest-path over a state graph (`ParityInternals.ts`)

This is the part that beats greedy. It's a layered DAG + Dijkstra/DP:

1. **Rows** (`recalculateRows`) — collapse notes at the same timestamp into a
   `Row` (notes, holds, holdTails, mines).
2. **States/nodes** (`recalculateStates` + `generateActions`, line 772) — for each
   row, enumerate *every legal foot assignment* (permutation of the 4 feet onto the
   active columns), pruned by `bracketCheck` (no impossible brackets) and heel/toe
   validity. Each permutation applied to a parent state yields a child `ParityState`
   node. So a row with 2 notes might have a dozen candidate nodes.
3. **Edges** (`computeCosts`) — every parent→child transition gets its full cost
   vector via `getActionCost`.
4. **Best path** (`computeBestPath`, line 630) — a forward DP: for each node keep
   the lowest cumulative cost to reach it (`cachedLowestCost`), sweeping row by row
   to a virtual end node. The min-cost path back is the parity assignment.

Because it minimizes cost *over the whole path*, the Down-arrow-as-crossover
decision is made correctly: the path where Down = right-foot-crossed has a lower
**total** cost (it avoids a later doublestep), even though that node looked
locally worse. **This is precisely the lookahead your greedy solver lacks.**

The rest of `ParityInternals` (caching edges, pruning, incremental recompute over
a beat range, the web-worker `onmessage`) is performance scaffolding for a live
editor. **A batch port for your read-only chart preview can drop almost all of it**
— you compute once per chart, so no incremental caching, no worker, no dirty-range
tracking. That collapses the 1200-line file to maybe 150 lines of core DP.

---

## 4. What a Dart port looks like (scoped to your app)

You render a static preview; you don't edit. So you want the *analyzer*, not the
live engine. Minimum viable port:

| SMEditor piece | Port? | Notes |
|---|---|---|
| `Foot` (5-value heel/toe enum) | **Yes** | Replaces your `{left,right}`. Renderer maps HEEL/TOE→L/R for the badge; brackets get the lighter shade. |
| `StageLayout` (single + double) | **Yes** | ~30 lines of coordinate tables + `getPlayerAngle`/`bracketCheck`/`averagePoint`. |
| `ParityState` + `getPlacementData` | **Yes** | The per-transition derived facts (jumped, jack, doublestep, brackets, positions). |
| `ParityCostCalculator` | **Yes** | Port the ~15 cost fns. Weights become tunable constants like your existing `_sameFootBonus` block. |
| `generateActions` (permutations) | **Yes** | Small recursive enumerator. |
| DP best-path | **Yes, simplified** | One forward sweep, `Map<nodeKey,cost>`. Drop all caching/pruning/worker code. |
| `recalculateRows` incremental logic | **No** | Compute once. Just group notes by second into rows. |
| Edge/lowest-cost caches, `deleteCache`, worker | **No** | Live-edit only. |
| `RowStatCalculator`, `ParityDebug` | **Optional** | Only if you want the "3 crossovers, 2 footswitches" tech counts shown in your UI. |

Integration point: `chart_scroller.dart:250` calls `FootAssigner.assign(...)`.
Keep that exact signature — return a `Map<StepNote, Foot>` where `Foot` is the new
heel/toe enum (or fold heel/toe to L/R at the boundary if you don't render brackets
yet). `_paintFootBadge` at `chart_scroller.dart:1061` already switches on L/R; it
just needs a toe/bracket variant.

### Complexity note
Permutations per row are tiny (≤ 4 columns in single, ≤ 8 in double), so nodes per
row stay small. Total work is `O(rows × nodes² )` for edges — fine for a batch
pass over one chart. Double (8 panels) is the only place to watch: prune
aggressively with `bracketCheck` and skip obviously-dead nodes.

---

## 5. Suggested reading order of the downloaded files

1. `ParityDataTypes.ts` — vocabulary (Foot parts, weights, ParityState, Row).
2. `StageLayouts.ts` — the pad geometry + the geometric helper methods.
3. `ParityCost.ts` — the cost functions = the actual "footwork rules."
4. `ParityInternals.ts` — the graph/DP (skim the caching; focus on
   `generateActions`, `initResultState`, `computeBestPath`).
5. `RowStatCalculator.ts` — only if you want tech-count labels.

---

## 6. Bottom line

Your crossovers/footswitches fail for two structural reasons, not tuning:
1. **Greedy, no lookahead** — the decision is made before the disambiguating
   notes are seen. → Needs the shortest-path DP.
2. **No physical pad model, atomic feet** — "crossed over," "facing," "bracket,"
   "footswitch vs jack" aren't even representable. → Needs the heel/toe enum +
   `StageLayout` geometry + the cost model.

The good news: SMEditor's author isolated exactly the four files you need, they're
pure logic, and for a read-only preview you can drop ~80% of `ParityInternals`
(all the incremental/caching/worker machinery). The port is real work but
well-bounded — call it the geometry+cost model (~250 lines) plus a ~150-line
batch DP replacing `FootAssigner`.
