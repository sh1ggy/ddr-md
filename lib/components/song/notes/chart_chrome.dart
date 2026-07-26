/// Name: Chart preview chrome
/// Parent: ChartScroller
/// Description: The preview's stateless UI furniture — tempo badge, speed and
/// control panes, the settings shade and its chips/tiles, and the edge tabs.
/// Split out of chart_scroller.dart: each takes its values and callbacks
/// through the constructor, so none of them reach into scroller state.
library;

import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/material.dart';

class TempoBadge extends StatelessWidget {
  const TempoBadge({
    super.key,
    required this.bpm,
    required this.readSpeed,
    this.syncLabel,
    this.syncAccent,
  });

  final int bpm;
  final int readSpeed;

  /// The song's effective sync, in the SAME terms as the ARCADE SYNC caption
  /// (e.g. "FAST 9.0ms" / "ON BEAT") so the two readouts always agree. Null
  /// hides the segment entirely — a song with no sync data has nothing to say
  /// here, and an empty slot would just be noise over the field.
  final String? syncLabel;

  /// FAST/SLOW hue for [syncLabel], or null for the badge's plain white.
  final Color? syncAccent;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, {Color? valueColor}) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: valueColor ?? Colors.white.withValues(alpha: 0.92),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    Widget divider() => Container(
          width: 1,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: Colors.white.withValues(alpha: 0.22),
        );
    return Container(
      // Stable handle so tests can read THIS badge's numbers rather than
      // matching bare text that the transport pane also shows.
      key: tempoBadgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stat("BPM", "$bpm"),
          divider(),
          stat("READ", "$readSpeed"),
          if (syncLabel != null) ...[
            divider(),
            stat("SYNC", syncLabel!, valueColor: syncAccent),
          ],
        ],
      ),
    );
  }
}

/// Left half of the control row: the DDR WORLD speed option. Shows the
/// active SPEED TYPE — REAL SPEED (the cabinet's ScrollSpeed: the dialled
/// target scroll rate) or HI-SPEED (the raw multiplier, printed "x %.2lf" as
/// the cabinet does) — with the resulting min–core–max read speeds under
/// either, like the cabinet's num_min/num_core/num_max readouts.
/// Tap to switch type; drag or tap the ∓ ends to turn the active dial —
/// buttons and drag share one detent (x0.05 for HI-SPEED, 10 for REAL
/// SPEED), and each type keeps its own dialled value.
class SpeedPane extends StatelessWidget {
  const SpeedPane({
    super.key,
    required this.label,
    required this.value,
    required this.range,
    required this.decLabel,
    required this.incLabel,
    required this.canDecrement,
    required this.canIncrement,
    required this.onStep,
    required this.onDrag,
    required this.onToggleType,
  });

  final String label;
  final String value;

  /// The min–core–max scroll speeds for the current multiplier, preformatted
  /// as "min–core–max" (matching the cabinet's num_min/num_core/num_max),
  /// folded to a single number only when all three coincide (true constant
  /// BPM). Null hides the row — used for a constant-BPM chart under REAL
  /// SPEED, whose folded number merely repeats the dialled read speed above.
  final String? range;
  final String decLabel;
  final String incLabel;
  final bool canDecrement;
  final bool canIncrement;
  final void Function(int dir) onStep;
  final void Function(double dx) onDrag;
  final VoidCallback onToggleType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = range;
    return ControlPane(
      onTap: onToggleType,
      onDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
      child: Row(
        children: [
          EdgeButton(
            label: decLabel,
            enabled: canDecrement,
            onTap: () => onStep(-1),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.0,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                // The BPM-change min–core–max range (cabinet
                // num_min/num_core/num_max) sits on its own line UNDER the
                // value, not beside it: on wide-range charts "150–300–602" is
                // wider than the big number, and baseline-aligned alongside it
                // collided with the value and crowded the ∓ edge buttons.
                // Stacking keeps the value centred and gives the range its own
                // uncramped row.
                if (r != null)
                  Text(
                    r,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.0,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          EdgeButton(
            label: incLabel,
            enabled: canIncrement,
            onTap: () => onStep(1),
          ),
        ],
      ),
    );
  }
}

/// Right half of the control row: playback speed (how fast the chart plays in
/// real time). Drag horizontally to speed up / slow down; tap to reset to 1.0×.
class SongSpeedPane extends StatelessWidget {
  const SongSpeedPane({
    super.key,
    required this.rate,
    required this.onDrag,
    required this.onReset,
  });

