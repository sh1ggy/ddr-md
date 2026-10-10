/// Name: ContentUpdateTest
/// Description: A published update reaches the app: changed and new files are
/// downloaded and read ahead of the bundle, a corrupt download changes
/// nothing, and patterns from another engine are left alone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/content_updater.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  test('downloads what differs from the bundle, verified, for next launch',
      () async {
    final support = Directory.systemTemp.createTempSync('content_test');
    addTearDown(() => support.deleteSync(recursive: true));

    final bundle = ContentManifest(
      format: kContentFormat,
      content: 1,
      engine: kPatternEngineVersion,
      files: {'steps/A.json': _sha('old A'), 'patterns/A.json': _sha('pA')},
    );
    final remote = ContentManifest(
      format: kContentFormat,
      content: 2,
      engine: kPatternEngineVersion + 1,
      files: {
        'steps/A.json': _sha('new A'),
        'steps/B.json': _sha('B'),
        'patterns/A.json': _sha('pA2'),
      },
    );
    final served = {
      'latest.json': jsonEncode({'format': kContentFormat, 'content': 2}),
      'manifest.json': jsonEncode(remote),
      for (final s in ['new A', 'B', 'pA2']) 'objects/${_sha(s)}.json': s,
    };
    final fetched = <String>[];
    Future<List<int>> fetch(Uri url) async {
      final path = url.path.substring(1);
      fetched.add(path);
      return utf8.encode(served[path]!);
    }

    await ContentStore.init(support, bundle: bundle);

    served['objects/${_sha('B')}.json'] = 'tampered';
    await expectLater(
        ContentUpdater.check(support, base: 'https://x/', fetch: fetch),
        throwsFormatException);
    await ContentStore.init(support, bundle: bundle);
    expect(ContentStore.inUse, isEmpty);

    served['objects/${_sha('B')}.json'] = 'B';
    fetched.clear();
    expect(
        await ContentUpdater.check(support, base: 'https://x/', fetch: fetch),
        isTrue);
    expect(fetched, isNot(contains('objects/${_sha('pA2')}.json')));

    await ContentStore.init(support, bundle: bundle);
    expect(await ContentStore.loadString('assets/steps/A.json'), 'new A');
    expect(await ContentStore.loadString('assets/steps/B.json'), 'B');
    expect(ContentStore.inUse, {'${_sha('new A')}.json', '${_sha('B')}.json'});
    expect(
        await ContentUpdater.check(support, base: 'https://x/', fetch: fetch),
        isFalse);
  });
}
