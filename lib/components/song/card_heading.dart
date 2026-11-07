/// Name: CardHeading
/// Parent: SongPage cards, Home cards
/// Description: A song page card's title with its icon, so the cards tell
/// apart at a glance.
library;

import 'package:flutter/material.dart';

class CardHeading extends StatelessWidget {
  const CardHeading(this.text,
      {super.key, required this.icon, this.iconColor, this.iconGradient});

  final String text;
  final IconData icon;
  final Color? iconColor;

  /// Paints the icon instead of [iconColor].
  final Gradient? iconGradient;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconGradient == null
              ? Icon(icon,
                  size: 20,
                  color: iconColor ?? Theme.of(context).colorScheme.primary)
              : ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: iconGradient!.createShader,
                  child: Icon(icon, size: 20, color: Colors.white)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      );
}
