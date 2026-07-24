# What Landpaddle's chart scripts add to the SMEditor port

A companion to [ANALYSIS.md](./ANALYSIS.md). That doc argues for porting SMEditor's
parity engine (heel/toe feet + physical pad geometry + a cost-model shortest-path
DP) to replace the greedy `FootAssigner`. **This doc does not revisit that decision.**
The SMEditor port stays the plan — it is the stronger *foot-assignment* engine
because it has lookahead and real geometry.

This doc studies a *different* set of scripts — the "Chart spreadsheet project"
analyzers by **Landpaddle** — and asks one question: **is there anything in them
that would make the SMEditor port better?** The answer is yes: a handful of
signals and framings that compose *on top of* the cost-model engine rather than
competing with it.

---

## 1. What the Landpaddle scripts are

Bulk analyzers that walk a Songs folder and emit spreadsheet-feeding JSON. The
parity-relevant ones:

| Script | What it does |
|---|---|
| `Chart Analyzer (Crossover Version)` | Foot/facing/turn state machine that always crosses over & spins |
| `Chart Analyzer (Doublestep Version)` | Same machine, but prioritizes facing forward: candle → doublestep instead of crossing |
| `Chart Analyzer (Hybrid Version)` | Crosses normally, but doublesteps to avoid 270° spins, then reorients |
| `Ambiguity Finder` | Finds patterns where the entry foot is genuinely undetermined; classifies them "okay" vs "bad" |

### The one modelling idea that differs from SMEditor

**Landpaddle makes the player's *facing direction* the primary state; SMEditor
derives facing after the fact.**

- SMEditor picks feet by minimizing a cost vector, then facing falls out of
  `getPlayerAngle` = `atan2` of the vector between the two foot positions.
- Landpaddle tracks one of 8 facings (`N NE E SE S SW W NW`) as first-class state
  and resolves each note through a hand-written `(Direction × LastNote × Holds)`
  transition table that outputs the new facing, the foot, and **how far you
  turned** (`Turn0/1/2/3` = 0°/45°/90°/135°).

The transition table itself is ~1400 lines of brittle `if/elif` and is **not**
worth porting — SMEditor's ~250-line geometry+cost core subsumes it. But three
*outputs / framings* of that machine are worth lifting.

---

## 2. Signal A — turn-magnitude counters (cheap "twistiness" stat)

Landpaddle counts, per chart, `TurnL1/L2/L3` and `TurnR1/R2/R3` (45°/90°/135°
turns, left and right). That's a **per-chart rotation/twist metric** and a
**per-note turn magnitude** — something neither the current preview nor the
planned port surfaces.

**Why it composes with the port instead of competing:** once SMEditor's
`StageLayout.getPlayerAngle(leftPos, rightPos)` is ported, you already have the
facing angle at every row *for free*. The turn magnitude is just the delta:

```
turnDegrees[i] = angleDiff( getPlayerAngle(state[i]), getPlayerAngle(state[i-1]) )
```

Bucket that delta into 0/45/90/135 and sign it L/R and you've reproduced
Landpaddle's entire turn-counting output as a ~10-line post-pass over the DP's
best path — no separate engine, no separate state.

**What it buys the app:**
- A chart-level "rotation / twist" number for the preview header, distinct from
  crossover *count* (a chart can have many gentle 45° turns or few violent 135°
  ones — very different to dance, same crossover count).
