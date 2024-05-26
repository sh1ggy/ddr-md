/// Name: NotePage
/// Parent: SongPage
/// Description: Page that displays timeline of notes
/// as well as allows you to make new ones. [NewNoteField]
/// is the widget handling the new note action and is a child of
/// [NotePage]
library;

import 'package:ddr_md/components/song/notes/new_note.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NotePage extends StatefulWidget {
  const NotePage({
    super.key,
  });

  @override
  State<NotePage> createState() => NotePageState();
}

class NotePageState extends State<NotePage> {
  Future<List<Note>>? _notesPromise;
  final List<NoteCard> _noteWidgets = [];

  Future<List<Note>> getNotes(
      SongState songState, String songTitleTranslit) async {
    List<Note> notesBySong;
    notesBySong = await DatabaseProvider.getAllNotesBySong(songTitleTranslit);

    for (var note in notesBySong) {
      setState(() {
        _noteWidgets.add(NoteCard(
          contents: note.contents,
          date: note.date,
        ));
      });
    }
    return notesBySong;
  }

  @override
  void initState() {
    super.initState();
    late SongState songState;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      songState = Provider.of<SongState>(context, listen: false);
    });
    setState(() {
      _notesPromise = Future<List<Note>>(
          () => getNotes(songState, songState.songInfo!.titletranslit));
    });
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.black,
          shadowColor: Colors.black,
          elevation: 2,
          centerTitle: true,
          title: const Text(
            'Notes',
            style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600),
          ),
          iconTheme: const IconThemeData(color: Colors.blueGrey),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.red,
          child: const Icon(Icons.edit, color: Colors.white),
          onPressed: () {
            showModalBottomSheet<void>(
              context: context,
              builder: (BuildContext context) {
                return const NewNoteField();
              },
            );
          },
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // NOTES LIST
                      FutureBuilder(
                        future: _notesPromise,
                        builder: (context, snapshot) {
                          List<Widget> children;
                          if (snapshot.hasData) {
                            if (snapshot.data!.isEmpty) {
                              return SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height / 1.5,
                                  child: const Center(
                                      child: Text('No notes...')));
                            }
                            children =
                                snapshot.data!.map<NoteCard>((Note note) {
                              return NoteCard(
                                contents: note.contents,
                                date: note.date,
                              );
                            }).toList();
                          } else {
                            children = [];
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            children: children,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.contents,
    required this.date,
  });

  final String contents;
  final String date;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (BuildContext context) {
            return NewNoteField(
              contentsInit: contents,
              date: date,
            );
          },
        );
      },
      child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Card(
            shadowColor: Colors.black,
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date,
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
