import 'package:ddr_md/components/ocr/save_score.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

SongInfo _song() => SongInfo(
      ssc: false,
      version: 'DDR A3',
      name: 'paranoia',
      title: 'PARANOIA',
      titletranslit: '',
      songLength: 90,
      perChart: false,
      singles:
          Difficulty(beginner: 5, easy: 8, medium: 12, hard: 16, challenge: 18),
      doubles: Difficulty(easy: 8, medium: 12, hard: 16),
      radarSingles: {},
      radarDoubles: {},
      singlesNotecounts: Difficulty(
          beginner: 80, easy: 150, medium: 280, hard: 420, challenge: 560),
      doublesNotecounts: Difficulty(easy: 150, medium: 280, hard: 420),
      charts: [],
    );

Widget _panel(Map<String, TextEditingController> controllers) =>
    ChangeNotifierProvider(
      create: (_) => SongState(),
      child: MaterialApp(
        home: Scaffold(
          body: SaveScorePanel(
            controllers: controllers,
            initialTitle: 'PARANOIA',
          ),
        ),
      ),
    );

void main() {
  setUp(() => Songs.list = [_song()]);
  tearDown(() => Songs.list = []);

  DropdownButton<String> dropdownOf(WidgetTester tester) =>
      tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>));

  testWidgets('dropdown pre-selects the chart matched from the OCR reading',
      (tester) async {
    final controllers = {'difficulty': TextEditingController(text: 'ert 16')};
    await tester.pumpWidget(_panel(controllers));

    expect(dropdownOf(tester).value, 'EXPERT');
    expect(find.text('EXPERT 16'), findsWidgets);
  });

  testWidgets('user pick overrides the match and can be reset', (tester) async {
    final controllers = {'difficulty': TextEditingController(text: 'ert 16')};
    await tester.pumpWidget(_panel(controllers));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CHALLENGE 18').last);
    await tester.pumpAndSettle();
    expect(dropdownOf(tester).value, 'CHALLENGE');

    // The close button restores the automatic match, like the song row's.
    await tester.tap(find.byTooltip('Back to automatic match'));
    await tester.pumpAndSettle();
    expect(dropdownOf(tester).value, 'EXPERT');
  });

  testWidgets('unmatched reading leaves no selection and shows it as the hint',
      (tester) async {
    final controllers = {'difficulty': TextEditingController(text: 'qzw 99')};
    await tester.pumpWidget(_panel(controllers));

    expect(dropdownOf(tester).value, null);
    expect(find.text('"qzw 99"?'), findsOneWidget);
  });

  testWidgets('judged step count pre-selects the chart when the reading fails',
      (tester) async {
    // 400+15+4+1+0 = 420 = the EXPERT chart's step count.
    final controllers = {
      'difficulty': TextEditingController(text: 'qzw 99'),
      'marvelous': TextEditingController(text: '400'),
      'perfect': TextEditingController(text: '15'),
      'great': TextEditingController(text: '4'),
      'good': TextEditingController(text: '1'),
      'miss': TextEditingController(text: '0'),
    };
    await tester.pumpWidget(_panel(controllers));

    expect(dropdownOf(tester).value, 'EXPERT');
  });

  testWidgets('dropdown offers only charts the song has in the current mode',
      (tester) async {
    final controllers = {'difficulty': TextEditingController()};
    await tester.pumpWidget(_panel(controllers));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('BEGINNER 5'), findsWidgets);
    expect(find.text('BASIC 8'), findsWidgets);
    expect(find.textContaining('EDIT'), findsNothing);
  });

  group('username mismatch warning', () {
    // Settings caches its SharedPreferences instance, so the mock values
    // must be in place before the first init and are shared by the group.
    setUp(() async {
      SharedPreferences.setMockInitialValues(
          {Settings.usernameKey: 'SHIGGY'});
      await Settings.init();
    });

    Finder warning() => find.textContaining("doesn't match");

    testWidgets('shows when the detected player differs from the setting',
        (tester) async {
      final controllers = {'username': TextEditingController(text: 'RIVAL')};
      await tester.pumpWidget(_panel(controllers));

      expect(warning(), findsOneWidget);
      expect(find.textContaining('RIVAL'), findsOneWidget);
      // Informational only — saving stays enabled.
      final button =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('silent on a case-insensitive match and updates with edits',
        (tester) async {
      final controller = TextEditingController(text: 'shiggy');
      await tester.pumpWidget(_panel({'username': controller}));
      expect(warning(), findsNothing);

      // Correcting the field (as the user would after a misread) updates
      // the warning live.
      controller.text = 'RIVAL';
      await tester.pump();
      expect(warning(), findsOneWidget);
    });

    testWidgets('silent when no username was detected', (tester) async {
      await tester
          .pumpWidget(_panel({'username': TextEditingController()}));
      expect(warning(), findsNothing);
    });
  });
}
