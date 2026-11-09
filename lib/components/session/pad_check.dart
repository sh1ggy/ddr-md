/// Name: PadCheck
/// Parent: LastSessionCard, VisitPage, CreditSheet
/// Description: Rating the pads after a session, whenever the player gets to
/// it: every side a session's credits played on, on one sheet, each with a
/// lamp for how it felt and the arrows that misbehaved. Home nudges once
/// after a session; the session's page keeps a Pads card; the credit sheet
/// shows each side's last lamp; the venue's pads page has every cab. Just
/// the player's read, never an official check.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/pad_post.dart';
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/session_page.dart' show signedMs;
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp, RecentPlay;
import 'package:ddr_md/models/pad_rating.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Best first, as the rating strip lists them.
const _lamps = [
  ClearLamp.mfc,
  ClearLamp.pfc,
  ClearLamp.gfc,
  ClearLamp.fc,
  ClearLamp.life4,
  ClearLamp.clear,
  ClearLamp.failed,
];

String lampCode(ClearLamp l) => switch (l) {
      ClearLamp.mfc => 'MFC',
      ClearLamp.pfc => 'PFC',
      ClearLamp.gfc => 'GFC',
      ClearLamp.fc => 'FC',
      ClearLamp.life4 => 'LIFE4',
      ClearLamp.clear => 'CLEAR',
      ClearLamp.failed => 'FAILED',
    };

String? _lampArt(ClearLamp l) => switch (l) {
      ClearLamp.mfc => fullComboIcon(FullComboTier.mfc),
      ClearLamp.pfc => fullComboIcon(FullComboTier.pfc),
      ClearLamp.gfc => fullComboIcon(FullComboTier.gfc),
      ClearLamp.fc => fullComboIcon(FullComboTier.fc),
      ClearLamp.life4 => life4Icon,
      ClearLamp.clear => clearIcon,
      // No lamp for a fail: its E grade, as the score overview shows it.
      ClearLamp.failed => 'assets/icons/rank_e.png',
    };

String sideName(PadSide s) => s == PadSide.p1 ? 'P1' : 'P2';

/// "Left cab · P1", or "P1" at a venue with one cab.
String padSideLabel(Cabinet c, PadSide s) =>
    c.name.isEmpty ? sideName(s) : '${c.name} · ${sideName(s)}';

/// "Today", "Yesterday", a weekday within the week, then weeks ago.
String padWhen(DateTime at) {
  at = at.toLocal();
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) {
    return const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun'
    ][at.weekday - 1];
  }
  final weeks = days ~/ 7;
  return weeks == 1 ? '1 wk ago' : '$weeks wks ago';
}

/// "Sun 1 Nov".
String padDay(DateTime at) => _day(at.toLocal());

String _day(DateTime at) => '${const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun'
    ][at.weekday - 1]} '
    '${at.day} ${const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ][at.month - 1]}';

/// A rated lamp in its art (a fail as its E).
class PadLamp extends StatelessWidget {
  const PadLamp(this.lamp, {super.key, this.height = 18});

  final ClearLamp lamp;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tag = LampTag(lamp, width: height * 3.2, height: height);
    final art = _lampArt(lamp);
    return Semantics(
      label: lampCode(lamp),
      child: ExcludeSemantics(
        child: art == null
            ? tag
            : Image.asset(art,
                height: height, errorBuilder: (_, __, ___) => tag),
      ),
    );
  }
}

/// A lamp as a leaning tag in its colour, for the rating strip and trails.
class LampTag extends StatelessWidget {
  const LampTag(this.lamp,
      {super.key,
      required this.width,
      required this.height,
      this.label = true,
      this.ring});

  final ClearLamp lamp;
  final double width, height;
  final bool label;

  /// Volt around the tag, on its lean, when true: the picked lamp. Null
  /// leaves no room for one.
  final bool? ring;

