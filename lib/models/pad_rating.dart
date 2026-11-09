/// Name: PadRating
/// Parent: PadCheck
/// Description: The player's own read of a pad after a session: a clear lamp
/// for how one side of a cabinet felt, and the arrows that misbehaved, each
/// with what it did and roughly where on the arrow. Not an official check.
/// A rating belongs to its session, so one made days later still dates to
/// the night it describes.
library;

import 'dart:convert';

import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/models/session_model.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Bumped on every save, so the views showing ratings reload.
final padRatingsRevision = ValueNotifier(0);

/// A rating this old (by its session) may not hold any more.
const kPadRatingStale = Duration(days: 28);

enum PadArrow {
  up,
  left,
  right,
  down;

  /// The rim toward the cabinet's frame, and the one toward the centre.
  PadZone get outerRim => switch (this) {
        up => PadZone.top,
        down => PadZone.bottom,
        left => PadZone.left,
        right => PadZone.right,
      };
  PadZone get innerRim => switch (this) {
        up => PadZone.bottom,
        down => PadZone.top,
        left => PadZone.right,
        right => PadZone.left,
      };

  /// Its rims as offered: outer, inner, then the two sides.
  List<PadZone> get rims => [
        outerRim,
        innerRim,
        for (final z in PadZone.values)
          if (z != outerRim && z != innerRim) z
      ];

  String rimLabel(PadZone z) => z == outerRim
      ? 'Outer edge'
      : z == innerRim
          ? 'Inner edge'
          : '${z.name[0].toUpperCase()}${z.name.substring(1)} edge';
}

/// What a misbehaving arrow does, in the words pad threads use.
enum PadIssue {
  dropsSteps('Drops steps'),
  heavy('Heavy'),
  dead('Dead'),
  sticky('Sticky'),
  ghosts('Ghosts'),
  dropsHolds('Drops holds');

  const PadIssue(this.label);
  final String label;
}

/// Which rim of the arrow's panel, as seen standing on the pad: a panel's
/// sensors run along its four edges.
enum PadZone { top, right, bottom, left }

/// How each lamp reads as a pad, best first.
const kPadVibes = {
  ClearLamp.mfc: 'Flawless',
  ClearLamp.pfc: 'Great',
  ClearLamp.gfc: 'Good',
  ClearLamp.fc: 'Solid',
  ClearLamp.life4: 'Tilting',
  ClearLamp.clear: 'Fighting it',
  ClearLamp.failed: 'Broken',
};

@immutable
class ArrowFlag {
  const ArrowFlag({this.issues = const {}, this.zone});

  final Set<PadIssue> issues;
  final PadZone? zone;

  bool get isEmpty => issues.isEmpty && zone == null;

  ArrowFlag toggled(PadIssue issue) => ArrowFlag(
      issues: issues.contains(issue)
          ? ({...issues}..remove(issue))
          : {...issues, issue},
      zone: zone);

  ArrowFlag zoned(PadZone? z) => ArrowFlag(issues: issues, zone: z);

  Map<String, Object?> toJson() => {
        'issues': [
          for (final i in PadIssue.values)
            if (issues.contains(i)) i.name
        ],
        if (zone != null) 'zone': zone!.name,
      };

  // Names a newer app added are skipped; early builds' "outer" and
  // "inner" are that arrow's rims.
  factory ArrowFlag.fromJson(Map m, PadArrow a) => ArrowFlag(
        issues: {
          for (final n in (m['issues'] as List? ?? const []))
            if (PadIssue.values.asNameMap()[n] case final i?) i
        },
        zone: switch (m['zone']) {
          'outer' => a.outerRim,
          'inner' => a.innerRim,
          final z => PadZone.values.asNameMap()[z],
        },
      );
}

/// One side of one cabinet as rated after [sessionId].
class PadRating {
  PadRating({
    String? id,
    required this.sessionId,
    required this.cabinet,
    required this.side,
    required this.lamp,
    this.arrows = const {},
    DateTime? ratedAt,
    this.sessionAt,
  })  : id = id ?? const Uuid().v4(),
        ratedAt = ratedAt ?? DateTime.now();

  final String id;
  final String sessionId;
  final Cabinet cabinet;
  final PadSide side;
  final ClearLamp lamp;
  final Map<PadArrow, ArrowFlag> arrows;
  final DateTime ratedAt;

  /// When its session started: what the rating dates to.
  final DateTime? sessionAt;

  DateTime get at => sessionAt ?? ratedAt;
  bool get stale => DateTime.now().difference(at) > kPadRatingStale;

  static String encodeArrows(Map<PadArrow, ArrowFlag> arrows) => json.encode({
        for (final MapEntry(:key, :value) in arrows.entries)
          if (!value.isEmpty) key.name: value.toJson()
      });

  static Map<PadArrow, ArrowFlag> decodeArrows(String? s) {
    final m = s == null || s.isEmpty ? const {} : json.decode(s) as Map;
    return {
      for (final MapEntry(:key, :value) in m.entries)
        if (PadArrow.values.asNameMap()[key] case final a?)
          a: ArrowFlag.fromJson(value as Map, a)
    };
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'cabinetId': cabinet.id,
        'side': side.name,
        'lamp': lamp.name,
        'arrows': encodeArrows(arrows),
        'ratedAt': ratedAt.toIso8601String(),
      };

  /// From a row joined with its cabinet, venue and session.
  factory PadRating.fromMap(Map<String, Object?> m) => PadRating(
        id: m['id'] as String,
        sessionId: m['sessionId'] as String,
        cabinet: Cabinet(m['cabinetId'] as int, m['venueId'] as int,
            m['venueName'] as String, m['cabinetName'] as String),
        side: PadSide.values.byName(m['side'] as String),
        lamp: ClearLamp.values.asNameMap()[m['lamp']] ?? ClearLamp.clear,
        arrows: decodeArrows(m['arrows'] as String?),
        ratedAt: DateTime.parse(m['ratedAt'] as String),
        sessionAt: m['sessionAt'] == null
            ? null
            : DateTime.parse(m['sessionAt'] as String),
      );

  /// "Up drops steps · outer edge", "Up, right flagged", or "Nothing flagged".
  String get flagSummary => summarize(arrows);

  static String summarize(Map<PadArrow, ArrowFlag> arrows) {
    if (arrows.isEmpty) return 'Nothing flagged';
    String name(PadArrow a) => a.name[0].toUpperCase() + a.name.substring(1);
    if (arrows.length > 1) {
      return '${[
        for (final a in PadArrow.values)
          if (arrows.containsKey(a)) name(a)
      ].join(', ')} flagged';
    }
    final MapEntry(key: a, value: f) = arrows.entries.single;
    return [
      name(a) +
          (f.issues.isEmpty
              ? ''
              : ' ${PadIssue.values.firstWhere(f.issues.contains).label.toLowerCase()}'),
      if (f.zone != null) a.rimLabel(f.zone!).toLowerCase(),
    ].join(' · ');
  }
}
