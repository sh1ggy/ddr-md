/// Name: CircleState
/// Parent: CirclePage
/// Description: The player's circle, through the Worker in infra/circles: the
/// DDR dancer name and DDR-CODE others know them by, the invite code (a day
/// long) that lets people into their circle, who's in it, and whose circles
/// they're in, and who of them is at the arcade right now. Two players in
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
  bool loading = false;
  String error = '';

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

  Future<void> refresh() => _run(() => _send('GET', 'v1/me'));

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

  /// Joins the circle [code] opens; true once in.
  Future<bool> join(String code) async =>
      await _run(() async {
        await _send('POST', 'v1/join', {'code': code});
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
