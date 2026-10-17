# Dancer form reference

How the dancers (flat dancing feet and the 3D pad dancer) should place and move
the feet. The source is CHRS4LFE (chris4life)'s 4-panel form guide,
<https://iamchris4life.com/formguide/>. It is the reference for MINIMAL form, and
foot placement in every form follows its contact rules. Read the guide itself
before changing placement. This page is a condensed paraphrase plus what the
code does with each rule. The shock dodges follow a separate post by the same
author, already built into `parity_shocks.dart`.

Don't guess at foot placement or body motion. If a rule here doesn't cover a
case, look it up in the guide or ask; record the answer here.

## Rules, condensed

**Contact and stance**
- Flat-footed by default, heel on the pad. Up is landed with the toes slightly
  down, Down with the heel slightly down.
- Feet and body face forward. Don't re-angle the feet per pattern; only
  crossovers, brackets and scoobies turn them. Angled feet fat-foot neighbours.
- Stay inside the inner part of each panel. Hit the inner corners of Up and
  Down, so each foot's Left/Right–Up–Down triangle is as small as possible.
- Keep each foot down as long as possible, lift it as little as possible,
  minimise airtime. Step lightly and push down, not sideways.
- No winding: never step outward early for the next arrow. Repeated hits on
  one arrow land in the same spot.
- Keep step sizes and foot rotation even across a run (RDUDL: right foot 0° on
  Right, ~22.5° on Up's inner centre, 45° on Left).

**Crossovers** (Down-side) **and crossunders** (Up-side)
- Feet turn at most 45°.
- The anchor foot sits toward the crossing side, heel-weighted on Down for a
  crossover, toe-weighted on Up for a crossunder.
- The crossing foot takes Left/Right's inner top corner for a crossover, inner
  bottom corner for a crossunder; if it also hits Up/Down in the run (LDUDR),
  it takes the inner centre instead.
- No anticipation turning: LDLDLDR stays square until the final LDR.

**Scoobies**: about 45°, then just under 90° in scooby position (left foot on
Right, right foot on Left), then 45°, then square again. No single move turns a
foot more than 90°. Judge by the feet, not the body.

**Brackets**: about 20°, not 45°. Toes toward Up's inner corner for UL/UR, heel
toward Down's inner corner for DL/DR. Toe slightly down so the toe arrow lands
first. A slightly wider stance helps in bracket-heavy runs; square up after.

**Footswitches**: no lifting. Spring off the arrow over the centre panel with
the ankle (toes up off Up, heel up off Down); fast ones use the first hit's
impact, slow ones spring just before the second.

**Sideswitches**: a footswitch on Left/Right with the feet crossed. The
same-side foot anchors over the 45° corner bracket, weighted toward the arrow,
unless Up/Down comes next, then it sits on the corner metal at a smaller angle.

**Jacks**: bounce back onto the same arrow; fast pairs as one strike and
rebound. **Doublesteps**: the bounce carries the foot to the next arrow, the
other foot stays planted. **Step-jumps**: a jack or doublestep with a jump,
minimal airtime.

**Not covered by the guide**: shoulders and upper body (beyond facing forward),
the bar, freezes. Shocks are in the separate post.

## In the code

| Rule | Where | Status |
| --- | --- | --- |
| Inner corners of Up/Down, inner edges of L/R (MINIMAL) | `formSpot` in `dancing_feet.dart` | done |
| Crossing foot on L/R inner top/bottom corner, inner centre of Up/Down | `formSpot` | done |
| Up on the toes, Down on the heel, L/R flat: that half of the shoe on the spot | `_pose` (`_FootAt.weight`) in `pad_dancer.dart` | done |
| Crossovers ≤45°, scooby just under 90° | `turnFor` / `stepTurn` | done (90° cap) |
| No anticipation turning | `stepTurn` (turns only on the crossing step) | done |
| Low lift, short airtime (MINIMAL) | `_Style` lift/air | done |
| Brackets at ~20° | bracket heading is heel→toe panel line (45° on corners) | not yet |
| Up landed toe-down, Down heel-down | `tilt` only dips the toe in the air | not yet |
| Footswitch spring without lifting | footswitch is an ordinary step | not yet |
| Anchor foot shifted toward the crossing side | anchor stays on its spot | not yet |
| Shoulders and hips | `_Style` torso turn/follow are tuned by eye, no source | unsourced |
