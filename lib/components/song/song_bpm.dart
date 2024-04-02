import 'package:ddr_md/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SongBpmTextItem extends StatelessWidget {
  const SongBpmTextItem(
      {super.key,
      required this.text,
      required this.nearestModIndex,
      required this.e});

  final String text;
  final int nearestModIndex;
  final double e;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<AppState>();
    return SizedBox(
      width: 50,
      child: Text(text,
          style: TextStyle(
              color: nearestModIndex == appState.mods.indexOf(e)
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyMedium?.color)),
    );
  }
}
