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
import 'package:ddr_md/models/settings_model.dart';
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
      ClearLamp.failed => null,
    };

String sideName(PadSide s) => s == PadSide.p1 ? 'P1' : 'P2';

/// "Left cab · P1", or "P1" at a venue with one cab.
String padSideLabel(Cabinet c, PadSide s) =>
    c.name.isEmpty ? sideName(s) : '${c.name} · ${sideName(s)}';

/// "Today", "Yesterday", a weekday within the week, then weeks ago.
String padWhen(DateTime at) {
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
String padDay(DateTime at) => '${const [
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

/// A rated lamp in its art; FAILED, which has none, as a grey tag.
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
      this.label = true});

  final ClearLamp lamp;
  final double width, height;
  final bool label;

  @override
  Widget build(BuildContext context) => Lean(
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: kLampColors[lamp],
              borderRadius: BorderRadius.circular(height * 0.28)),
          child: label
              ? Upright(
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(lampCode(lamp),
                          style: const TextStyle(
                              fontFamily: kReadoutFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 0.4,
                              color: FloorPop.onVolt)),
                    ),
                  ),
                )
              : null,
        ),
      );
}

/// The pad's four arrows in a 3×3, flagged ones in coral.
class MiniPad extends StatelessWidget {
  const MiniPad(this.flagged, {super.key, this.size = 30});

  final Set<PadArrow> flagged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final gap = size * 0.07;
    final cell = (size - gap * 2) / 3;
    Widget at(PadArrow a, double x, double y) => Positioned(
          left: x * (cell + gap),
          top: y * (cell + gap),
          child: Container(
            width: cell,
            height: cell,
            decoration: BoxDecoration(
                color: flagged.contains(a) ? FloorPop.coral : pop.line,
                borderRadius: BorderRadius.circular(cell * 0.25)),
          ),
        );
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
  PadArrow selected = PadArrow.up;
  bool open = false;
  // The side's rating from an earlier session, for "Same as last".
  PadRating? last;
}

class _RatingSheetState extends State<_RatingSheet> {
  late final _rows = [for (final s in widget.sides) _Row(s)];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mine = await DatabaseProvider.getSessionPadRatings(widget.session.id);
    final venue =
        await DatabaseProvider.getVenuePadRatings(widget.session.venue.id);
    if (!mounted) return;
    setState(() {
      for (final r in _rows) {
        bool same(PadRating x) =>
            x.cabinet.id == r.key.cabinet.id && x.side == r.key.side;
        if (mine.where(same).firstOrNull case final m?) {
          r.lamp = m.lamp;
          r.arrows = {...m.arrows};
        }
        r.last = venue
            .where((x) =>
                same(x) &&
                x.sessionId != widget.session.id &&
                !x.at.isAfter(widget.session.startedAt))
            .firstOrNull;
        // A fix is an untick, not starting over.
        if (r.lamp == null && r.last != null) r.arrows = {...r.last!.arrows};
      }
    });
  }

  Future<bool> _save() async {
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
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final text = Theme.of(context).textTheme;
    final rated = _rows.any((r) => r.lamp != null);
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
                '${widget.session.venue.name} · just your read',
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
              onPressed: !rated || _saving
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
                  onPressed: !rated || _saving
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
    final last = r.last;
    final flagged = r.arrows.entries.where((e) => !e.value.isEmpty).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(padSideLabel(r.key.cabinet, r.key.side),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  if (hint != null)
                    Text(hint!.text,
                        style: TextStyle(
                            fontSize: 12,
                            color: hint!.warn ? FloorPop.coral : pop.haze)),
                ],
              ),
            ),
            if (last != null)
              ActionChip(
                backgroundColor: pop.riser,
                side: BorderSide.none,
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Same as last', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  LampTag(last.lamp, width: 40, height: 16),
                ]),
                onPressed: () {
                  r.lamp = last.lamp;
                  r.arrows = {...last.arrows};
                  onChanged();
                },
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
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
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: r.lamp == l
                                      ? FloorPop.volt
                                      : Colors.transparent,
                                  width: 2),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: ExcludeSemantics(
                                child: LampTag(l, width: 38, height: 22)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          Row(children: [
            Expanded(
              child: Text(r.lamp == null ? 'Tap a lamp' : kPadVibes[r.lamp]!,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          r.lamp == null ? FontWeight.w400 : FontWeight.w700,
                      color: r.lamp == null ? pop.haze : null)),
            ),
            TextButton.icon(
              onPressed: () {
                r.open = !r.open;
                onChanged();
              },
              icon: const Icon(Icons.flag_outlined,
                  size: 18, color: FloorPop.coral),
              label: Text(flagged == 0 ? 'Flag arrows' : 'Flagged $flagged'),
            ),
          ]),
          if (r.open) _Flags(row: r, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Flags extends StatelessWidget {
  const _Flags({required this.row, required this.onChanged});

  final _Row row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final r = row;
    final cur = r.arrows[r.selected] ?? const ArrowFlag();
    void set(ArrowFlag f) {
      r.arrows = {...r.arrows, r.selected: f};
      onChanged();
    }

    Widget panel(PadArrow a) {
      final flagged = !(r.arrows[a]?.isEmpty ?? true);
      final on = r.selected == a;
      return Semantics(
        button: true,
        selected: on,
        label: '${a.name} arrow${flagged ? ', flagged' : ''}',
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () {
            r.selected = a;
            onChanged();
          },
          child: Container(
            decoration: BoxDecoration(
              color:
                  flagged ? FloorPop.coral.withValues(alpha: 0.18) : pop.riser,
              border: Border.all(
                  color: on
                      ? FloorPop.volt
                      : flagged
                          ? FloorPop.coral
                          : pop.line,
                  width: on ? 2 : 1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Transform.rotate(
                angle: switch (a) {
                  PadArrow.up => 0,
                  PadArrow.right => math.pi / 2,
                  PadArrow.down => math.pi,
                  PadArrow.left => -math.pi / 2,
                },
                child: CustomPaint(
                    size: const Size.square(22),
                    painter:
                        _ChevronPainter(flagged ? FloorPop.coral : pop.haze)),
              ),
            ),
          ),
        ),
      );
    }

    Widget chip(String label, bool on, Color fill, VoidCallback onTap,
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
          label: Text(label),
          onSelected: (_) => onTap(),
        );

    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: pop.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox.square(
            dimension: 126,
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
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
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.selected.name.toUpperCase()} ARROW',
                  style: TextStyle(
                      fontFamily: kReadoutFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: pop.haze)),
              const SizedBox(height: 4),
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
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text('ROUGHLY WHERE',
            style: TextStyle(
                fontFamily: kReadoutFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: pop.haze)),
        const SizedBox(height: 4),
        Wrap(spacing: 5, children: [
          for (final z in PadZone.values)
            chip(z.label, cur.zone == z, FloorPop.volt,
                () => set(cur.zoned(cur.zone == z ? null : z))),
        ]),
      ]),
    );
  }
}

