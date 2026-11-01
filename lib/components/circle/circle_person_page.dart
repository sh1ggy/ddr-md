/// Name: CirclePersonPage
/// Parent: CirclePage
/// Description: Someone from your circles: who they are and how you're tied,
/// where they're playing and each credit of it to cheer while they're
/// live, otherwise their last session in brief, cheered as one. Refreshes
/// every half minute while it's open. Leaving or taking out is in the corner.
library;

import 'dart:async';

import 'package:ddr_md/components/circle/circle_credit_card.dart';
import 'package:ddr_md/components/circle/circle_page.dart';
import 'package:ddr_md/components/circle/circle_sheets.dart';
import 'package:ddr_md/components/circle/circle_widgets.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/nav_bar.dart' show LivePulse;
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<void> openPersonPage(
        BuildContext context, CirclePerson person, CircleTie tie) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => CirclePersonPage(person: person, tie: tie)));

class CirclePersonPage extends StatefulWidget {
  const CirclePersonPage({super.key, required this.person, required this.tie});
  final CirclePerson person;
  final CircleTie tie;

  @override
  State<CirclePersonPage> createState() => _CirclePersonPageState();
}

class _CirclePersonPageState extends State<CirclePersonPage> {
  late final Timer _poll;

  @override
  void initState() {
    super.initState();
    final circle = context.read<CircleState>();
    WidgetsBinding.instance.addPostFrameCallback((_) => circle.poll());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => circle.poll());
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final pop = FloorPop.of(context);
    // The latest of them: live, or gone from your circles meanwhile.
    final person = [...circle.following, ...circle.circle]
            .where((p) => p.id == widget.person.id)
            .firstOrNull ??
        widget.person;
    // Credit by credit while they're playing; once it's over, the session
    // in brief.
    final live = person.live != null;
    final credits =
        live ? circle.liveCreditsOf(person) : circle.lastSessionOf(person);
    final seesThem = widget.tie != CircleTie.cheeringYou;
    return Scaffold(
      appBar: AppBar(actions: [
        HeaderButton(
          icon: const Icon(Icons.more_horiz),
          tooltip: 'Circle options',
          onPressed: () => showPersonSheet(context, person, widget.tie),
        ),
      ]),
      bottomNavigationBar: !seesThem
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: CircleScanButton(
                label: 'Scan ${person.name}’s QR',
                onPressed: () => openJoinCircle(context),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: circle.poll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            Column(children: [
              CircleBubble(person, size: 72),
              const SizedBox(height: 12),
              Text(person.name,
                  textAlign: TextAlign.center,
                  style: FloorPop.display(24,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              DdrCodeBadge(person.ddrCode),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(widget.tie.icon, size: 14, color: pop.voltText),
                const SizedBox(width: 6),
                Text(widget.tie.heading,
                    style: TextStyle(
                        color: pop.voltText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ]),
            if (person.live case final live?) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: pop
                    .stripes(
                        color: pop.stage, radius: BorderRadius.circular(18))
                    .copyWith(
                      border: Border.all(
                          color: FloorPop.volt.withValues(alpha: 0.55)),
                    ),
                child: Row(children: [
                  const LivePulse(),
                  const SizedBox(width: 6),
                  Text('LIVE', style: pop.label.copyWith(color: pop.voltText)),
                  const SizedBox(width: 10),
                  Text('C${live.credit}',
                      style: FloorPop.readout(21,
                          color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(width: 10),
                  Icon(
                      live.venue.isEmpty
                          ? Icons.location_off_outlined
                          : Icons.place_outlined,
                      size: 16,
                      color: pop.haze),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(
                          live.venue.isEmpty ? 'Location hidden' : live.venue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Text(live.side, style: pop.label.copyWith(color: pop.haze)),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            if (!seesThem || credits.isEmpty)
              CircleStory(
                person: person,
                you: (
                  id: circle.id ?? 'you',
                  name: circle.name,
                  ddrCode: circle.ddrCode,
                  friend: false,
                  live: null,
                ),
                kind: !seesThem
                    ? CircleStoryKind.cheeringYou
                    : live
                        ? CircleStoryKind.awaitingSync
                        : CircleStoryKind.quiet,
              )
            else if (live) ...[
              Text('CREDITS', style: pop.label),
              const SizedBox(height: 10),
              for (final c in credits) CircleCreditCard(c),
            ] else
              CircleSessionCard(credits),
          ],
        ),
      ),
    );
  }
}
