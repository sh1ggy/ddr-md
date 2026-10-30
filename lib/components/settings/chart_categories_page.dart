/// Name: ChartCategoriesPage
/// Parent: SettingsPage, SongPatternsCard
/// Description: What each chart category means, each looping the stretch of
/// the chart that leads with it most clearly (picked by
/// tool/generate_patterns.dart), chart and pad side by side.
library;

import 'dart:convert';

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/settings/footing_style_page.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _blurbs = <ChartCategory, String>{
  ChartCategory.stream: 'Long, even runs at five or more steps a second',
  ChartCategory.stamina: 'More steps than most charts of its level',
  ChartCategory.burst: 'Short spikes far busier than the rest',
  ChartCategory.jumps: 'Many rows step two arrows at once',
  ChartCategory.jack: 'Repeats on one arrow and fast two-arrow trills',
  ChartCategory.crossover: 'Feet cross to reach the far side',
  ChartCategory.footswitch: 'Feet trade places on one arrow',
  ChartCategory.bracket: 'One foot covering two arrows',
  ChartCategory.swing: 'Steps off the 4th, 8th and 16th grid',
  ChartCategory.freeze: 'Much of the chart spent holding',
  ChartCategory.gimmick: 'Speed changes and stops',
  ChartCategory.signature: 'One uncommon pattern it is known for. Yours to '
      'pick: it is never chosen for you',
  ChartCategory.balanced: 'Nothing leads: no category stands clear of the '
      'rest for its level',
};

class ChartCategoriesPage extends StatefulWidget {
  const ChartCategoriesPage({super.key});

  @override
  State<ChartCategoriesPage> createState() => _ChartCategoriesPageState();
}

class _ChartCategoriesPageState extends State<ChartCategoriesPage>
    with SingleTickerProviderStateMixin {
  List<ChartMoment>? _moments;

  late final Ticker _ticker = createTicker((elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    for (final m in _moments ?? const <ChartMoment>[]) {
      m.tick(t);
    }
  });

  @override
  void initState() {
    super.initState();
    SpriteNoteskin.tryLoad().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final levels =
        json.decode(await ContentStore.loadString('assets/pattern_levels.json'))
            as Map;
    final moments = <ChartMoment>[];
    for (final e in levels['examples'] as List? ?? const []) {
      final c = ChartCategory.values
          .where((c) => c.name == e['category'])
          .firstOrNull;
      final notes = (await StepsLoader.load(e['song'] as String))
          ?.chartFor(Modes.singles, e['difficulty'] as String)
          ?.notes;
      if (c == null || notes == null) continue;
      final from = (e['from'] as num).toDouble();
      final to = (e['to'] as num).toDouble();
      moments.add(ChartMoment(kCategoryLabels[c]!, e['song'] as String,
          e['difficulty'] as String, from, from, to, notes,
          icon: kCategoryIcons[c], blurb: _blurbs[c]));
    }
    await solveMoments(moments);
    if (!mounted) return;
    setState(() => _moments = moments);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final m in _moments ?? const <ChartMoment>[]) {
      m.playhead.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moments = _moments;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: const Text('Chart Categories'),
      ),
      body: moments == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) => ListView(
                padding: clearOfBars(context, const EdgeInsets.all(8)),
                children: [
                  for (final m in moments)
                    MomentCard(m, onTap: () => openMomentChart(context, m)),
                  for (final c in [
                    ChartCategory.signature,
                    ChartCategory.balanced
                  ])
                    Card(
                      child: ListTile(
                        leading: Icon(kCategoryIcons[c]),
                        title: Text(kCategoryLabels[c]!,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(_blurbs[c]!),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