/// Home's one prompt after a session: rate its sides, or wave it off. Gone
/// once they're rated, waved off, or a few days on.
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
        DateTime.now().difference(visit.end) > _lasts ||
        Settings.getString(Settings.padNudgeDismissedKey) == session.id) {
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
          if (rated == null) return const SizedBox.shrink();
          final left = sides
              .where((s) => !rated
                  .any((r) => r.cabinet.id == s.cabinet.id && r.side == s.side))
              .length;
          if (left == 0) return const SizedBox.shrink();
          return _NudgeRow(
            sides: left,
            onRate: () => showPadRatingSheet(context,
                session: session, sides: sides, hints: sideHints(visit, data)),
            onDismiss: () async {
              await Settings.setString(
                  Settings.padNudgeDismissedKey, session.id);
              padRatingsRevision.value++;
            },
          );
        },
      ),
    );
  }
}

class _NudgeRow extends StatelessWidget {
  const _NudgeRow(
      {required this.sides, required this.onRate, required this.onDismiss});

  final int sides;
  final VoidCallback onRate, onDismiss;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
          color: pop.riser, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const PadGlyph(size: 22, lit: true),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: onRate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text.rich(TextSpan(children: [
                const TextSpan(
                    text: 'How were the pads?',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
                    text: ' · $sides side${sides == 1 ? '' : 's'}',
                    style: TextStyle(color: pop.haze)),
              ])),
            ),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: FloorPop.volt,
              foregroundColor: FloorPop.onVolt,
              minimumSize: const Size(44, 40)),
          onPressed: onRate,
          child: const Text('Rate'),
        ),
        IconButton(
          tooltip: 'Not now',
          icon: Icon(Icons.close, size: 18, color: pop.haze),
          onPressed: onDismiss,
        ),
      ]),
    );
  }
}

