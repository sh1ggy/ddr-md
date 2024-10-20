/// Name: NoteCard
/// Parent: NotePage
/// Description: Card to display note information from DB, with
/// differing action based on the params
library;

import 'package:ddr_md/components/song/notes/new_note.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.contents,
    required this.date,
    required this.getNotes,
  });

  final String contents;
  final String date;
  final void Function(String) getNotes;

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return GestureDetector(
      onTap: () async {
        // Wait for return from modalBottomSheet
        final result = await showModalBottomSheet<bool>(
          isScrollControlled: true, // for keyboard movement
          context: context,
          builder: (BuildContext context) {
            return NewNoteField(
              contentsInit: contents,
              date: date,
              getNotes: getNotes,
            );
          },
        );
        // If return is the expected value, execute getNotes and re-render
        if (result == true) {
          getNotes(songState.songInfo!.titletranslit);
        }
      },
      child: Card(
        child: ListTile(
          title: Column(
            children: [
              Text(formatDate(DateTime.parse(date)),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary)),
              Text(
                contents,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
