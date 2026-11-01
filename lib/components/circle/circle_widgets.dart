/// Name: CircleWidgets
/// Parent: CirclePage, CirclePersonPage, CircleSheets
/// Description: The identity badge, bottom scan action and small visual
/// stories for a friend's next credit or a connection that's still one way.
library;

import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/components/circle/circle_page.dart' show CircleBubble;
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

/// The cabinet identity, styled the same wherever a circle shows it.
class DdrCodeBadge extends StatelessWidget {
  const DdrCodeBadge(this.code, {super.key});
  final String code;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: pop.riser, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.badge_outlined, size: 15, color: pop.haze),
        const SizedBox(width: 6),
        Flexible(
          child: Text('DDR-CODE ${formatDdrCode(code)}',
              style: TextStyle(
                  color: pop.haze, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// A centered, labelled scan action shared by the tab and friend pages.
class CircleScanButton extends StatelessWidget {
  const CircleScanButton(
      {super.key, required this.onPressed, this.label = 'Scan theirs'});
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: VoltButton(
            height: 52,
            radius: 18,
            onPressed: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.qr_code_scanner, size: 20),
                const SizedBox(width: 10),
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ]),
            ),
          ),
        ),
      );
}

enum CircleStoryKind { quiet, awaitingSync, cheeringYou }

/// A short story with a credit ticket or an arrow between the two dancers.
class CircleStory extends StatelessWidget {
  const CircleStory(
      {super.key, required this.person, required this.you, required this.kind});
  final CirclePerson person, you;
  final CircleStoryKind kind;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final connection = kind == CircleStoryKind.cheeringYou;
    final waiting = kind == CircleStoryKind.awaitingSync;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(children: [
        if (connection)
          _ConnectionScene(person: person, you: you)
        else
          _CreditTicket(waiting: waiting),
        const SizedBox(height: 22),
        Text(
            connection
                ? 'Bring their side into view'
                : waiting
                    ? 'Next credit, your cheer'
                    : 'Catch their next session',
            textAlign: TextAlign.center,
            style: FloorPop.display(18,
                color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 10),
        Text(
            connection
                ? 'Scan ${person.name}\'s QR to see their sessions.'
                : waiting
                    ? 'Credits arrive as they sync.'
                    : '${person.name} hasn’t shared a credit in the last two days.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pop.haze, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),
        if (connection)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.visibility_off_outlined, size: 16, color: pop.haze),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Their sessions aren’t visible to you yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pop.haze, fontSize: 12)),
            ),
          ])
        else ...[
          Divider(color: pop.line, height: 1),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _StoryStep(icon: Icon(Icons.album_outlined), label: 'Credit'),
            _StepArrow(color: pop.haze),
            const _StoryStep(
                icon: Icon(Icons.cloud_download_outlined), label: 'Sync'),
            _StepArrow(color: pop.haze),
            const _StoryStep(
                icon: CheerIcon(), label: 'Cheer', color: FloorPop.coral),
          ]),
        ],
      ]),
    );
  }
}

class _CreditTicket extends StatelessWidget {
  const _CreditTicket({required this.waiting});
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Semantics(
      image: true,
      label: waiting ? 'A credit waiting to sync' : 'Waiting for a new credit',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 156,
          height: 132,
          child: Center(
            child: Transform.rotate(
              angle: -0.12,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 116,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: pop.stage,
                      border: Border.all(color: pop.line),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.album_outlined,
                        size: 32, color: FloorPop.padBlue),
                    const SizedBox(height: 13),
                    for (final width in [64.0, 42.0])
                      Container(
                        width: width,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 7),
                        decoration: BoxDecoration(
                            color: pop.riser,
                            borderRadius: BorderRadius.circular(3)),
                      ),
                  ]),
                ),
                Positioned(
                  right: -14,
                  bottom: -10,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration:
                        BoxDecoration(color: pop.riser, shape: BoxShape.circle),
                    child: Icon(
                        waiting
                            ? Icons.cloud_download_outlined
                            : Icons.bedtime_outlined,
                        size: 20,
                        color: waiting ? pop.voltText : FloorPop.coral),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionScene extends StatelessWidget {
  const _ConnectionScene({required this.person, required this.you});
  final CirclePerson person, you;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    Widget dancer(CirclePerson p, String label) => Expanded(
          child: Column(children: [
            CircleBubble(p, size: 56),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: pop.haze, fontSize: 12)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(children: [
        dancer(person, person.name),
        Expanded(
          child: Column(children: [
            const Icon(Icons.celebration_outlined,
                size: 24, color: FloorPop.coral),
            const Icon(Icons.arrow_right_alt, size: 32, color: FloorPop.coral),
            Text('cheers for you',
                textAlign: TextAlign.center,
                style: TextStyle(color: pop.haze, fontSize: 11)),
          ]),
        ),
        dancer(you, 'You'),
      ]),
    );
  }
}

class _StoryStep extends StatelessWidget {
  const _StoryStep({required this.icon, required this.label, this.color});
  final Widget icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Expanded(
      child: Column(children: [
        SizedBox(
          height: 32,
          child: IconTheme.merge(
              data: IconThemeData(color: color ?? pop.haze, size: 22),
              child: icon),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: pop.haze, fontSize: 12)),
      ]),
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Icon(Icons.chevron_right, size: 16, color: color),
      );
}
