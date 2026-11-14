import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a GRAND PRIX chart reads as default from its release day', () {
    final song = SongInfo.fromJson({
      'name': 'x',
      'sp': {'easy': 5, 'hard': 12, 'challenge': 15},
      'charts': [],
      'unlocks': {
        'sp': {
          'hard': {'via': 'galaxy_brave'},
          'challenge': {
            'via': 'grand_prix',
            'pack': 'SPECIAL pop\'n music vol.1',
            'until': '2026-06-30'
          },
          'easy': {'via': 'some_future_event'},
        },
      },
    });
    final before = DateTime(2026, 6, 29), after = DateTime(2026, 6, 30);
    expect(song.unlockAt(Modes.singles, 0, before), isNull);
    expect(song.unlockAt(Modes.singles, 1, after)?.source,
        UnlockSource.galaxyBrave);
    expect(song.unlockAt(Modes.singles, 2, before)?.source,
        UnlockSource.grandPrix);
    expect(song.unlockAt(Modes.singles, 2, after), isNull);
  });
}
