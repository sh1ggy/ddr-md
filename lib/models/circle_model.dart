/// Name: CircleState
/// Parent: CirclePage
/// Description: The player's circle, through the Worker in infra/circles: the
/// DDR dancer name and DDR-CODE others know them by, the invite code (a day
/// long) that lets people into their circle, who's in it, and whose circles
/// they're in, and who of them is at the arcade right now, with the credits
/// they share as each syncs and the preset cheers on them. Two players in
/// each other's circles are friends. There's no
/// sign-in: the account is its own [DeviceKey], apart from the backup's. The
/// last answer is kept so the tab shows something offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/models/device_key.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';

/// Release builds default to the live server; debug/profile to off unless
/// given --dart-define=CIRCLES_URL=… (terraform output circles_url, or
/// infra/circles/dev/server.mjs).
const kCirclesUrl = String.fromEnvironment('CIRCLES_URL',
    defaultValue: kReleaseMode ? 'https://circles.ddr-md.workers.dev' : '');

/// A debug build's fixed key, so infra/circles/dev/scenario.mjs can act as
/// this player. Ignored in release builds.
const _devKey = kReleaseMode ? '' : String.fromEnvironment('CIRCLES_KEY');

/// A session someone is broadcasting to their circle: where, and the
/// credit they're on.
typedef CircleLive = ({String venue, int credit, String side, DateTime? at});

/// Someone in your circle, or whose circle you're in. [id] tells apart two
/// who gave the same DDR-CODE. [live] only on whose circle you're in.
typedef CirclePerson = ({
  String id,
  String name,
  String ddrCode,
  bool friend,
  CircleLive? live,
});

/// A circle an invite code opens, before joining it.
typedef CirclePreview = ({CirclePerson leader, int members, int friends});

/// The cheers on offer: presets only, so there's no free text to moderate.
/// [id] is what the server takes.
enum Cheer {
  letsGo('lets_go', "LET'S GO"),
  clean('clean', 'CLEAN!'),
  stamina('stamina', 'STAMINA'),
  soClose('so_close', 'SO CLOSE'),
  restUp('rest_up', 'REST UP'),
  legend('legend', 'LEGEND');

  const Cheer(this.id, this.label);
  final String id;
  final String label;

  static Cheer? of(Object? id) =>
      Cheer.values.where((c) => c.id == id).firstOrNull;
}

/// One song of a shared credit, as e-amusement synced it. [best]: it set
/// the chart's best.
typedef CirclePlay = ({
  String song,
  String mode,
  String difficulty,
  int? score,
  bool failed,
  bool best
});

/// A credit someone shared as it synced, and the cheers on it. [by] is null
/// for your own; [mine] is the cheer you gave it.
typedef CircleCredit = ({
  CirclePerson? by,
  String session,
  int credit,
  DateTime at,
  List<CirclePlay> plays,
  List<({String name, Cheer cheer})> cheers,
  Cheer? mine,
});

/// What the server said no to, worded for the player.
class CircleException implements Exception {
  CircleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// "SHGY7FK2" as it's shown and read out: "SHGY-7FK2".
String formatCircleCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

/// "12345678" as the cabinet shows a DDR-CODE: "1234-5678".
String formatDdrCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

/// What a circle's QR code holds: the code, in a link a future version could
/// open the app with.
String circleQrData(String code) => 'ddrmd://circle/$code';

final _codeIn = RegExp('[A-HJ-NP-Z2-9]{4}-?[A-HJ-NP-Z2-9]{4}');

/// The circle code in [text] (a QR's data, a pasted share), if any.
String? findCircleCode(String text) =>
    _codeIn.firstMatch(text.toUpperCase())?.group(0)?.replaceAll('-', '');

class CircleState extends ChangeNotifier {
  CircleState() {
    _apply(Settings.getString(Settings.circleStateKey));
  }

  static const _key = DeviceKey('circleKey', Settings.circleKeyKey);

  /// A dancer name as the cabinet allows it.
  static final namePattern = RegExp(r'^[A-Z0-9.\-*&!?#$@ ]{1,8}$');

  static bool get available => kCirclesUrl.isNotEmpty;

  String? id;
  String name = '';
  String ddrCode = '';
  String? code;
  DateTime? codeUntil;
  List<CirclePerson> circle = const [];
  List<CirclePerson> following = const [];

  /// Credits shared by those whose circles you're in, newest first.
  List<CircleCredit> feed = const [];

  /// Your own shared credits, newest first, with their cheers.
  List<CircleCredit> yours = const [];
  bool loading = false;
  String error = '';

  /// [person]'s shared credits, newest first.
  List<CircleCredit> creditsOf(CirclePerson person) => [
        for (final c in feed)
          if (c.by?.id == person.id) c
      ];

