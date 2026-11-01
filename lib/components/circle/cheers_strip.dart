/// Name: CheersStrip
/// Parent: LiveSessionCard
/// Description: Under your live card while you broadcast: your latest shared
/// credit of [sessionId] and the cheers it's had as stamps, new ones
/// popping in, or that it's waiting for some. Checks for new cheers every
/// minute while it's on screen, so polling only happens during a broadcast
/// session.
library;

import 'dart:async';

import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CheersStrip extends StatefulWidget {
  const CheersStrip({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<CheersStrip> createState() => _CheersStripState();
}

class _CheersStripState extends State<CheersStrip> {
  late final Timer _poll;
  // Cheers already shown, so only new arrivals pop in.
  final _seen = <String>{};

  @override
  void initState() {
    super.initState();
    final circle = context.read<CircleState>();
    WidgetsBinding.instance.addPostFrameCallback((_) => circle.poll());
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      // Not on another tab, where the card sits offstage.
      if (mounted && TickerMode.valuesOf(context).enabled) circle.poll();
    });
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    if (!CircleState.broadcasting || circle.id == null) {
      return const SizedBox.shrink();
    }
    final pop = FloorPop.of(context);
    final latest =
        circle.yours.where((c) => c.session == widget.sessionId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const PomPom(size: 16),
          const SizedBox(width: 6),
          Text(
              latest == null
                  ? 'YOUR CIRCLE SEES CREDITS AS THEY SYNC'
                  : 'CREDIT ${latest.credit} · '
                      '${latest.cheers.isEmpty ? 'NO CHEERS YET' : '${latest.cheers.length} CHEERS'}',
              style: pop.label),
        ]),
        if (latest != null && latest.cheers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in latest.cheers)
              CheerStamp(c.cheer,
                  key: ValueKey('${latest.credit}:${c.name}:${c.cheer.id}'),
                  name: c.name,
                  pop: _seen.add('${latest.credit}:${c.name}:${c.cheer.id}')),
          ]),
        ],
      ]),
    );
  }
}
