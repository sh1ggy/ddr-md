/// Name: FootingStylePage
/// Parent: SettingsPage
/// Description: Ours vs Yours. Yours is learned from the feet set by hand in
/// the chart preview's footing editor; this page re-fits it and shows, per
/// edited chart, how many of those feet each style places on its own, plus how
/// often the flagged patterns come up under each.
library;

import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/parity_labels.dart';
import 'package:ddr_md/models/parity_profile.dart';
import 'package:flutter/material.dart';

/// Ours (the shipped footing) or Yours (learned from your edits); Yours stays
/// disabled until there's a fit to use.
class FootingStyleSwitch extends StatelessWidget {
  const FootingStyleSwitch({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        const ButtonSegment(value: false, label: Text('Ours')),
        ButtonSegment(
            value: true,
            label: const Text('Yours'),
            enabled: ParityProfile.yours != null),
      ],
      selected: {ParityProfile.usingYours},
      onSelectionChanged: (s) {
        ParityProfile.usingYours = s.first;
        onChanged?.call();
      },
    );
  }
}

class FootingStylePage extends StatefulWidget {
  const FootingStylePage({super.key});

  @override
  State<FootingStylePage> createState() => _FootingStylePageState();
}

class _FootingStylePageState extends State<FootingStylePage> {
  late final Future<FootingFit?> _fit = refitFromEdits();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Footing Style',
            style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      body: FutureBuilder<FootingFit?>(
        future: _fit,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final fit = snapshot.data;
          if (fit == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Fix footing in a chart preview to start teaching Yours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ),
            );
          }
          return _buildTable(fit);
        },
      ),
    );
  }

  Widget _buildTable(FootingFit fit) {
    final yours = ParityProfile.usingYours;
    final r = fit.result;
    final total = fit.pinCounts.fold(0, (a, b) => a + b);
    const dim = TextStyle(color: Colors.blueGrey, fontSize: 13);
    const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    // Two columns throughout, the one in use tinted.
    Widget row(Widget label, Widget ours, Widget mine) {
      Widget cell(Widget child, bool active) => Container(
            width: 72,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: active ? Colors.white.withValues(alpha: 0.05) : null,
            child: child,
          );
      return Row(children: [
        Expanded(child: label),
        cell(ours, !yours),
        cell(mine, yours),
      ]);
    }

    Text n(Object v, {bool big = false}) => Text('$v',
        style: big
            ? const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)
            : tabular);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          row(
            const SizedBox(),
            const Text('Ours', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Yours', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          row(
            const Text('Your edits it gets right'),
            n('${r.before.fold(0, (a, b) => a + b)}/$total', big: true),
            n('${r.after.fold(0, (a, b) => a + b)}/$total', big: true),
          ),
          for (int i = 0; i < fit.charts.length; i++)
            row(
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${fit.charts[i].song}  '),
                    TextSpan(
                        text: kInGameDifficultyNames[fit.charts[i].difficulty] ??
                            fit.charts[i].difficulty,
                        style: TextStyle(
                            color: difficultyColor(fit.charts[i].difficulty),
                            fontWeight: FontWeight.w800)),
                  ]),
                  style: dim,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              n('${r.before[i]}/${fit.pinCounts[i]}'),
              n('${r.after[i]}/${fit.pinCounts[i]}'),
            ),
          const SizedBox(height: 16),
          const Text('Across these charts', style: dim),
          for (final (flag, label) in const [
            (ParityFlag.doublestep, 'Doublesteps'),
            (ParityFlag.crossover, 'Crossovers'),
            (ParityFlag.footswitch, 'Footswitches'),
            (ParityFlag.samePanel, 'Both feet on one arrow'),
          ])
            row(Text(label), n(fit.countsOurs[flag] ?? 0),
                n(fit.countsYours[flag] ?? 0)),
          const SizedBox(height: 20),
          Center(child: FootingStyleSwitch(onChanged: () => setState(() {}))),
        ],
      ),
    );
  }
}
