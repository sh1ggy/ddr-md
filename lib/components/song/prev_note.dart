/// Name: PrevNote
/// Parent: SongPage
/// Description: Widget that displays the most recent note
/// as well as your most recent score.
library;

import 'package:ddr_md/components/song/note_page.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;

class PrevNote extends StatelessWidget {
  const PrevNote({super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Container(
          padding: const EdgeInsets.all(15.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const NotePage())),
                      child: const Text("Previous Note",
                          style: TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(
                      child: Text(constants.note,
                          softWrap: true,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const NoteScore(),
            ].expand((x) => [const SizedBox(width: 20), x]).skip(1).toList(),
          ),
        ),
      );
}

class NoteScore extends StatelessWidget {
  const NoteScore({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          Text(
            "Recent Score:",
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image(
                  image: AssetImage('assets/rank_s_aaa.png'),
                ),
                Image(
                  image: AssetImage('assets/full_mar.png'),
                ),
              ],
            ),
          ),
          Text(
            '1,000,000',
            style: TextStyle(fontFamily: 'Handel'),
          ),
        ],
      );
}
