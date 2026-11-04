/// Name: CirclePersonPage
/// Parent: CirclePage
/// Description: A friend's identity, showcase and previous session. Their
/// current live session opens separately, leaving this profile consistent
/// whether they're playing or away. Circle options sit in the corner.
library;

import 'dart:async';

import 'package:ddr_md/components/circle/showcase_page.dart';
import 'package:ddr_md/components/circle/circle_credit_card.dart';
import 'package:ddr_md/components/circle/circle_page.dart';
import 'package:ddr_md/components/circle/circle_sheets.dart';
import 'package:ddr_md/components/circle/circle_widgets.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/circle/circle_live_page.dart';
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
    // The profile keeps the previous session even during a new broadcast.
    final live = person.live != null;
    final credits = circle.lastSessionOf(person);
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
            if (seesThem && live)
              TextButton.icon(
                  icon: const Icon(Icons.sensors),
                  label: const Text('View live session'),
                  onPressed: () =>
                      openLivePersonPage(context, person, widget.tie)),
            if (seesThem) ...[
              const SizedBox(height: 16),
              CircleShowcase(person: person, revision: circle.feedRevision),
            ],
            if (seesThem) ...[
              const SizedBox(height: 28),
              Divider(color: pop.line),
              const SizedBox(height: 12),
              Text('LAST SESSION', style: pop.label),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 20),
            if (!seesThem)
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
                    : CircleStoryKind.quiet,
              )
            else if (credits.isEmpty)
              Text('No previous session shared in the last two days.',
                  style: TextStyle(color: pop.haze))
            else
              CircleSessionCard(credits),
          ],
        ),
      ),
    );
  }
}
