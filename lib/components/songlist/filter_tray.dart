/// Name: FilterTray
/// Parent: DifficultyListPage
/// Description: The songlist's filter options for one axis, each labelled with
/// how many songs it would yield. One widget serves all three axes — the panel
/// is a mode rather than three bespoke trays — so adding an axis is a matter of
/// handing it different options.
library;

import 'package:flutter/material.dart';

/// One selectable filter option: its label and whether it is currently on.
class FilterOption {
  const FilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// A wrap of filter chips for one axis. The running match count lives once
/// above the list rather than on every chip.
class FilterTray extends StatelessWidget {
  const FilterTray({super.key, required this.options, this.compact = false});

  final List<FilterOption> options;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final option in options)
          _chip(context, option),
      ],
    );
  }

  Widget _chip(BuildContext context, FilterOption option) {
    return FilterChip(
      label: Text(option.label),
      selected: option.selected,
      showCheckmark: false,
      visualDensity:
          compact ? const VisualDensity(horizontal: -2, vertical: -2) : null,
      side: BorderSide(
        color: option.selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).dividerColor,
      ),
      onSelected: (_) => option.onTap(),
    );
  }
}