  @override
  Widget build(BuildContext context) => Lean(
        child: ring == null
            ? _tag()
            : Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    border: Border.all(
                        color: ring! ? FloorPop.volt : Colors.transparent,
                        width: 2),
                    borderRadius: BorderRadius.circular(height * 0.28 + 4)),
                child: _tag(),
              ),
      );

  Widget _tag() {
    final art = label ? _lampArt(lamp) : null;
    final text = Text(lampCode(lamp),
        style: const TextStyle(
            fontFamily: kReadoutFont,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 0.4,
            color: FloorPop.onVolt));
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          // The lamp's own art reads on the dark, edged in its colour.
          color: art == null ? kLampColors[lamp] : FloorPop.night.ink,
          border: art == null
              ? null
              : Border.all(color: kLampColors[lamp]!, width: 1.5),
          borderRadius: BorderRadius.circular(height * 0.28)),
      child: !label
          ? null
          : Upright(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: FittedBox(
                  child: art == null
                      ? text
                      : Image.asset(art,
                          height: height, errorBuilder: (_, __, ___) => text),
                ),
              ),
            ),
    );
  }
}

/// The pad's four arrows in a 3×3, flagged ones in coral. A flag with a
/// rim lights that edge of the panel solid.
class MiniPad extends StatelessWidget {
  const MiniPad(this.flags, {super.key, this.size = 30, this.idle});

  final Map<PadArrow, ArrowFlag> flags;
  final double size;

  /// The unflagged arrows' colour; the card's line by default.
  final Color? idle;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final gap = size * 0.07;
    final cell = (size - gap * 2) / 3;
    Widget at(PadArrow a, double x, double y) {
      final f = flags[a];
      final on = f != null && !f.isEmpty;
      return Positioned(
        left: x * (cell + gap),
        top: y * (cell + gap),
        child: Container(
          width: cell,
          height: cell,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: !on
                  ? idle ?? pop.line
                  : f.zone == null
                      ? FloorPop.coral
                      : FloorPop.coral.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(cell * 0.25)),
          child: on && f.zone != null ? _rimBand(f.zone!, cell) : null,
        ),
      );
    }

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(children: [
          at(PadArrow.up, 1, 0),
          at(PadArrow.left, 0, 1),
          at(PadArrow.right, 2, 1),
          at(PadArrow.down, 1, 2),
        ]),
      ),
    );
  }
}

/// A solid coral strip along the [rim] of a panel [cell] wide.
Widget _rimBand(PadZone rim, double cell) {
  final across = rim == PadZone.top || rim == PadZone.bottom;
  return Align(
    alignment: switch (rim) {
      PadZone.top => Alignment.topCenter,
      PadZone.right => Alignment.centerRight,
      PadZone.bottom => Alignment.bottomCenter,
      PadZone.left => Alignment.centerLeft,
    },
    child: Container(
      width: across ? cell : cell * 0.3,
      height: across ? cell * 0.3 : cell,
      color: FloorPop.coral,
    ),
  );
}

/// Each issue's glyph: the Chevron doing what the arrow does.
class IssueGlyph extends StatelessWidget {
  const IssueGlyph(this.issue, {super.key, this.size = 16, this.color});

  final PadIssue issue;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _IssuePainter(
            issue, color ?? IconTheme.of(context).color ?? Colors.white),
      );
}

class _IssuePainter extends CustomPainter {
  _IssuePainter(this.issue, this.color);

  final PadIssue issue;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(List<double> p, [Paint? with_]) {
      final path = Path()..moveTo(p[0], p[1]);
      for (var i = 2; i < p.length; i += 2) {
        path.lineTo(p[i], p[i + 1]);
      }
      canvas.drawPath(path, with_ ?? paint);
    }

