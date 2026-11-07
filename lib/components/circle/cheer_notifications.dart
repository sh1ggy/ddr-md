/// Name: CheerNotifications
/// Parent: App
/// Description: Incoming cheers appear briefly above the current page while
/// a session is broadcast. Existing cheers establish a baseline on first
/// fetch; only later arrivals toast, with names attached to their avatars.
library;

import 'dart:async';
import 'dart:collection';

import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CheerNotifications extends StatefulWidget {
  const CheerNotifications({super.key, required this.child});
  final Widget child;

  /// Plays each cheer in turn, for the development tools; nothing is saved.
  static void preview(BuildContext context) =>
      context.findAncestorStateOfType<_CheerNotificationsState>()?._preview();

  @override
  State<CheerNotifications> createState() => _CheerNotificationsState();
}

class _CheerNotificationsState extends State<CheerNotifications>
    with WidgetsBindingObserver {
  late final CircleState _circle;
  late final SessionState _session;
  final _seen = <String, String>{};
  final _pending =
      Queue<({String name, String? id, Cheer cheer, int credit})>();
  ({String name, String? id, Cheer cheer, int credit})? _showing;
  Timer? _poll;
  Timer? _dismiss;
  int _revision = -1;
  String? _sessionId;
  bool _baseline = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _circle = context.read<CircleState>();
    _session = context.read<SessionState>();
    _circle.addListener(_changed);
    _session.addListener(_changed);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && _session.active && CircleState.broadcasting) {
        _circle.poll();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _session.active && CircleState.broadcasting) {
        _circle.poll();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _session.active && CircleState.broadcasting) {
      _circle.poll();
    }
  }

  void _changed() {
    final sessionId = _session.session?.id;
    if (sessionId != _sessionId) {
      _sessionId = sessionId;
      _seen.clear();
      _pending.clear();
      _baseline = false;
      _revision = -1;
    }
    if (!_session.active ||
        !CircleState.broadcasting ||
        !_foreground ||
        _circle.feedRevision == 0 ||
        _revision == _circle.feedRevision) {
      return;
    }
    _revision = _circle.feedRevision;
    final present = <String>{};
    for (final credit in _circle.yours.where((c) => c.session == sessionId)) {
      for (final c in credit.cheers) {
        final key = '${credit.credit}:${c.id ?? c.name}';
        present.add(key);
        final changed = _seen[key] != c.cheer.id;
        _seen[key] = c.cheer.id;
        if (changed && _baseline && _pending.length < 8) {
          _pending.add(
              (name: c.name, id: c.id, cheer: c.cheer, credit: credit.credit));
        }
      }
    }
    _seen.removeWhere((key, _) => !present.contains(key));
    _baseline = true;
    if (_showing == null && _pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _next();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  /// Every cheer through the real banner, from a made-up circle.
  void _preview() {
    const names = ['MIKA', 'REXX', 'TOFU', 'JUN.K', 'SORA', 'KAI'];
    _pending
      ..clear()
      ..addAll([
        for (final c in Cheer.values)
          (name: names[c.index], id: null, cheer: c, credit: c.index + 1)
      ]);
    _next();
  }

  void _next() {
    _dismiss?.cancel();
    if (!mounted) return;
    setState(() => _showing = _pending.isEmpty ? null : _pending.removeFirst());
    if (_showing != null) _dismiss = Timer(const Duration(seconds: 4), _next);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _dismiss?.cancel();
    _circle.removeListener(_changed);
    _session.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showing = _showing;
    return Stack(children: [
      widget.child,
      Positioned(
        top: 0,
        left: 16,
        right: 16,
        child: SafeArea(
            bottom: false,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : FloorPop.beat,
                      reverseDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : FloorPop.eighth,
                      layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previous,
                            if (current != null) current
                          ]),
                      transitionBuilder: (child, t) => SlideTransition(
                          position: CurvedAnimation(
                                  parent: t,
                                  curve: FloorPop.step,
                                  reverseCurve: FloorPop.settle)
                              .drive(Tween(
                                  begin: const Offset(0, -1.4),
                                  end: Offset.zero)),
                          child: FadeTransition(opacity: t, child: child)),
                      child: showing == null
                          ? const SizedBox.shrink()
                          : _CheerBanner(
                              key: ObjectKey(showing),
                              name: showing.name,
                              cheer: showing.cheer,
                              credit: showing.credit,
                              // An outgoing banner mustn't dismiss the next.
                              onDismiss: () {
                                if (identical(_showing, showing)) _next();
                              }),
                    )))),
      ),
    ]);
  }
}

/// The cheer's own colour edge to edge, its label loudest; swipe up to dismiss.
class _CheerBanner extends StatelessWidget {
  const _CheerBanner(
      {super.key,
      required this.name,
      required this.cheer,
      required this.credit,
      required this.onDismiss});
  final String name;
  final Cheer cheer;
  final int credit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      label: '$name: ${cheer.label}, credit $credit',
      onDismiss: onDismiss,
      child: ExcludeSemantics(
          child: GestureDetector(
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < -3) onDismiss();
              },
              child: Material(
                  elevation: 8,
                  color: cheer.color,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                      child: Row(children: [
                        CircleAvatar(
                            radius: 20,
                            backgroundColor: cheer.ink,
                            child: Text(
                                name.isEmpty ? '?' : name.substring(0, 1),
                                style:
                                    FloorPop.display(16, color: cheer.color))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text(cheer.label,
                                  style:
                                      FloorPop.display(20, color: cheer.ink)),
                              Text('$name · Credit $credit',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: cheer.ink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ])),
                        const SizedBox(width: 8),
                        Icon(cheer.icon, color: cheer.ink, size: 26),
                      ]))))));
}
