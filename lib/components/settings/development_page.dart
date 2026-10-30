/// Name: DevelopmentPage
/// Parent: AppSettingsPage, SettingsPage
/// Description: Persistent debug/profile tools, isolated fixtures and previews.
library;

import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_lab_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_browser.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_store.dart';
import 'package:ddr_md/components/songlist/generated_jacket.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
                    title: const Text('Jacket edition lab'),
                    subtitle: const Text(
                        'Real jackets, material controls, native stamps and frame timings'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionLabPage())))),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('Seeded score combinations'),
                    subtitle: Text(
                        '${_fixtures.count} combinations • isolated test database'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionFixtureBrowser(
                            artwork: GeneratedJacket(
                                songName: 'edition-dev-fixture',
                                title: 'EDITION LAB')))))),
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
                ('Play style stamp', Settings.jacketModeOffKey),
                ('Grade stamp', Settings.jacketGradeOffKey),
                ('Difficulty stamp', Settings.jacketDifficultyOffKey),
                ('Optical tier suffix', Settings.jacketTierOffKey),
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
