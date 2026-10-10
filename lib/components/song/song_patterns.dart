/// Name: SongPatterns
/// Parent: SongPage
/// Description: Card summarising the chosen chart's patterns — what it is
/// known for at a glance, then footwork and rhythm.
library;

import 'package:ddr_md/components/song/card_heading.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';

/// Quantization buckets as the chart preview colours them, with every grid
/// finer than 32nds folded into green.
const _rhythmBuckets = <(String, List<String>, Color)>[
  ("4th", ["4"], QuantColors.quarter),
  ("8th", ["8"], QuantColors.eighth),
  ("12th", ["12"], QuantColors.twelfth),
  ("16th", ["16"], QuantColors.sixteenth),
  ("24th", ["24"], QuantColors.twentyfourth),
  ("32nd", ["32"], QuantColors.thirtysecond),
  ("Other", ["other"], QuantColors.other),
];

/// The same under ARCADE NOTES, where only 4ths, 8ths and 16ths keep a colour.
const _arcadeRhythmBuckets = <(String, List<String>, Color)>[
  ("4th", ["4"], QuantColors.quarter),
  ("8th", ["8"], QuantColors.eighth),
  ("16th", ["16"], QuantColors.sixteenth),
  ("Other", ["12", "24", "32", "other"], QuantColors.other),
];

class SongPatternsCard extends StatelessWidget {
  const SongPatternsCard({super.key, required this.patterns});

  final ChartPatterns patterns;

  @override
  Widget build(BuildContext context) {
    final p = patterns;
    final hint = Theme.of(context).hintColor;
    final standouts = p.standouts;
    final present = [
      for (final pattern in Pattern.values)
        if (p.counts[pattern]! > 0) pattern
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const CardHeading('Patterns', icon: Icons.insights),
          // The glanceable part: what this chart is known for, readable with
          // the card closed.
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: standouts.isEmpty
                ? Text('Nothing unusual for its level',
                    style: TextStyle(fontSize: 12, color: hint))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final pattern in standouts)
                        _Tag(pattern, p.counts[pattern]!),
                    ],
                  ),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (present.isNotEmpty) ...[
              const _Heading('Footwork', top: 0),
              for (final pattern in present)
                _PatternRow(
                  pattern: pattern,
                  detail: _detail(p, pattern),
                  count: p.counts[pattern]!,
                  percentile: p.percentiles[pattern.name] ?? 0,
                  standout: standouts.contains(pattern),
                ),
            ],
            const _Heading('Rhythm'),
            _RhythmBar(quantization: p.rhythm),
          ],
        ),
      ),
    );
  }
}

String? _detail(ChartPatterns p, Pattern pattern) => switch (pattern) {
      Pattern.crossover when p.fullCrossovers > 0 => '${p.fullCrossovers} full',
      Pattern.footswitch =>
        '${p.upFootswitches} up · ${p.downFootswitches} down',
      _ => null,
    };

class _Tag extends StatelessWidget {
  const _Tag(this.pattern, this.count);

  final Pattern pattern;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kPatternIcons[pattern], size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${kPatternLabels[pattern]} ×$count',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// A pattern's count, its bar the chart's percentile within its level.
class _PatternRow extends StatelessWidget {
  const _PatternRow({
    required this.pattern,
    required this.detail,
    required this.count,
    required this.percentile,
    required this.standout,
  });

  final Pattern pattern;
  final String? detail;
  final int count;
  final int percentile;
  final bool standout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = standout ? theme.colorScheme.primary : theme.hintColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(kPatternIcons[pattern], size: 18, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kPatternLabels[pattern]!),
                if (detail != null)
                  Text(detail!,
                      style: TextStyle(fontSize: 11, color: theme.hintColor)),
              ],
            ),
          ),
          Expanded(
            child: Tooltip(
              message: 'More per step than $percentile% of charts at its level',
              triggerMode: TooltipTriggerMode.tap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: percentile / 100,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.top = 16});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

/// Share of arrows on each beat grid, as one stacked bar plus a legend, in the
/// note colours the chart preview draws them in.
class _RhythmBar extends StatelessWidget {
  const _RhythmBar({required this.quantization});

  final Map<String, int> quantization;

  @override
  Widget build(BuildContext context) {
    final arcade = Settings.getInt(Settings.arcadeQuantOnKey) == 1;
    final buckets = [
      for (final (label, keys, color)
          in arcade ? _arcadeRhythmBuckets : _rhythmBuckets)
        (label, keys.fold(0, (s, k) => s + (quantization[k] ?? 0)), color),
    ].where((b) => b.$2 > 0).toList();
    final total = buckets.fold(0, (s, b) => s + b.$2);
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final (_, count, color) in buckets)
                  Expanded(flex: count, child: ColoredBox(color: color)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, count, color) in buckets)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$label ${_percent(count, total)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeData.estimateBrightnessForColor(color) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Rounded, but never "0%" for a grid that does appear.
String _percent(int count, int total) {
  final pct = count * 100 / total;
  return pct < 1 ? '<1%' : '${pct.round()}%';
}