  bool get codeLive =>
      code != null && codeUntil != null && codeUntil!.isAfter(DateTime.now());

  static CirclePerson _person(Map p) => (
        id: p['id'] as String,
        name: p['name'] as String,
        ddrCode: p['ddrCode'] as String,
        friend: p['friend'] == true,
        live: switch (p['live']) {
          final Map l => (
              venue: l['venue'] as String,
              credit: l['credit'] as int,
              side: l['side'] as String,
              at: DateTime.tryParse(l['at'] as String? ?? ''),
            ),
          _ => null,
        },
      );

  void _apply(String body) {
    if (body.isEmpty) return;
    final m = json.decode(body) as Map<String, dynamic>;
    List<CirclePerson> people(Object? list) =>
        [for (final p in (list as List? ?? const []).cast<Map>()) _person(p)];
    id = m['id'] as String?;
    name = m['name'] as String? ?? '';
    ddrCode = m['ddrCode'] as String? ?? '';
    code = m['code'] as String?;
    codeUntil = DateTime.tryParse(m['codeUntil'] as String? ?? '');
    circle = people(m['circle']);
    following = people(m['following']);
  }

  /// Sends one request; an answer describing the player's circle replaces
  /// the one kept.
  Future<Map<String, dynamic>?> _send(String method, String path,
      [Object? body]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final base =
          Uri.parse(kCirclesUrl.endsWith('/') ? kCirclesUrl : '$kCirclesUrl/');
      final req = await client.openUrl(method, base.resolve(path));
      final key = _devKey.isNotEmpty ? _devKey : await _key.read();
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(json.encode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      final answer = text.isEmpty
          ? null
          : (json.decode(text) as Map).cast<String, dynamic>();
      if (res.statusCode >= 300) {
        throw CircleException(switch (answer?['error']) {
          'name' => 'Dancer names are up to 8 letters, numbers or symbols',
          'ddrCode' => 'A DDR-CODE is 8 digits',
          'code' => "That code doesn't open a circle",
          'daily limit' => 'Too many tries today, try again tomorrow',
          _ => 'Circles are unavailable (HTTP ${res.statusCode})',
        });
      }
      if (answer != null && answer.containsKey('following')) {
        await Settings.setString(Settings.circleStateKey, text);
        _apply(text);
      }
      return answer;
    } on SocketException {
      // A debug build names the server, which is usually just not started.
      throw CircleException(kReleaseMode
          ? "Circles didn't answer. Pull down to try again."
          : 'Nothing answered at $kCirclesUrl. Is '
              'infra/circles/dev/server.mjs running?');
    } finally {
      client.close();
    }
  }