- An optional per-note turn badge / facing-timeline strip, matching SMEditor's own
  "Facing Timeline" feature ([parity-guide.md](./parity-guide.md#L59)) but derived
  from data you'll already be computing.

**Effort:** tiny. Post-pass over `computeBestPath` output. Do this one first.

---

## 3. Signal B — the crossover-vs-doublestep fork is a *preference*, not a fact

Landpaddle shipped **three** engines for the same charts because the same
ambiguous pattern has three defensible foot readings:

- **Crossover** — always cross/spin, even into awkward backward-facing.
- **Doublestep** — prefer to stay facing forward: candle first, then doublestep,
  avoid crossing.
- **Hybrid** — cross normally, but doublestep to avoid 270° spins, then doublestep
  again to reorient.

SMEditor bakes exactly *one* of these into its weights (`DOUBLESTEP 750` >
crossover's `FACING` cost, so it crosses). That's a fine default — but it's a
**tuning choice, not ground truth**, and Landpaddle is the evidence that real
players disagree.

**Why this composes with the port:** you don't ship three engines. The three
philosophies map directly onto the SMEditor weights you're already porting:

| Philosophy | Weight change on the ported cost model |
|---|---|
| Crossover (SMEditor default) | as-is: `DOUBLESTEP` high, `FACING` cheap |
| Doublestep / face-forward | lower `DOUBLESTEP`, raise `FACING`/`SPIN` so the DP prefers stepping twice over turning the body |
| Hybrid | keep `DOUBLESTEP` moderate, raise `SPIN` hard so only *spins* get doublestepped away |

So it becomes a **preview toggle ("reading style: crossover / face-forward /
hybrid")** backed by three weight presets over the *same* DP. This is strictly a
win the port enables and the current greedy solver cannot — greedy can't honor a
"prefer doublestep globally" preference because it has no path-level view.

**Bonus — categorize *why* a doublestep happened.** Landpaddle's doublestep engine
splits its doublestep counter into `DoubleSteps0/1/2/3` (avoid-crossover /
avoid-facing-S / avoid-S-candle / true-spin-avoidance). If you show doublestep
counts in the preview, the DP already knows which competing cost term it dodged —
you can label them the same way for a much more informative tech readout than a
bare "3 doublesteps".

**Effort:** low-moderate. Three weight presets + a toggle. Only meaningful *after*
the port lands.

---

## 4. Signal C — detect ambiguity and stop presenting guesses as facts

The **Ambiguity Finder** targets exactly the class of pattern your greedy solver
gets wrong and the SMEditor port *silently resolves*: sections where the entry
foot is genuinely undetermined — `D1U1` jumps, or D↔U steps out of a neutral pose.
It does **forward lookahead** and classifies each:

- **"okay"** — no way of turning into the section costs you anything later, so
  either foot is fine.
- **"bad"** — there *is* an optimal entry, and a naive/greedy read that guesses
  wrong pays for it downstream (awkward motion).

**Why this matters even with a perfect cost DP:** the DP always returns *a* path.
When two paths tie (or nearly tie), it picks one and renders a confident foot
badge — but that's precisely the "okay ambiguity" case where the badge is a coin
flip. SMEditor's own guide admits the checker is sometimes wrong and offers manual
overrides ([parity-guide.md](./parity-guide.md#L84-L92)); this is the principled
way to *detect* those spots automatically instead of waiting for the user to
notice.

**Two ways it composes with the port — both cheap because the DP already has the data:**

1. **Tie/near-tie detection = "okay" ambiguity.** During `computeBestPath` you
   keep `cachedLowestCost` per node. If the best and second-best incoming paths to
   a row are within an epsilon, flag that row **ambiguous**. Render its foot badge
   in a muted/dashed style: "this is a guess, either foot works." Directly
   reproduces Landpaddle's "okay" class from data the DP computes anyway.
2. **Clear-winner-but-fragile = "bad" ambiguity.** Where one entry is clearly
   cheaper *because of notes several rows later*, that's a spot a human reading
   locally would get wrong — worth a subtle "reads better entered with the X foot"
   hint. This is Landpaddle's "bad" class and it's the strongest argument the
   scripts make for *why* lookahead matters, restated as a UI affordance.

**Deterministic tie-breaks as a fallback.** Landpaddle also documents concrete
conventions for permanent ambiguity so a facing solver never oscillates: ambiguous
`D1U1` → left foot forward / right back; lone ambiguous `U1` → left; lone ambiguous
`D1` → right back. Even with a cost DP, an epsilon-tie needs a stable tie-break for
reproducible rendering — these are sensible defaults to break ties by rather than
"whatever the DP visited first."

**Effort:** low. Both flags are a comparison against `cachedLowestCost` values the
DP already stores. The muted-badge render is a `_paintFootBadge` variant.

---

## 5. Limitations — why this is "signals," not "a second port"

Being clear about what *not* to take:

- **The three analyzers have no lookahead** (stated in every header). Their foot
  assignment is history-only — the same structural weakness ANALYSIS.md pins on
  the greedy solver. Only the Ambiguity Finder looks ahead. So the *foot
  assignment* stays SMEditor's job; we're lifting metrics and framings, not the
  solver.
- **The analyzers explicitly ignore footswitches, sideswitches, and mines.**
  SMEditor's `calcSlowFootswitchCost` etc. remain the reason to port it.
- **Single-pad only** (`dance-single`) for the analyzers; doubles live in a
  separate classifier.
- **The transition table is brittle** hand-written branching, not a general model.
  Porting it wholesale would regress against the geometry core.

---

## 6. Bottom line — three additive improvements to the port

None of these change the plan to port SMEditor. All three ride on top of it and
use data the DP already produces:

1. **Turn-magnitude signal (do first, trivial):** post-pass over `getPlayerAngle`
   deltas → a chart "twist" stat + optional per-note turn badge / facing timeline.
2. **Reading-style toggle (after port):** three weight presets (crossover /
   face-forward / hybrid) over the same cost DP, exposed as a preview option —
   because the crossover-vs-doublestep call is a player preference, not a fact.
   Optionally categorize *why* each doublestep happened.
3. **Ambiguity/confidence overlay (after port, cheap):** flag rows where the best
   and second-best DP paths tie ("okay" — muted badge, either foot) vs. where the
   winner depends on far-future notes ("bad" — subtle better-foot hint). Stops the
   preview from rendering coin-flip guesses as confident facts, and directly
   addresses the "known incorrect situations" in the SMEditor guide.