    switch (issue) {
      case PadIssue.dropsSteps:
        line([5, 14, 9.5, 9.5]);
        line([14.5, 9.5, 19, 14]);
        canvas.drawCircle(const Offset(12, 19.5), 1.5, Paint()..color = color);
      case PadIssue.heavy:
        line([5, 11, 12, 4, 19, 11]);
        line([6, 16, 18, 16]);
        line([9, 20.5, 15, 20.5]);
      case PadIssue.dead:
        line([5, 15.5, 12, 8.5, 19, 15.5]);
        line([4, 4, 20, 20]);
      case PadIssue.sticky:
        line([5, 13, 12, 6, 19, 13]);
        line([4, 18, 20, 18]);
        line([9, 18, 9, 21]);
      case PadIssue.ghosts:
        line([5, 11, 12, 4, 19, 11]);
        line([5, 19, 12, 12, 19, 19],
            Paint.from(paint)..color = color.withValues(alpha: 0.45));
      case PadIssue.dropsHolds:
        line([7, 8, 12, 3, 17, 8]);
        line([12, 4, 12, 10]);
        line([12, 15, 12, 21]);
    }
  }

  @override
  bool shouldRepaint(_IssuePainter old) =>
      old.issue != issue || old.color != color;
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(
        Path()
          ..moveTo(6, 14)
          ..lineTo(12, 8)
          ..lineTo(18, 14),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

/// One side a session played on.
typedef PadSideKey = ({Cabinet cabinet, PadSide side});

/// Every side [credits] (newest first) were played on, first played first.
List<PadSideKey> sidesPlayed(List<Credit> credits) {
  final seen = <(int, PadSide)>{};
  return [
    for (final c in credits.reversed)
      if (seen.add((c.cabinet.id, c.side))) (cabinet: c.cabinet, side: c.side)
  ];
}

/// A line under each side, from how its credits scored against the usual.
Map<(int, PadSide), ({String text, bool warn})> sideHints(
    Visit visit, VisitData data) {
  final session = visit.session;
  if (session == null || visit.plays.isEmpty) return const {};
  final timing = data.timing[session.id] ?? [];
  final credits = data.credits[session.id] ?? [];
  final (played, matched) = reconcileTiming(visit.plays, timing);
  final bySide = <(int, PadSide), List<RecentPlay>>{};
  final count = <(int, PadSide), int>{};
  for (final (credit, plays) in groupByCredit(played, credits, matched)) {
    if (credit == null) continue;
    final k = (credit.cabinet.id, credit.side);
    bySide.putIfAbsent(k, () => []).addAll(plays);
    count[k] = (count[k] ?? 0) + 1;
  }
  return {
    for (final MapEntry(:key, :value) in bySide.entries)
      key: () {
        final points =
            value.isEmpty ? const [] : data.model.summarize(value).points;
        final gap = points.isEmpty
            ? null
            : points
                    .map((p) => p.play.score! - p.usual)
                    .reduce((a, b) => a + b) /
                points.length;
        final n = count[key]!;
        if (gap != null && gap <= -15000) {
          return (text: 'Scored well below your usual', warn: true);
        }
        return (text: '$n credit${n == 1 ? '' : 's'} here', warn: false);
      }(),
  };
}

/// Rate every side [session] played on, starting from any ratings it has.
Future<void> showPadRatingSheet(BuildContext context,
        {required PlaySession session,
        required List<PadSideKey> sides,
        Map<(int, PadSide), ({String text, bool warn})> hints = const {}}) =>
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) =>
          _RatingSheet(session: session, sides: sides, hints: hints),
    );

class _RatingSheet extends StatefulWidget {
  const _RatingSheet(
      {required this.session, required this.sides, required this.hints});