  final double rate;
  final void Function(double dx) onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ControlPane(
      onTap: onReset,
      onDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "SONG SPEED",
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          Text(
            "${rate.toStringAsFixed(2)}×",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared framing for the two control panes: a rounded, tappable/draggable
/// surface with a horizontal-drag gesture and a subtle grab cursor.
class ControlPane extends StatelessWidget {
  const ControlPane({
    super.key,
    required this.child,
    required this.onDragUpdate,
    this.onTap,
    this.borderRadius = 10,
    this.fill,
  });

  final Widget child;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback? onTap;

  /// Corner rounding. Defaults to the preview chrome's 10; the song page
  /// passes Material's card radius so its pane matches the cards it sits among.
  final double borderRadius;

  /// Pane fill. Defaults to the preview chrome's raised tint, which reads as a
  /// control against the dark field. Pass [Colors.transparent] when the pane
  /// already sits on a surface that supplies its own colour (the song page's
  /// Card), so it doesn't tint itself lighter than its neighbours.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragUpdate: onDragUpdate,
        child: Container(
          decoration: BoxDecoration(
            color: fill ?? scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One group of modifier controls inside the settings shade. [content] is the
/// section's laid-out body (tiles/rows). Sections carry no caption — the
/// controls read on their own.
class ShadeSection {
  final Widget? content;
  const ShadeSection({
    this.content,
  });
}

/// The pull-down options card: a rounded panel of chart-viewing modifiers that
/// floats inset from the screen edges (never a full-width sheet — it must not
/// dominate the field). Styled like the bottom transport — same padding, fill
/// and radius, with filled tiles inside matching the read/song-speed panes — so
/// the two chrome surfaces read as one family. Height-capped with a scrollable
/// body for when the option set outgrows the cap. Its top is positioned by the
/// caller ([_buildSettingsShade]) so it seats under the title when the header is
/// up, or at the status bar when it isn't.
class SettingsShade extends StatelessWidget {
  const SettingsShade({
    super.key,
    required this.sections,
  });

  final List<ShadeSection> sections;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Inset from the screen edges so the card doesn't span the full width —
      // matching how the transport floats above the bottom edge.
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        // Same framing as the bottom transport ([_buildTransport]) so the top
        // and bottom chrome read as one surface: identical padding, fill and
        // corner radius. The solidity comes from the filled tiles inside (like
        // the transport's read/song-speed panes), not the thin outer wash.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: BoxConstraints(maxHeight: media.size.height * 0.4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        // No close button — the left-edge pull-tab dismisses the card.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < sections.length; i++)
                      if (sections[i].content != null)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                          child: sections[i].content!,
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fill/border/foreground for a shade control, keyed on whether it's active.
/// The inactive state deliberately matches the read/song-speed panes
/// ([ControlPane]: `surfaceContainerHighest` at α 0.5, no border) so the shade
/// tiles read as the same buttons as the bottom config. The active state lifts
/// the same surface brighter with a hairline border to mark the selection —
/// still monochrome, never a purple accent.
({Color fill, Color border, Color fg, Color fgMuted}) _tileColors(
    ColorScheme scheme, bool active) {
  final onSurface = scheme.onSurface;
  final surface = scheme.surfaceContainerHighest;
  return active
      ? (
          fill: surface.withValues(alpha: 0.9),
          border: onSurface.withValues(alpha: 0.45),
          fg: onSurface,
          fgMuted: onSurface.withValues(alpha: 0.7),
        )
      : (
          fill: surface.withValues(alpha: 0.5),
          border: Colors.transparent,
          fg: onSurface.withValues(alpha: 0.85),
          fgMuted: onSurface.withValues(alpha: 0.55),
        );
}

/// The accent for a dial value: the FAST hue for positive, the SLOW hue for
/// negative, null at neutral (which stays the shade's plain grey). Uses the
/// app's existing sync FAST/SLOW palette ([kFastColor]/[kSlowColor], shared with
/// the song page's sync card) so the same two colours mean the same two things
/// everywhere in the app.
Color? timingAccent(double value, bool isDark) {
  if (value == 0) return null;
  return value > 0
      ? constants.kFastColor(isDark)
      : constants.kSlowColor(isDark);
}

/// The CONSTANT-modifier tile: the full-width top row of the ARROWS section.
/// Tap toggles the modifier on/off (no separate switch); dragging horizontally
/// sweeps the display time. Styled neutrally like the rest of the shade — when
/// on it reads a touch brighter and shows the current ms, off it reads "OFF".
class ConstantChip extends StatelessWidget {
  const ConstantChip({
    super.key,
    required this.on,
    required this.ms,
    required this.equivalentReadSpeed,
    required this.onTap,
    required this.onDrag,
  });

  final bool on;
  final double ms;

  /// The read speed the chart effectively READS at with this window at the
  /// current scroll: the faster of the dialled read speed and the window's
  /// equivalent, so it tracks the live speed type/multiplier rather than being
  /// a fixed property of the window. Null when off; shown muted next to ms.
  final int? equivalentReadSpeed;

  final VoidCallback onTap;
  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _tileColors(scheme, on);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
        child: Container(
          width: double.infinity,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border, width: 1),
          ),
          child: Row(
            children: [
              // CONSTANT = a fixed arrow display *time*, so a stopwatch reads
              // the concept better than a generic clock. DDR World has no
              // CONSTANT glyph (it's not one of the option-icon categories), so
              // the closest conceptual Material icon stands in here.
              Icon(Icons.timer_outlined, size: 16, color: c.fgMuted),
              const SizedBox(width: 8),
              Text(
                "CONSTANT",
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: c.fgMuted,
                ),
              ),
              const Spacer(),
              if (on && equivalentReadSpeed != null) ...[
                Text(
                  "≈ C$equivalentReadSpeed",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.fgMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                on ? "${ms.round()}ms" : "OFF",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: c.fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Identifies the tempo badge for tests reading its BPM/READ values.
const Key tempoBadgeKey = Key('chart-preview-tempo-badge');

/// Identifies the settings shade's pull-tab. The shade is slid off-screen and
/// pointer-ignoring while closed, so tests must open it before driving anything
/// inside.
const Key shadeTabKey = Key('chart-preview-shade-tab');

/// Identifies the ARCADE SYNC tile and its two offset chips, for tests driving
/// their tap/drag.
const Key arcadeSyncTileKey = Key('chart-preview-arcade-sync');
const Key visualOffsetChipKey = Key('chart-preview-visual-offset');
const Key audioOffsetChipKey = Key('chart-preview-audio-offset');

/// Resolves a stored VISUAL OFFSET through the ARCADE SYNC gate exactly as the
/// live state does, in seconds. Returns 0 whenever the gate is off, whatever is
/// stored — the gate is not merely a UI affordance, it decides whether the field
/// moves at all.
///
/// Exposed because the field painter can't be observed in a widget test: the
/// scroller paints nothing until [SpriteNoteskin.tryLoad] resolves, and that
/// future never completes under the test harness.
@visibleForTesting
/// One TIMING offset chip (VISUAL or AUDIO) in the shade's TIMING section.
/// Drag horizontally to sweep the offset, tap to reset it to neutral — the same
/// interaction as [ConstantChip], minus an on/off state: an offset of +0.0 IS
/// the off state, so the chip reads "non-neutral" rather than "on".
class TimingOffsetChip extends StatelessWidget {
  const TimingOffsetChip({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.valueLabel,
    required this.onTap,
    required this.onDrag,
  });

  final String label;
  final IconData icon;

  /// The raw offset. Only its sign and zero-ness are used here (for the
  /// highlight and the hint) — the two dials carry different units, so the
  /// formatted text comes in via [valueLabel] rather than being built here.
  final double value;

  /// Preformatted display text for [value], e.g. "+1.5" or "-10ms".
  final String valueLabel;

  final VoidCallback onTap;
  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Deliberately NOT accent-coloured: the two chips sit side by side, and
    // tinting both turned the row into competing blocks of colour. The FAST/SLOW
    // hue lives on the ARCADE SYNC summary above instead, where one label reads
    // the state for both dials. A dialled chip still brightens (via the active
    // tile colours) so it's visible which ones are engaged.
    final c = _tileColors(scheme, value != 0);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border, width: 1),
          ),
          // Stacked rather than side-by-side: at half width there isn't room for
          // icon + label + value on one line, so the name sits above the value
          // with the drag affordance trailing it.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: c.fgMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: c.fgMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    valueLabel,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: c.fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  // Drag affordance: the chip is swept horizontally, which
                  // nothing else about it advertises.
                  Icon(Icons.drag_indicator,
                      size: 14, color: c.fgMuted.withValues(alpha: 0.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ARCADE SYNC header: the master toggle for the cabinet timing simulation
/// and, while engaged, a live summary of both dials.
///
/// Tap to toggle and a plain ON/OFF readout, exactly like every other control in
/// the shade — a [Switch] was tried here and read as foreign, since nothing else
/// in the shade uses one. State is carried by the same fill/border treatment the
/// TURN tiles and CONSTANT chip use, so this reads as one of them despite owning
/// the two chips below it.
///
/// This is also the ONLY place the FAST/SLOW hue appears: the summary label
/// takes it, so one line reports the direction for both dials. The chips
/// themselves stay neutral — tinting two side-by-side chips turned the row into
/// competing blocks of colour.
class ArcadeSyncHeader extends StatelessWidget {
  const ArcadeSyncHeader({
    super.key,
    required this.on,
    required this.summary,
    required this.summaryAccent,
    required this.onTap,
  });

  final bool on;

  /// The song's measured sync, e.g. "song is FAST by 12.3ms" — the same reading
  /// the previous page's Sync card shows. Always present: it describes the song,
  /// not the mode, so it stays visible whether ARCADE SYNC is engaged or not.
  final String summary;

  /// FAST/SLOW hue for [summary], or null to leave it the shade's muted grey
  /// (a song that is on the beat, or ships no sync data).
  final Color? summaryAccent;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _tileColors(scheme, on);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(on ? Icons.sync : Icons.sync_disabled,
                size: 16, color: c.fgMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "ARCADE SYNC",
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: c.fgMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.2,
                      // The one accented element in the section: the song's own
                      // FAST/SLOW bias, so the direction it leans reads before
                      // the number does.
                      fontWeight: summaryAccent != null
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color:
                          summaryAccent ?? c.fgMuted.withValues(alpha: 0.75),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            // Plain ON/OFF text in the same weight the CONSTANT chip uses for its
            // value — no Switch, no chevron. State reads from the shared tile
            // fill/border treatment plus this word, exactly like the rest of the
            // shade's controls.
            Text(
              on ? "ON" : "OFF",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: c.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single TURN tile (MIRROR / LEFT / RIGHT) in the split second row of the
/// ARROWS section. Neutral like [ConstantChip]; the selected turn reads a touch
/// brighter with a stronger border. Tapping the active one turns it off (handled
/// by the caller).
class TurnTile extends StatelessWidget {
  const TurnTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;

  // A conceptual Material glyph standing in for DDR's turn icon: swap_vert for
  // MIRROR's up/down flip pair, rotate_left/right for the 90° turns. Keeps the
  // shade free of copyrighted arcade art while reading the same at a glance.
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _tileColors(scheme, selected);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c.fg),
            const SizedBox(height: 4),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
                color: c.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small always-visible pull-tab pinned to a screen edge, vertically centred
/// so it never collides with the full-width header or transport. Two mirrored
/// instances exist: the RIGHT tab shows/hides the floating controls, the LEFT
/// tab pulls the settings shade down/up. [leftEdge] flips the shape so the
/// rounded corners always face away from the edge the tab hangs off.
class EdgeTab extends StatelessWidget {
  const EdgeTab({
    super.key,
    required this.leftEdge,
    required this.icon,
    required this.onTap,
  });

  final bool leftEdge;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.horizontal(
            left: leftEdge ? Radius.zero : const Radius.circular(12),
            right: leftEdge ? const Radius.circular(12) : Radius.zero,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.9),
          size: 22,
        ),
      ),
    );
  }
}

/// A tappable ∓ end-cap inside the read-speed pane. Dimmed when its step would
/// run off the end of the mod list.
class EdgeButton extends StatelessWidget {
  const EdgeButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: double.infinity,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: enabled
                ? scheme.onSurface.withValues(alpha: 0.85)
                : scheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}

// A HI-SPEED multiplier as DDR WORLD prints it — the cabinet's own format
// string is "x %.2lf" (sans the space here): always two decimals, and in
// SCROLL SPEED mode the derived multiplier genuinely uses the hundredths.
String fmtXMod(double mod) => "x${mod.toStringAsFixed(2)}";

String fmtTime(double s) {
  final m = (s ~/ 60).toString();
  final sec = (s % 60).floor().toString().padLeft(2, '0');
  return "$m:$sec";
}
