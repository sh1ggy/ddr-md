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
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_showing case final cheer?)
          Positioned(
            top: 0,
            left: 16,
            right: 16,
            child: SafeArea(
                bottom: false,
                child: Align(
                    alignment: Alignment.topCenter,
                    child: Semantics(
                        liveRegion: true,
                        child: Material(
                          elevation: 8,
                          color: FloorPop.of(context).stage,
                          borderRadius: BorderRadius.circular(22),
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                        child: CheerNote(cheer.cheer,
                                            name: cheer.name,
                                            personId: cheer.id)),
                                    const SizedBox(width: 12),
                                    Flexible(
                                        child: Text(
                                            'Cheering you on\nCredit ${cheer.credit}',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600))),
                                    Semantics(
                                        label: 'Dismiss cheer',
                                        button: true,
                                        child: IconButton(
                                            onPressed: _next,
                                            icon: const Icon(Icons.close,
                                                size: 18))),
                                  ])),
                        )))),
          ),
      ]);
}
