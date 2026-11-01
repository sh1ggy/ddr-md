/// Name: DevelopmentPage
/// Parent: AppSettingsPage, SettingsPage
/// Description: Persistent debug/profile tools, isolated fixtures and previews.
library;

import 'package:ddr_md/components/session/session_wrap.dart';
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_browser.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_store.dart';
import 'package:ddr_md/components/song_json.dart' show Modes;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Always reachable in debug and profile builds; in a release, once four
/// quick taps on Profile's flare rank unlock them.
final developmentToolsEnabled = ValueNotifier(
    !kReleaseMode || Settings.getInt(Settings.developmentToolsKey) == 1);

/// Unlocks the development tools in a release, or locks them again.
Future<void> toggleDevelopmentTools(BuildContext context) async {
  final on = Settings.getInt(Settings.developmentToolsKey) != 1;
  await Settings.setInt(Settings.developmentToolsKey, on ? 1 : 0);
  developmentToolsEnabled.value = !kReleaseMode || on;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            on ? 'Development tools unlocked' : 'Development tools locked')));
  }
}

/// A way into [DevelopmentPage], while [developmentToolsEnabled].
class DevelopmentToolsTile extends StatelessWidget {
  const DevelopmentToolsTile({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
      valueListenable: developmentToolsEnabled,
      builder: (context, on, _) => !on
          ? const SizedBox.shrink()
          : Card(
              child: ListTile(
              leading: const Icon(Icons.developer_mode),
              title: const Text('Development'),
              subtitle:
                  const Text('Session wrap, seeded scores and card effects'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DevelopmentPage())),
            )));
}

const _previewCards = 12;

/// Home's wrap banner held up for testing: it stays on its session's real
/// wrap, however often it's opened.
final wrapBannerPreview =
    ValueNotifier(Settings.getInt(Settings.wrapBannerPreviewKey) == 1);

/// Opens the wrap of the latest session with plays, cheers from a made-up
/// circle on its credits, and its gains made up from
/// its charts' bests in turn: a new card, AAA's foil, a frame one tier up and
/// a flare one rank up, each where the best allows, from a few thousand
/// points lower. A dozen cards, topped
/// up from the player's other bests when the session has fewer charts.
Future<void> previewSessionWrap(BuildContext context) async {
  final data = await loadVisits(context.read<SessionState>().session?.id);
  final visit = data.visits
      .where((v) => v.session != null && v.plays.isNotEmpty)
      .firstOrNull;
  if (!context.mounted) return;
  if (visit == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No session with synced plays')));
    return;
  }
  const lamps = [ClearLamp.clear, ClearLamp.fc, ClearLamp.gfc, ClearLamp.pfc];
  // The session's charts, then the player's other bests in its first style,
  // until there are a dozen.
  final mode = visit.plays.last.mode;
  await ChartBests.ensure(mode);
  final charts = <(String, Modes, String), ChartBest>{};
  for (final p in visit.plays.reversed) {
    final song = p.song;
    if (song == null || charts.containsKey((song, p.mode, p.difficulty))) {
      continue;
    }
    await ChartBests.ensure(p.mode);
    charts[(song, p.mode, p.difficulty)] =
        ChartBests.forChart(song, p.mode, p.difficulty) ??
            (score: p.score, grade: null, lamp: null, flare: null);
  }
  for (final MapEntry(key: song, value: bests)
      in ChartBests.bestsOf(mode).entries) {
    for (final MapEntry(key: difficulty, value: best) in bests.entries) {
      if (charts.length >= _previewCards) break;
      charts.putIfAbsent((song, mode, difficulty), () => best);
    }
  }
  final gains = <CardGain>[];
  for (final MapEntry(key: (song, mode, difficulty), value: best)
      in charts.entries.take(_previewCards)) {
    CardGain gain(CardLayer layer, [String from = '', String to = '']) =>
        CardGain(
            song: song,
            mode: mode,
            difficulty: difficulty,
            layer: layer,
            from: from,
            to: to,
            fromScore: layer == CardLayer.card || best.score == null
                ? null
                : best.score! - 4210 * (1 + gains.length % 3),
            best: best,
            playedAt: visit.plays.first.playedAt,
            syncedAt: DateTime.now());
    final tier = cardFrameTier(best.lamp);
    final flare = kFlareRanks.indexOf(best.flare ?? '');
    gains.add(switch (gains.length % 4) {
      1 when best.grade == Grade.aaa =>
        gain(CardLayer.finish, Grade.aaPlus.label, Grade.aaa.label),
      2 when tier > 0 =>
        gain(CardLayer.frame, lamps[tier - 1].name, best.lamp!.name),
      3 when flare > 0 =>
        gain(CardLayer.aura, kFlareRanks[flare - 1], best.flare!),
      _ => gain(CardLayer.card),
    });
  }
  // A circle that cheered three credits, a friend or two each.
  const cheerers = ['MIKA', 'REXX', 'TOFU', 'JUN.K'];
  final cheered = [
    for (var c = 1; c <= 3; c++)
      (
        by: null,
        session: visit.session!.id,
        credit: c,
        at: visit.plays.first.playedAt,
        plays: const <CirclePlay>[],
        cheers: [
          for (var i = 0; i < 1 + c % 2; i++)
            (
              id: null,
              name: cheerers[(c + i) % cheerers.length],
              cheer: Cheer.values[(c * 2 + i) % Cheer.values.length],
            )
        ],
        mine: null,
      )
  ];
  if (!context.mounted) return;
  await showSessionWrap(context,
      visit: visit,
      summary: data.model.summarize(visit.plays),
      gains: gains,
      cheered: cheered);
}