  final PlaySession session;
  final List<PadSideKey> sides;
  final Map<(int, PadSide), ({String text, bool warn})> hints;

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _Row {
  _Row(this.key);
  final PadSideKey key;
  ClearLamp? lamp;
  Map<PadArrow, ArrowFlag> arrows = {};
  // The arrow whose issues show, once one's tapped.
  PadArrow? selected;
  // Its flags open under the lamps.
  bool open = false;
}

/// A side's rating as of [session]: its own, else the latest before it.
PadRating? padRatingAsOf(
    List<PadRating> venue, PlaySession session, Cabinet c, PadSide side) {
  bool same(PadRating x) => x.cabinet.id == c.id && x.side == side;
  return venue.where((x) => same(x) && x.sessionId == session.id).firstOrNull ??
      venue
          .where((x) => same(x) && !x.at.isAfter(session.startedAt))
          .firstOrNull;
}

class _RatingSheetState extends State<_RatingSheet> {
  late final _rows = [for (final s in widget.sides) _Row(s)];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // A side's own rating for this session, else the arrows flagged last
  // time (hardware carries over; how it felt that day doesn't).
  Future<void> _load() async {
    final venue =
        await DatabaseProvider.getVenuePadRatings(widget.session.venue.id);
    if (!mounted) return;
    setState(() {
      for (final r in _rows) {
        if (padRatingAsOf(venue, widget.session, r.key.cabinet, r.key.side)
            case final was?) {
          if (was.sessionId == widget.session.id) r.lamp = was.lamp;
          r.arrows = {...was.arrows};
        }
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    for (final r in _rows) {
      if (r.lamp == null) continue;
      await DatabaseProvider.savePadRating(PadRating(
          sessionId: widget.session.id,
          cabinet: r.key.cabinet,
          side: r.key.side,
          lamp: r.lamp!,
          arrows: {
            for (final MapEntry(:key, :value) in r.arrows.entries)
              if (!value.isEmpty) key: value
          }));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final text = Theme.of(context).textTheme;
    final changed = _rows.any((r) => r.lamp != null);
    final circle = context.watch<CircleState>();
    final canPost = CircleState.available && circle.id != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How were the pads?', style: text.titleLarge),
            const SizedBox(height: 2),
            Text(
                '${padDay(widget.session.startedAt)} at '
                '${widget.session.venue.name}',
                style: TextStyle(fontSize: 13, color: pop.haze)),
            const SizedBox(height: 12),
            for (final r in _rows) ...[
              _SideRow(
                row: r,
                hint: widget.hints[(r.key.cabinet.id, r.key.side)],
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            VoltButton(
              onPressed: !changed || _saving
                  ? null
                  : () async {
                      await _save();
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text('Save'),
            ),
            Row(children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Not now')),
              const Spacer(),
              if (canPost)
                TextButton(
                  onPressed: !changed || _saving
                      ? null
                      : () async {
                          await _save();
                          final ratings =
                              await DatabaseProvider.getSessionPadRatings(
                                  widget.session.id);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          await showPadPostSheet(context,
                              session: widget.session, ratings: ratings);
                        },
                  child: const Text('Save & post to circle'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({required this.row, this.hint, required this.onChanged});

  final _Row row;
  final ({String text, bool warn})? hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final r = row;
    final flagged = r.arrows.values.any((f) => !f.isEmpty);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: pop.ink,
        border: Border.all(color: pop.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: padSideLabel(r.key.cabinet, r.key.side),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                if (hint case final h? when h.warn)
                  TextSpan(
                      text: ' · ${h.text.toLowerCase()}',
                      style:
                          const TextStyle(fontSize: 12, color: FloorPop.coral)),
              ])),
            ),
            // The flags sit behind the side's own pad: its flagged arrows
            // lit, tap to open.
            Tooltip(
              message: flagged ? 'Flagged arrows' : 'Flag an arrow',
              child: InkResponse(
                radius: 24,
                onTap: () {
                  r.open = !r.open;
                  if (!r.open) r.selected = null;
                  onChanged();
                },
                child: Container(
                  width: 44,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r.open ? pop.riser : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: MiniPad(r.arrows,
                      size: 20, idle: pop.haze.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(children: [
              for (final l in _lamps)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: r.lamp == l,
                    label: '${lampCode(l)}, ${kPadVibes[l]}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        r.lamp = l;
                        onChanged();
                      },
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: AnimatedOpacity(
                            duration: FloorPop.sixteenth,
                            opacity: r.lamp == null || r.lamp == l ? 1 : 0.3,
                            child: ExcludeSemantics(
                                child: LampTag(l,
                                    width: 44, height: 24, ring: r.lamp == l)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          if (r.lamp != null)
            Text(kPadVibes[r.lamp]!,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if (r.open)
            Container(
              margin: const EdgeInsets.only(top: 10, right: 4),
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: pop.line))),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _TapPad(row: r, onChanged: onChanged),
                const SizedBox(width: 12),
                Expanded(
                  child: r.selected == null
                      ? const SizedBox.shrink()
                      : _Issues(row: r, onChanged: onChanged),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// The side's pad as the flag control: tap an arrow to say what it did.
class _TapPad extends StatelessWidget {
  const _TapPad({required this.row, required this.onChanged});

  final _Row row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final r = row;
    Widget panel(PadArrow a) {
      final flagged = !(r.arrows[a]?.isEmpty ?? true);
      final zone = r.arrows[a]?.zone;
      final on = r.selected == a;
      return Semantics(
        button: true,
        selected: on,
        label: '${a.name} arrow${flagged ? ', flagged' : ''}',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            r.selected = on ? null : a;
            onChanged();
          },
          child: Container(
            decoration: BoxDecoration(
              color:
                  flagged ? FloorPop.coral.withValues(alpha: 0.18) : pop.riser,
              borderRadius: BorderRadius.circular(7),
            ),
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                  color: on
                      ? FloorPop.volt
                      : flagged
                          ? FloorPop.coral
                          : pop.line,
                  width: on ? 2 : 1),
              borderRadius: BorderRadius.circular(7),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(alignment: Alignment.center, children: [
              if (zone != null)
                Positioned.fill(
                  child: LayoutBuilder(
                      builder: (_, c) => _rimBand(zone, c.maxWidth)),
                ),
              Transform.rotate(
                angle: switch (a) {
                  PadArrow.up => 0,
                  PadArrow.right => math.pi / 2,
                  PadArrow.down => math.pi,
                  PadArrow.left => -math.pi / 2,
                },
                child: CustomPaint(
                    size: const Size.square(16),
                    painter:
                        _ChevronPainter(flagged ? FloorPop.coral : pop.haze)),
              ),
            ]),
          ),
        ),
      );
    }

    return SizedBox.square(
      dimension: 90,
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(),
          panel(PadArrow.up),
          const SizedBox(),
          panel(PadArrow.left),
          const SizedBox(),
          panel(PadArrow.right),
          const SizedBox(),
          panel(PadArrow.down),
          const SizedBox(),
        ],
      ),
    );
  }
}

/// What the tapped arrow did, and roughly where.
class _Issues extends StatelessWidget {
  const _Issues({required this.row, required this.onChanged});

  final _Row row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final r = row;
    final a = r.selected!;
    final cur = r.arrows[a] ?? const ArrowFlag();
    void set(ArrowFlag f) {
      r.arrows = {...r.arrows, a: f};
      onChanged();
    }

    final label = TextStyle(
        fontFamily: kReadoutFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: pop.haze);
    Widget chip(String text, bool on, Color fill, VoidCallback onTap,
            {Widget? icon}) =>
        FilterChip(
          showCheckmark: false,
          selected: on,
          selectedColor: fill,
          backgroundColor: pop.riser,
          side: BorderSide.none,
          labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: on ? FloorPop.onVolt : null),
          avatar: icon,
          label: Text(text),
          onSelected: (_) => onTap(),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${a.name.toUpperCase()} ARROW', style: label),
      const SizedBox(height: 6),
      Wrap(spacing: 5, runSpacing: 5, children: [
        for (final i in PadIssue.values)
          chip(i.label, cur.issues.contains(i), FloorPop.coral,
              () => set(cur.toggled(i)),
              icon: IssueGlyph(i,
                  size: 18,
                  color: cur.issues.contains(i)
                      ? FloorPop.onVolt
                      : FloorPop.coral)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 5, children: [
        for (final z in a.rims)
          chip(a.rimLabel(z), cur.zone == z, FloorPop.volt,
              () => set(cur.zoned(cur.zone == z ? null : z))),
      ]),
    ]);
  }
}

/// Home's prompt after a session: a chip among its tags, gone once every
/// side it played is rated or a few days on.
class PadNudge extends StatelessWidget {
  const PadNudge({super.key, required this.visit, required this.data});

  final Visit visit;
  final VisitData data;

  static const _lasts = Duration(days: 3);

  @override
  Widget build(BuildContext context) {
    final session = visit.session;
    final active = context.watch<SessionState>().session?.id;
    if (session == null ||
        session.id == active ||
        DateTime.now().difference(visit.end) > _lasts) {
      return const SizedBox.shrink();
    }
    final sides = sidesPlayed(data.credits[session.id] ?? []);
    if (sides.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: padRatingsRevision,
      builder: (context, _, __) => FutureBuilder<List<PadRating>>(
        future: DatabaseProvider.getSessionPadRatings(session.id),
        builder: (context, snapshot) {
          final rated = snapshot.data;
          if (rated == null ||
              sides.every((s) => rated.any(
                  (r) => r.cabinet.id == s.cabinet.id && r.side == s.side))) {
            return const SizedBox.shrink();
          }
          return Semantics(
            button: true,
            child: GestureDetector(
              onTap: () => showPadRatingSheet(context,
                  session: session,
                  sides: sides,
                  hints: sideHints(visit, data)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
                decoration: BoxDecoration(
                    color: FloorPop.volt,
                    borderRadius: BorderRadius.circular(99)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  PadGlyph(size: 13, color: FloorPop.onVolt),
                  SizedBox(width: 5),
                  Text('How were the pads?',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: FloorPop.onVolt)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A session page's Pads card: how each side it played on felt that
/// session; tap one to rate it.
class PadsCard extends StatelessWidget {
  const PadsCard({super.key, required this.visit, required this.data});

  final Visit visit;
  final VisitData data;

  @override
  Widget build(BuildContext context) {
    final session = visit.session;
    if (session == null) return const SizedBox.shrink();
    final sides = sidesPlayed(data.credits[session.id] ?? []);
    if (sides.isEmpty) return const SizedBox.shrink();
    final hints = sideHints(visit, data);
    void rate() => showPadRatingSheet(context,
        session: session, sides: sides, hints: hints);
    return ValueListenableBuilder(
      valueListenable: padRatingsRevision,
      builder: (context, _, __) => FutureBuilder<List<PadRating>>(
        future: DatabaseProvider.getSessionPadRatings(session.id),
        builder: (context, snapshot) {
          final rated = snapshot.data ?? const <PadRating>[];
          return HomeCard(
            title: 'Pads',
            icon: Icons.grid_view_rounded,
            heading: Row(mainAxisSize: MainAxisSize.min, children: [
              const PadGlyph(size: 20, lit: true),
              const SizedBox(width: 8),
              Text('Pads', style: Theme.of(context).textTheme.titleMedium),
            ]),
            onMore: () => context.push('/home/pads/${session.venue.id}'),
            children: [
              for (final s in sides)
                _PadsRow(
                  side: s,
                  rating: rated
                      .where((r) =>
                          r.cabinet.id == s.cabinet.id && r.side == s.side)
                      .firstOrNull,
                  hint: hints[(s.cabinet.id, s.side)],
                  onTap: rate,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PadsRow extends StatelessWidget {
  const _PadsRow(
      {required this.side,
      required this.rating,
      required this.hint,
      required this.onTap});

  final PadSideKey side;
  final PadRating? rating;
  final ({String text, bool warn})? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final r = rating;
    final warn = r == null && (hint?.warn ?? false);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: pop.line))),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(padSideLabel(side.cabinet, side.side)),
                Text(
                    r != null
                        ? r.flagSummary
                        : warn
                            ? hint!.text
                            : 'Not rated',
                    style: TextStyle(
                        fontSize: 12, color: warn ? FloorPop.coral : pop.haze)),
              ],
            ),
          ),
          if (r != null) ...[
            MiniPad(r.arrows),
            const SizedBox(width: 10),
            PadLamp(r.lamp),
          ] else
            Text('Rate',
                style: TextStyle(
                    color: pop.voltText, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// Beside a side in the credit sheet's picker: its last rated lamp, so a
/// sketchy side shows before the credit starts. Nothing when unrated.
class SidePadLamp extends StatelessWidget {
  const SidePadLamp({super.key, required this.cabinet, required this.side});

  final Cabinet? cabinet;
  final PadSide side;

  @override
  Widget build(BuildContext context) {
    final c = cabinet;
    if (c == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: padRatingsRevision,
      builder: (context, _, __) => FutureBuilder<List<PadRating>>(
        future: DatabaseProvider.getVenuePadRatings(c.venueId),
        builder: (context, snapshot) {
          final r = (snapshot.data ?? const <PadRating>[])
              .where((r) => r.cabinet.id == c.id && r.side == side)
              .firstOrNull;
          if (r == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Opacity(
                opacity: r.stale ? 0.45 : 1,
                child: PadLamp(r.lamp, height: 12)),
          );
        },
      ),
    );
  }
}

/// Every cab at a venue, each side as last rated, with its trail of
/// earlier lamps and its timing.
class VenuePadsPage extends StatelessWidget {
  const VenuePadsPage({super.key, required this.venueId});

  final int venueId;

  Future<
      ({
        Venue? venue,
        List<Cabinet> cabinets,
        List<PadRating> ratings,
        Map<(int, PadSide), double> timing,
        Map<(int, PadSide), String> lastSession
      })> _load() async {
    final venue = (await DatabaseProvider.getVenues())
        .where((v) => v.id == venueId)
        .firstOrNull;
    final cabinets = await DatabaseProvider.getCabinets(venueId);
    final timing = <(int, PadSide), double>{};
    final lastSession = <(int, PadSide), String>{};
    for (final c in cabinets) {
      for (final s in PadSide.values) {
        if (await DatabaseProvider.getLastSessionOnSide(c.id, s)
            case final id?) {
          lastSession[(c.id, s)] = id;
        }
        final plays = (await DatabaseProvider.getTimingPlays(c.id, s)).take(10);
        if (plays.isNotEmpty) {
          timing[(c.id, s)] =
              plays.map((p) => p.averageMs).reduce((a, b) => a + b) /
                  plays.length;
        }
      }
    }
    return (
      venue: venue,
      cabinets: cabinets,
      ratings: await DatabaseProvider.getVenuePadRatings(venueId),
      timing: timing,
      lastSession: lastSession,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: padRatingsRevision,
      builder: (context, _, __) => FutureBuilder(
        future: _load(),
        builder: (context, snapshot) {
          final d = snapshot.data;
          return HomeSubpage(
            title: d?.venue?.name ?? 'Pads',
            body: d == null
                ? const SizedBox.shrink()
                // Under the page's scaffold, so its header is cleared too.
                : Builder(
                    builder: (context) => ListView(
                          padding: clearOfBars(
                              context, const EdgeInsets.only(bottom: 24)),
                          children: [
                            for (final c in d.cabinets)
                              HomeCard(
                                title: c.name.isEmpty ? 'Pads' : c.name,
                                icon: Icons.grid_view_rounded,
                                heading: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const PadGlyph(size: 20, lit: true),
                                      const SizedBox(width: 8),
                                      Text(c.name.isEmpty ? 'Pads' : c.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                    ]),
                                children: [
                                  IntrinsicHeight(
                                      child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final s in PadSide.values) ...[
                                        if (s == PadSide.p2)
                                          const SizedBox(width: 10),
                                        Expanded(
                                          child: _SideTile(
                                            cabinet: c,
                                            side: s,
                                            trail: [
                                              for (final r in d.ratings)
                                                if (r.cabinet.id == c.id &&
                                                    r.side == s)
                                                  r
                                            ],
                                            timing: d.timing[(c.id, s)],
                                            lastSession:
                                                d.lastSession[(c.id, s)],
                                          ),
                                        ),
                                      ],
                                    ],
                                  )),
                                  if (CircleState.available &&
                                      context.watch<CircleState>().id != null &&
                                      d.ratings
                                          .any((r) => r.cabinet.id == c.id))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: VoltButton(
                                        height: 48,
                                        radius: 16,
                                        onPressed: () {
                                          final latest = [
                                            for (final s in PadSide.values)
                                              if (d.ratings
                                                      .where((r) =>
                                                          r.cabinet.id ==
                                                              c.id &&
                                                          r.side == s)
                                                      .firstOrNull
                                                  case final r?)
                                                r
                                          ];
                                          showPadPostSheet(context,
                                              venueName: c.venueName,
                                              ratings: latest);
                                        },
                                        child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.groups_rounded,
                                                  size: 20),
                                              SizedBox(width: 8),
                                              Text('Post to circle'),
                                            ]),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        )),
          );
        },
      ),
    );
  }
}

class _SideTile extends StatelessWidget {
  const _SideTile(
      {required this.cabinet,
      required this.side,
      required this.trail,
      this.timing,
      this.lastSession});

  final Cabinet cabinet;
  final PadSide side;
  // Newest first.
  final List<PadRating> trail;
  final double? timing;

  /// The last session played on this side; none greys it out.
  final String? lastSession;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final r = trail.firstOrNull;
    final played = lastSession != null || r != null;
    // Rates the side as of the last session on it.
    Future<void> edit() async {
      final session =
          await DatabaseProvider.getSession(lastSession ?? r!.sessionId);
      if (session == null || !context.mounted) return;
      await showPadRatingSheet(context,
          session: session, sides: [(cabinet: cabinet, side: side)]);
    }

    return Opacity(
      opacity: !played
          ? 0.4
          : r?.stale ?? false
              ? 0.55
              : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: played ? edit : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: pop.riser, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Text(sideName(side),
                      style: const TextStyle(
                          fontFamily: kReadoutFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const Spacer(),
                  if (r != null) PadLamp(r.lamp, height: 16),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  MiniPad(r?.arrows ?? const {}),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            r != null
                                ? r.flagSummary
                                : played
                                    ? 'Not rated'
                                    : 'Not played',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: r == null
                                ? const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700)
                                : TextStyle(fontSize: 12, color: pop.haze)),
                      ],
                    ),
                  ),
                ]),
                if (r != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    // Oldest first, toward the latest.
                    for (final t in trail.take(5).toList().reversed) ...[
                      LampTag(t.lamp, width: 16, height: 8, label: false),
                      const SizedBox(width: 4),
                    ],
                    const Spacer(),
                    Text(padWhen(r.at),
                        style: TextStyle(fontSize: 11, color: pop.haze)),
                  ]),
                ],
                if (timing case final ms?) ...[
                  Divider(height: 16, color: pop.line),
                  Row(children: [
                    Text('Timing avg',
                        style: TextStyle(fontSize: 11, color: pop.haze)),
                    const Spacer(),
                    Text(signedMs(ms), style: FloorPop.readout(12)),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
