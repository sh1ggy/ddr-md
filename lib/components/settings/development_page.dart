/// Name: DevelopmentPage
/// Parent: AppSettingsPage, SettingsPage
/// Description: Persistent debug/profile tools, isolated fixtures and previews.
library;

import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_guide.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_lab_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_browser.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_store.dart';
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
                    leading: const Icon(Icons.collections_bookmark_outlined),
                    title: const Text('Binder'),
                    subtitle: const Text('Your cards, filed by level'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditionBinderPage())))),
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
