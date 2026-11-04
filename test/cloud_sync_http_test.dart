/// Name: CloudSyncHttpTest
/// Parent: HttpSyncServer
/// Description: Verifies byte-bounded Unicode uploads and conflict indexes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/models/cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large Unicode batches split without losing conflict indexes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var rev = 0;
    var requests = 0;
    var largest = 0;
    final listening = server.listen((request) async {
      final bytes =
          await request.fold<List<int>>([], (all, part) => all..addAll(part));
      if (bytes.length > largest) largest = bytes.length;
      requests++;
      final body = jsonDecode(utf8.decode(bytes)) as Map;
      final changes = body['changes'] as List;
      rev += changes.length;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'rev': rev,
        'lost': [
          for (var i = 0; i < changes.length; i++)
            if (changes[i]['k'] == '7') i
        ],
      }));
      await request.response.close();
    });
    try {
      final client =
          HttpSyncServer('http://127.0.0.1:${server.port}', 'a' * 43);
      final changes = <SyncChange>[
        for (var i = 0; i < 20; i++)
          (t: 'notes', k: '$i', u: '2026-01-01', d: {'text': '界' * 20000}),
      ];
      final result = await client.push(changes);
      expect(result.rev, 20);
      expect(result.lost, [7]);
      expect(requests, greaterThan(1));
      expect(largest, lessThanOrEqualTo(512 * 1024));
    } finally {
      await server.close(force: true);
      await listening.cancel();
    }
  });
}