/// A session page's Pads card: each side it played on, rated or not.
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
    final pop = FloorPop.of(context);
    final hints = sideHints(visit, data);
    void rate() => showPadRatingSheet(context,
        session: session, sides: sides, hints: hints);
    return ValueListenableBuilder(
      valueListenable: padRatingsRevision,
      builder: (context, _, __) => FutureBuilder<List<PadRating>>(
        future: DatabaseProvider.getSessionPadRatings(session.id),
        builder: (context, snapshot) {
          final rated = snapshot.data ?? const [];
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
                () {
                  final r = rated
                      .where((r) =>
                          r.cabinet.id == s.cabinet.id && r.side == s.side)
                      .firstOrNull;
                  final hint = hints[(s.cabinet.id, s.side)];
                  return InkWell(
                    onTap: rate,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: pop.line))),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(padSideLabel(s.cabinet, s.side)),
                              Text(
                                  r != null
                                      ? '${r.flagSummary} · rated '
                                          '${padWhen(r.ratedAt)}'
                                      : hint?.text ?? 'Not rated',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: r == null && (hint?.warn ?? false)
                                          ? FloorPop.coral
                                          : pop.haze)),
                            ],
                          ),
                        ),
                        if (r != null) ...[
                          MiniPad(r.arrows.keys.toSet()),
                          const SizedBox(width: 10),
                          PadLamp(r.lamp),
                        ] else
                          Text('Rate',
                              style: TextStyle(
                                  color: pop.voltText,
                                  fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  );
                }(),
            ],
          );
        },
      ),
    );
  }
}

/// Under the credit sheet's side picker: each side of [cabinet] as last
/// rated, so a sketchy one shows before the credit starts.
class CabinetPadLamps extends StatelessWidget {
  const CabinetPadLamps({super.key, required this.cabinet});

  final Cabinet? cabinet;

  @override
  Widget build(BuildContext context) {
    final c = cabinet;
    if (c == null) return const SizedBox.shrink();
    final pop = FloorPop.of(context);
    return ValueListenableBuilder(
      valueListenable: padRatingsRevision,
      builder: (context, _, __) => FutureBuilder<List<PadRating>>(
        future: DatabaseProvider.getVenuePadRatings(c.venueId),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const [];
          PadRating? latest(PadSide s) =>
              all.where((r) => r.cabinet.id == c.id && r.side == s).firstOrNull;
          if (PadSide.values.every((s) => latest(s) == null)) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              for (final s in PadSide.values)
                Expanded(
                  child: Opacity(
                    opacity: latest(s)?.stale ?? false ? 0.55 : 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: switch (latest(s)) {
                        null => [
                            Text('Not rated',
                                style: TextStyle(fontSize: 12, color: pop.haze))
                          ],
                        final r => [
                            PadLamp(r.lamp, height: 14),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                  r.arrows.isEmpty
                                      ? padWhen(r.at)
                                      : '${r.flagSummary.split(' · ').first} · ${padWhen(r.at)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: r.arrows.isEmpty
                                          ? pop.haze
                                          : FloorPop.coral)),
                            ),
                          ],
                      },
                    ),
                  ),
                ),
            ]),
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
        Map<(int, PadSide), double> timing
      })> _load() async {
    final venue = (await DatabaseProvider.getVenues())
        .where((v) => v.id == venueId)
        .firstOrNull;
    final cabinets = await DatabaseProvider.getCabinets(venueId);
    final timing = <(int, PadSide), double>{};
    for (final c in cabinets) {
      for (final s in PadSide.values) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
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
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final s in PadSide.values) ...[
                                        if (s == PadSide.p2)
                                          const SizedBox(width: 10),
                                        Expanded(
                                          child: _SideTile(
                                            side: s,
                                            trail: [
                                              for (final r in d.ratings)
                                                if (r.cabinet.id == c.id &&
                                                    r.side == s)
                                                  r
                                            ],
                                            timing: d.timing[(c.id, s)],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (CircleState.available &&
                                      context.watch<CircleState>().id != null &&
                                      d.ratings
                                          .any((r) => r.cabinet.id == c.id))
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
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
                                        child: const Text('Post to circle'),
                                      ),
                                    ),
                                ],
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                              child: Text(
                                  'Your read of each pad, not an official check. '
                                  'Rate them from a session\'s page.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontSize: 12, color: pop.haze)),
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
  const _SideTile({required this.side, required this.trail, this.timing});

  final PadSide side;
  // Newest first.
  final List<PadRating> trail;
  final double? timing;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final r = trail.firstOrNull;
    return Opacity(
      opacity: r?.stale ?? false ? 0.55 : 1,
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
              MiniPad(r?.arrows.keys.toSet() ?? const {}),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r == null ? 'Not rated' : kPadVibes[r.lamp]!,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    if (r != null)
                      Text(r.flagSummary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: pop.haze)),
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
    );
  }
}
