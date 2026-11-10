/// Name: PadPost
/// Parent: PadCheck, CirclePage
/// Description: Posting a pad check to the circle, after rating a session's
/// pads or from a venue's pads page: one cab's sides as rated that session,
/// previewed as the circle will see it, played sides only. It always names the venue, and carries no typed
/// text, as Circles has none to moderate. [CirclePadCard] is the post as it
/// shows on the Circle tab.
library;

import 'package:ddr_md/components/circle/circle_page.dart' show CircleBubble;
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/pad_check.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/pad_rating.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Post one cab of [ratings], all from [session].
Future<void> showPadPostSheet(BuildContext context,
        {required PlaySession session, required List<PadRating> ratings}) =>
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _PostSheet(session: session, ratings: ratings),
    );

class _PostSheet extends StatefulWidget {
  const _PostSheet({required this.session, required this.ratings});

  final PlaySession session;
  final List<PadRating> ratings;

  String get venue => session.venue.name;

  @override
  State<_PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends State<_PostSheet> {
  late final _cabs =
      {for (final r in widget.ratings) r.cabinet.id: r.cabinet}.values.toList();
  late Cabinet? _cab = _cabs.firstOrNull;
  final _off = <PadSide>{};
  // The cab sides the session played on; null until loaded.
  Set<(int, PadSide)>? _played;
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    DatabaseProvider.getCredits(widget.session.id).then((credits) {
      if (!mounted) return;
      setState(() => _played = {
            for (final s in sidesPlayed(credits)) (s.cabinet.id, s.side)
          });
    });
  }

  bool _postable(PadRating r) =>
      r.cabinet.id == _cab?.id &&
      (_played?.contains((r.cabinet.id, r.side)) ?? false);

  List<PadRating> get _shown => [
        for (final r in widget.ratings)
          if (_postable(r) && !_off.contains(r.side)) r
      ];

  Future<void> _post() async {
    final cab = _cab!;
    setState(() {
      _posting = true;
      _error = null;
    });
    final id = '${widget.session.id}-${cab.id}';
    final ok = await context
        .read<CircleState>()
        .postPads(id, widget.venue, cab.name, _shown);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _posting = false;
        _error = "Couldn't post just now. Try again in a bit.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final circle = context.watch<CircleState>();
    final open = {
      for (final r in widget.ratings)
        if (_postable(r)) r.side
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Post to your circle',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            CirclePadCard((
              by: (
                id: circle.id ?? '',
                name: circle.name,
                ddrCode: circle.ddrCode,
                friend: false,
                live: null
              ),
              id: '',
              at: widget.session.startedAt,
              venue: widget.venue,
              cab: _cab?.name ?? '',
              sides: [
                for (final r in _shown)
                  (side: r.side, lamp: r.lamp, arrows: r.arrows)
              ],
            )),
            if (_cabs.length > 1) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, children: [
                for (final c in _cabs)
                  ChoiceChip(
                    label: Text(c.name.isEmpty ? 'Main cab' : c.name),
                    selected: _cab?.id == c.id,
                    onSelected: (_) => setState(() {
                      _cab = c;
                      _off.clear();
                    }),
                  ),
              ]),
            ],
            const SizedBox(height: 10),
            // Both sides, the ones not played (or rated) that session greyed.
            Wrap(spacing: 8, children: [
              for (final s in PadSide.values)
                FilterChip(
                  label: Text(sideName(s)),
                  selected: open.contains(s) && !_off.contains(s),
                  // One side always stays in.
                  onSelected: !open.contains(s)
                      ? null
                      : (on) => setState(() {
                            if (on) {
                              _off.remove(s);
                            } else if (open.length - _off.length > 1) {
                              _off.add(s);
                            }
                          }),
                ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: pop.riser, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(Icons.location_on_outlined, size: 18, color: pop.haze),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                      TextSpan(style: const TextStyle(fontSize: 12), children: [
                    const TextSpan(text: 'Shared with your circle · '),
                    TextSpan(
                        text: 'names ${widget.venue}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: '. A pad check always says where.'),
                  ])),
                ),
              ]),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            VoltButton(
                onPressed:
                    _cab == null || _shown.isEmpty || _posting ? null : _post,
                child: const Text('Post')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

/// A pad check as the circle sees it.
class CirclePadCard extends StatelessWidget {
  const CirclePadCard(this.pad, {super.key});

  final CirclePad pad;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final by = pad.by;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pop.stage,
        border: Border.all(color: pop.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (by != null) CircleBubble(by, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(by?.name ?? '',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                  [
                    pad.venue,
                    if (pad.cab.isNotEmpty) pad.cab,
                    padWhen(pad.at),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: pop.haze)),
            ]),
          ),
          Transform.rotate(
            angle: 0.07,
            child: Lean(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: pop.riser, borderRadius: BorderRadius.circular(10)),
                child: Upright(
                  child: Text('PAD CHECK',
                      style: FloorPop.display(11, color: FloorPop.coral)),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final (i, s) in pad.sides.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: pop.riser, borderRadius: BorderRadius.circular(14)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Text(sideName(s.side),
                            style: const TextStyle(
                                fontFamily: kReadoutFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const Spacer(),
                        PadLamp(s.lamp, height: 15),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        MiniPad(s.arrows, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(PadRating.summarize(s.arrows),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ]),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}
