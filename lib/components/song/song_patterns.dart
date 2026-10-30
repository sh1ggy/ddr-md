/// Name: SongPatterns
/// Parent: SongPage
/// Description: Card summarising the chosen chart's patterns — what it is
/// known for at a glance, then footwork and rhythm.
library;

import 'dart:convert';

import 'package:ddr_md/components/settings/chart_categories_page.dart';
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

/// The same without QUANT COLORS, where only 4ths, 8ths and 16ths keep a colour.
const _arcadeRhythmBuckets = <(String, List<String>, Color)>[
  ("4th", ["4"], QuantColors.quarter),
  ("8th", ["8"], QuantColors.eighth),
  ("16th", ["16"], QuantColors.sixteenth),
  ("Other", ["12", "24", "32", "other"], QuantColors.other),
];

class SongPatternsCard extends StatefulWidget {
  const SongPatternsCard(
      {super.key, required this.patterns, required this.chartKey});

  final ChartPatterns patterns;

  /// Where the player's own category for this chart is kept, see
  /// [Settings.chartCategoriesKey].
  final String chartKey;

  @override
  State<SongPatternsCard> createState() => _SongPatternsCardState();
}

class _SongPatternsCardState extends State<SongPatternsCard> {
  /// The category can only be changed with the card open, so a tap on the
  /// closed card can't change it by accident.
  bool _expanded = false;

  Map<String, dynamic> _all() {
    try {
      return json.decode(Settings.getString(Settings.chartCategoriesKey))
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  ChartCategory? get _own => switch (_all()[widget.chartKey]) {
        final String name =>
          ChartCategory.values.where((c) => c.name == name).firstOrNull,
        _ => null,
      };

  Future<void> _pick() async {
    final auto = widget.patterns.primaryCategory;
    final current = _own ?? auto;
    // Picking the suggested category drops the player's own.
    final picked = await showModalBottomSheet<ChartCategory>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(children: [
                Expanded(
                    child: Text('Chart category',
                        style: Theme.of(context).textTheme.titleLarge)),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ChartCategoriesPage())),
                  child: const Text('What they mean'),
                ),
              ]),
            ),
            for (final c in ChartCategory.values)
              ListTile(
                leading: Icon(kCategoryIcons[c]),
                title: Text(kCategoryLabels[c]!),
                subtitle: c == auto ? const Text('Suggested') : null,
                selected: c == current,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final all = _all();
    if (picked == auto) {
      all.remove(widget.chartKey);
    } else {
      all[widget.chartKey] = picked.name;
    }
    await Settings.setString(Settings.chartCategoriesKey, json.encode(all));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patterns;
    final own = _own;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (own ?? p.primaryCategory case final primary?)
                  InkWell(
                    onTap: _expanded ? _pick : null,
                    borderRadius: BorderRadius.circular(8),
                    child: _CategoryHeadline(
                        primary,
                        [
                          for (final c in p.secondaryCategories)
                            if (c != primary) c
                        ],
                        own: own != null,
                        editable: _expanded),
                  )
                else if (standouts.isEmpty)
                  Text('Nothing unusual for its level',
                      style: TextStyle(fontSize: 12, color: hint)),
                if (standouts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final pattern in standouts)
                        _Tag(pattern, p.counts[pattern]!),
                    ],
                  ),
                ],
              ],
            ),
          ),
          onExpansionChanged: (open) => setState(() => _expanded = open),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (present.isNotEmpty) ...[
              const _Heading('Footwork'),
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

/// The chart's lead category as an icon badge and a name, its other strong
/// categories underneath.
class _CategoryHeadline extends StatelessWidget {
  const _CategoryHeadline(this.primary, this.secondary,
      {required this.own, required this.editable});

  final ChartCategory primary;
  final List<ChartCategory> secondary;

  /// The player picked [primary] themselves.
  final bool own;

  /// Tapping it picks another, so it shows a pencil.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = Theme.of(context).hintColor;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: scheme.primary,
          child:
              Icon(kCategoryIcons[primary], size: 20, color: scheme.onPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${kCategoryLabels[primary]} chart',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (own || editable) ...[
                    const SizedBox(width: 4),
                    Icon(editable ? Icons.edit : Icons.person,
                        size: 13, color: hint),
                  ],
                ],
              ),
              if (secondary.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in secondary)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(kCategoryIcons[c], size: 13, color: hint),
                          const SizedBox(width: 3),
                          Text(kCategoryLabels[c]!,
                              style: TextStyle(fontSize: 12, color: hint)),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

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
    // Fixed height so a row's detail line never changes the bars' spacing.
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Icon(kPatternIcons[pattern], size: 18, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
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
    final arcade = Settings.getInt(Settings.quantColorsOnKey) == 0;
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