  /// Runs [request], showing it as loading and keeping its failure in [error].
  Future<T?> _run<T>(Future<T> Function() request) async {
    loading = true;
    error = '';
    notifyListeners();
    try {
      return await request();
    } on CircleException catch (e) {
      error = e.message;
      return null;
    } catch (e) {
      debugPrint('Circles: $e');
      error = 'Something went wrong';
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => _run(() async {
        await _send('GET', 'v1/me');
        await _loadFeed();
      });

  /// [refresh] without showing it: for polling while someone's live. A
  /// failure waits for the next one.
  Future<void> poll() async {
    if (!available || id == null) return;
    try {
      await _send('GET', 'v1/me');
      await _loadFeed();
      notifyListeners();
    } catch (e) {
      debugPrint('Circles: poll failed: $e');
    }
  }

  Future<void> _loadFeed() async {
    if (id == null) return;
    final m = await _send('GET', 'v1/feed');
    List<CircleCredit> credits(Object? list) => [
          for (final c in (list as List? ?? const []).cast<Map>())
            (
              by: c['by'] == null ? null : _person(c['by'] as Map),
              session: c['session'] as String,
              credit: c['credit'] as int,
              at: DateTime.tryParse(c['at'] as String? ?? '') ?? DateTime.now(),
              plays: [
                for (final p in (c['plays'] as List).cast<Map>())
                  (
                    song: p['song'] as String,
                    mode: p['mode'] as String,
                    difficulty: p['difficulty'] as String,
                    score: p['score'] as int?,
                    failed: p['failed'] == true,
                    best: p['best'] == true,
                  )
              ],
              cheers: [
                for (final x in (c['cheers'] as List? ?? const []).cast<Map>())
                  if (Cheer.of(x['preset']) case final cheer?)
                    (name: x['name'] as String, cheer: cheer)
              ],
              mine: Cheer.of(c['mine']),
            )
        ];
    feed = credits(m?['credits']);
    yours = credits(m?['yours']);
  }

  /// Cheers [credit] with [cheer], or takes yours back with null. Shown at
  /// once; a failure puts it back.
  Future<void> cheerFor(CircleCredit credit, Cheer? cheer) async {
    final before = feed;
    feed = [
      for (final c in feed)
        if (c.by?.id == credit.by?.id &&
            c.session == credit.session &&
            c.credit == credit.credit)
          (
            by: c.by,
            session: c.session,
            credit: c.credit,
            at: c.at,
            plays: c.plays,
            cheers: [
              for (final x in c.cheers)
                if (x.name != name) x,
              if (cheer != null) (name: name, cheer: cheer),
            ],
            mine: cheer,
          )
        else
          c
    ];
    notifyListeners();
    try {
      await _send('PUT', 'v1/cheer', {
        'by': credit.by!.id,
        'session': credit.session,
        'credit': credit.credit,
        'preset': cheer?.id,
      });
    } catch (e) {
      debugPrint('Circles: cheer not sent: $e');
      feed = before;
      notifyListeners();
    }
  }

  /// Shares one synced credit of [session] with your circle; sending the
  /// same songs again changes nothing. Quietly, from the arcade.
  Future<void> shareCredit(
      String session, int credit, List<CirclePlay> plays) async {
    if (!available || id == null || plays.isEmpty) return;
    try {
      await _send('PUT', 'v1/credit', {
        'session': session,
        'credit': credit,
        'plays': [
          for (final p in plays)
            {
              'song': p.song,
              'mode': p.mode,
              'difficulty': p.difficulty,
              'score': p.score,
              'failed': p.failed,
              'best': p.best,
            }
        ],
      });
    } catch (e) {
      debugPrint('Circles: credit not shared: $e');
    }
  }

  /// Joins circles as [dancer] with [code], or changes either. True when
  /// the server took them.
  Future<bool> claim(String dancer, String code) async =>
      await _run(
          () => _send('PUT', 'v1/me', {'name': dancer, 'ddrCode': code})) !=
      null;

  /// A new invite code, good for a day; the old one stops working.
  Future<void> newCode() => _run(() => _send('POST', 'v1/code'));

  Future<CirclePreview?> preview(String code) => _run(() async {
        final m = (await _send('GET', 'v1/code/${Uri.encodeComponent(code)}'))!;
        return (
          leader: _person(m['person'] as Map),
          members: m['members'] as int,
          friends: m['friends'] as int,
        );
      });

  /// Joins the circle [code] opens, and with [back] lets its leader into
  /// yours too, which makes you friends in one scan. True once in.
  Future<bool> join(String code, {bool back = false}) async =>
      await _run(() async {
        await _send('POST', 'v1/join', {'code': code, 'back': back});
        return _send('GET', 'v1/me');
      }) !=
      null;

  /// Takes [p] out of your circle; a live code lets them back in.
  Future<void> remove(CirclePerson p) =>
      _run(() => _send('DELETE', 'v1/circle/${p.id}'));

  Future<void> leave(CirclePerson p) =>
      _run(() => _send('DELETE', 'v1/following/${p.id}'));

  /// Whether a credit starting now goes out to the circle, as last chosen.
  static bool get broadcasting =>
      Settings.getInt(Settings.circleBroadcastKey) == 1;

  /// Shows the player's session to their circle: [venue], [credit] and
  /// [side]. Quietly, as it's sent from the arcade between songs; a failure
  /// leaves the last broadcast to lapse on its own.
  Future<void> broadcast(String venue, int credit, String side) async {
    if (!available || id == null) return;
    await Settings.setInt(Settings.circleBroadcastKey, 1);
    try {
      await _send(
          'PUT', 'v1/live', {'venue': venue, 'credit': credit, 'side': side});
    } catch (e) {
      debugPrint('Circles: broadcast not sent: $e');
    }
  }

  /// The session ended, or a credit started without broadcasting.
  /// [keepChoice] for an end, which leaves the next session's choice as is.
  Future<void> endBroadcast({bool keepChoice = false}) async {
    if (!available || id == null) return;
    final was = broadcasting;
    if (!keepChoice) await Settings.setInt(Settings.circleBroadcastKey, 0);
    if (!was) return;
    try {
      await _send('DELETE', 'v1/live');
    } catch (e) {
      debugPrint('Circles: broadcast not ended: $e');
    }
  }

  /// Deletes this player's profile, circle and memberships from the server
  /// and starts over with a new key.
  Future<void> deleteAll() => _run(() async {
        await _send('DELETE', 'v1/me');
        await _key.replace();
        await Settings.setString(Settings.circleStateKey, '');
        id = code = null;
        codeUntil = null;
        name = ddrCode = '';
        circle = following = const [];
      });
}
