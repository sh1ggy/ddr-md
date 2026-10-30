/// Name: DevelopmentPage
/// Parent: AppSettingsPage, SettingsPage
/// Description: Persistent debug/profile tools, isolated fixtures and previews.
library;

import 'package:ddr_md/components/session/session_wrap.dart';
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_guide.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_lab_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_browser.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_store.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Always reachable in debug and profile builds; absent from release UI.
const developmentToolsEnabled = !kReleaseMode;

class DevelopmentToolsTile extends StatelessWidget {
  const DevelopmentToolsTile({super.key});
  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        leading: const Icon(Icons.developer_mode),
        title: const Text('Development'),
        subtitle: const Text('Jacket lab, seeded scores and performance'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DevelopmentPage())),
      ));
}

/// Opens the wrap of the latest session with plays, its gains made up from
/// its charts' bests in turn: a new card, AAA's foil, a frame one tier up and
/// a flare one rank up, each where the best allows.
Future<void> _previewWrap(BuildContext context) async {
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
  final seen = <Object>{};
  final gains = <CardGain>[];
  for (final p in visit.plays.reversed) {
    final song = p.song;
    if (song == null || !seen.add((song, p.mode, p.difficulty))) continue;
    await ChartBests.ensure(p.mode);
    final best = ChartBests.forChart(song, p.mode, p.difficulty) ??
        (score: p.score, grade: null, lamp: null, flare: null);
    CardGain gain(CardLayer layer, [String from = '', String to = '']) =>
        CardGain(
            song: song,
            mode: p.mode,
            difficulty: p.difficulty,
            layer: layer,
            from: from,
            to: to,
            best: best,
            playedAt: p.playedAt,
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
    if (gains.length == 6) break;
  }
  if (!context.mounted) return;
  await showSessionWrap(context,
      visit: visit, summary: data.model.summarize(visit.plays), gains: gains);
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
                    leading: const Icon(Icons.collections_bookmark_outlined),
                    title: const Text('Binder'),
                    subtitle: const Text('Your cards, filed by level'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionBinderPage())))),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.style_outlined),
                    title: const Text('Session wrap preview'),
                    subtitle: const Text(
                        'Your last session with made-up card gains, nothing saved'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _previewWrap(context))),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Session wrap banner'),
                    subtitle: const Text(
                        'Show Home\'s banner for your last session, as after a sync'),
                    onTap: () async {
                      await Settings.setString(Settings.sessionWrapSinceKey,
                          DateTime.utc(2000).toIso8601String());
                      if (!context.mounted) return;
                      // Home rereads its sessions, as after a sync.
                      await context.read<EamuseSyncState>().reloadSaved();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Banner on: go to Home')));
                    })),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: const Text('Card lab'),
                    subtitle: const Text(
                        'Each layer of a card and what earns it; try any result'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionGuidePage())))),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('Seeded score combinations'),
                    subtitle: Text(
                        '${_fixtures.count} combinations • isolated test database'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionFixtureBrowser())))),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.speed_outlined),
                    title: const Text('Frame timing lab'),
                    subtitle:
                        const Text('Measure the card renderer\'s frame times'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionLabPage())))),
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'Preview tools are always available in development builds. The fixture database is separate from your scores and is never synced.')),
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(editionDevelopmentEnabled
                        ? 'Experimental jacket rendering is enabled for song zoom.'
                        : 'Song zoom uses the plain jacket until performance rollout gates pass. The lab previews every material independently.'))),
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
            ])),
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'Measure phone frame timings in profile or release mode. Debug timings and desktop previews do not establish mobile performance.')),
          ]));
}
