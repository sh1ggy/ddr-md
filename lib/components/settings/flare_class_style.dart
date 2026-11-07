/// Name: FlareClassStyle
/// Parent: ScoreOverviewPage, EamuseProfileCard
/// Description: How a flare skill class looks wherever it's shown: its colour,
/// each sub-rank a clear step stronger, and WORLD in EX's rainbow.
library;

import 'dart:math';

import 'package:ddr_md/grades.dart';
import 'package:flutter/material.dart';

const kFlareRainbow = LinearGradient(colors: kFlareExColors);

/// How many plusses a class name carries, 0 to 3.
int flareSubRank(String name) => name.length - name.replaceAll('+', '').length;

/// How strongly a class's colour shows, stepping up with its sub-rank.
double flareSubRankStrength(String name) => 0.25 + 0.25 * flareSubRank(name);

bool isWorldClass(String name) => name == 'WORLD';

/// Paints [child] in the rainbow at WORLD, and leaves it alone otherwise.
class FlareClassPaint extends StatelessWidget {
  const FlareClassPaint(this.name, {super.key, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => isWorldClass(name)
      ? ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: kFlareRainbow.createShader,
          child: child)
      : child;
}

/// A card surface in the class's colours: a wash, a frame and a glow that all
/// strengthen with the sub-rank.
BoxDecoration flareClassSurface(String name,
    {required Color base, required BorderRadius radius}) {
  final strength = flareSubRankStrength(name);
  if (isWorldClass(name)) {
    return BoxDecoration(
      borderRadius: radius,
      gradient: LinearGradient(
          colors: [for (final c in kFlareExColors) Color.lerp(base, c, 0.28)!]),
      border: Border.all(color: Colors.transparent, width: 1.5),
      boxShadow: [
        for (final (i, c) in kFlareExColors.indexed)
          BoxShadow(
              color: c.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: Offset.fromDirection(i * pi / 3, 4))
      ],
    );
  }
  final color = flareClassColor(name);
  return BoxDecoration(
    borderRadius: radius,
    gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(base, color, 0.1 + 0.3 * strength)!, base]),
    border: Border.all(color: color.withValues(alpha: strength), width: 1.5),
    boxShadow: [
      BoxShadow(
          color: color.withValues(alpha: 0.35 * strength),
          blurRadius: 4 + 14 * strength)
    ],
  );
}

/// The class's art in a fixed square, with a glow growing with the sub-rank.
class FlareClassArt extends StatelessWidget {
  const FlareClassArt(this.name, {super.key, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = flareClassColor(name);
    final strength = flareSubRankStrength(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: isWorldClass(name)
              ? [
                  for (final (i, c) in kFlareExColors.indexed)
                    BoxShadow(
                        color: c.withValues(alpha: 0.5),
                        blurRadius: size * 0.35,
                        offset: Offset.fromDirection(i * pi / 3, size * 0.12))
                ]
              : [
                  BoxShadow(
                      color: color.withValues(alpha: strength),
                      blurRadius: size * (0.1 + 0.4 * strength))
                ]),
      child: Image.asset(flareClassIcon(name),
          fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }
}

/// The class's name with three plus slots, those earned lit and the rest
/// faint, so its sub-rank reads at a glance and the width never changes.
class FlareClassName extends StatelessWidget {
  const FlareClassName(this.name, {super.key, this.fontSize = 13});

  final String name;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = flareClassColor(name);
    final style = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
        color: color);
    final sub = flareSubRank(name);
    return FlareClassPaint(
      name,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(name.replaceAll('+', ''), style: style),
        if (!isWorldClass(name)) ...[
          SizedBox(width: fontSize / 3),
          for (var i = 0; i < 3; i++)
            Text('+',
                style: style.copyWith(
                    fontSize: fontSize * 1.25,
                    height: 1,
                    letterSpacing: 0,
                    color: i < sub ? color : color.withValues(alpha: 0.2))),
        ],
      ]),
    );
  }
}
