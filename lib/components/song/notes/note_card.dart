/// Name: NoteCard
/// Parent: NotePage
/// Description: Card to display note information from DB, with
/// differing action based on the params
library;

import 'package:ddr_md/components/song/notes/new_note.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
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
          context: context,
          builder: (BuildContext context) {
            return NewNoteField(contentsInit: contents, date: date);
          },
        );
        // If return is the expected value, execute getNotes and re-render
        if (result == true) {
          getNotes(songState.songInfo!.titletranslit);
        }
      },
      child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Card(
            shadowColor: Colors.black,
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDate(DateTime.parse(date)),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(contents),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever),
                    tooltip: "Delete note",
                    onPressed: () async {
                      await DatabaseProvider.deleteNote(date);
                      if (!context.mounted) return;
                      getNotes(songState.songInfo!.titletranslit);
                      showToast(context, "Note deleted.");
                    },
                  )
                ],
              ),
            ),
          )),
    );
  }
}
