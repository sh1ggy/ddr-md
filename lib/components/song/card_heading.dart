/// Name: CardHeading
/// Parent: SongPage cards
/// Description: A song page card's title with its icon, so the cards tell
/// apart at a glance.
library;

import 'package:flutter/material.dart';

class CardHeading extends StatelessWidget {
  const CardHeading(this.text, {super.key, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      );
}
