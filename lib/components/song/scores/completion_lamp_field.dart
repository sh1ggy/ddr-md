/// Name: CompletionLampField
/// Parent: SaveScorePanel, ScoreDetailsPage
/// Description: Explicit per-play completion evidence, never inferred from OCR.
library;

import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';

class CompletionLampField extends StatelessWidget {
  const CompletionLampField(
      {super.key, required this.value, required this.onChanged});
  final ClearLamp? value;
  final ValueChanged<ClearLamp?>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: value?.name ?? '',
        decoration: const InputDecoration(
          labelText: 'Confirmed result of this play',
          helperText: 'Include holds/shocks. Leave unknown unless verified.',
          helperMaxLines: 2,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Unknown')),
          for (final lamp in ClearLamp.values)
            DropdownMenuItem(
                value: lamp.name, child: Text(lamp.name.toUpperCase())),
        ],
        onChanged: onChanged == null
            ? null
            : (v) => onChanged!(ClearLamp.values.asNameMap()[v]),
      );
}