class DevelopmentPage extends StatefulWidget {
  const DevelopmentPage({super.key});
  @override
  State<DevelopmentPage> createState() => _DevelopmentPageState();
}

class _DevelopmentPageState extends State<DevelopmentPage> {
  final _fixtures = EditionFixtureSpace();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Development')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
          children: [
            Card(
                child: ListTile(
                    leading: const Icon(Icons.style_outlined),
                    title: const Text('Session wrap preview'),
                    subtitle: const Text(
                        'Your last session with made-up cheers and card gains, nothing saved'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => previewSessionWrap(context))),
            Card(
                child: ValueListenableBuilder(
                    valueListenable: wrapBannerPreview,
                    builder: (context, on, _) => SwitchListTile(
                        secondary: const Icon(Icons.flag_outlined),
                        title: const Text('Session wrap banner'),
                        subtitle: const Text(
                            'Keep Home\'s banner up on your last session\'s real wrap'),
                        value: on,
                        onChanged: (v) async {
                          await Settings.setInt(
                              Settings.wrapBannerPreviewKey, v ? 1 : 0);
                          wrapBannerPreview.value = v;
                        }))),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('Seeded score combinations'),
                    subtitle: Text(
                        '${_fixtures.count} combinations • isolated test database'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionFixtureBrowser())))),
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'Preview tools are always available in development builds. The fixture database is separate from your scores and is never synced.')),
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(editionDevelopmentEnabled
                        ? 'Experimental jacket rendering is enabled for song zoom.'
                        : 'Song zoom uses the plain jacket until performance rollout gates pass.'))),
            Card(
                child: Column(children: [
              for (final (label, key) in [
                ('Jacket effects', Settings.jacketEffectsOffKey),
                ('Jacket motion', Settings.jacketMotionOffKey),
              ])
                SwitchListTile(
                    title: Text(label),
                    value: Settings.getInt(key) == 0,
                    onChanged: (v) async {
                      await Settings.setInt(key, v ? 0 : 1);
                      if (mounted) setState(() {});
                    }),
              SwitchListTile(
                  title: const Text('Flare gauge'),
                  subtitle: const Text(
                      'Show the flare aura as a gauge round the card instead of flames'),
                  value: Settings.getInt(Settings.jacketFlareGaugeKey) == 1,
                  onChanged: (v) async {
                    await Settings.setInt(
                        Settings.jacketFlareGaugeKey, v ? 1 : 0);
                    if (mounted) setState(() {});
                  }),
              ListTile(
                  title: const Text('Wrap card landing'),
                  trailing: DropdownButton<PackLanding>(
                      value: PackLanding.current,
                      onChanged: (v) async {
                        await Settings.setInt(
                            Settings.wrapLandingKey, v!.index);
                        if (mounted) setState(() {});
                      },
                      items: [
                        for (final l in PackLanding.values)
                          DropdownMenuItem(value: l, child: Text(l.label)),
                      ])),
            ])),
          ]));
}
