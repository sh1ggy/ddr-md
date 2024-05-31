/// Name: NotePage
/// Parent: SongPage
/// Description: Page that displays timeline of notes
/// as well as allows you to make new ones. [NewNoteField]
/// is the widget handling the new note action and is a child of
/// [NotePage]
library;

import 'package:ddr_md/components/song/notes/new_note.dart';
import 'package:ddr_md/components/song/notes/note_card.dart';
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

  // Function to get notes by song in DB
  void getNotes(String songTitleTranslit) async {
    // Variable initialisation
    List<Note> notesBySong;
    notesBySong = await DatabaseProvider.getAllNotesBySong(songTitleTranslit);

    // Early return if notes list is empty
    if (notesBySong.isEmpty) {
      setState(() {
        _notesPromise = Future(() => notesBySong);
      });
      return;
    }

    // Loop through all relevant notes and create a list of widgets from them.
    for (var note in notesBySong) {
      setState(() {
        _noteWidgets.add(NoteCard(
          contents: note.contents,
          date: note.date,
          getNotes: getNotes,
        ));
      });
    }

    _notesPromise = Future(() => notesBySong);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      late SongState songState;
      songState = Provider.of<SongState>(context, listen: false);
      setState(() {
        getNotes(songState.songInfo!.titletranslit);
      });
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
          onPressed: () async {
            // Wait for return from modalBottomSheet
            final result = await showModalBottomSheet<bool>(
              context: context,
              builder: (BuildContext context) {
                return const NewNoteField();
              },
            );
            // If return is the expected value, execute getNotes and re-render
            if (result == true) {
              setState(() {
                getNotes(songState.songInfo!.titletranslit);
              });
            }
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
                          List<Widget> noteWidgets;
                          if (snapshot.hasData) {
                            if (snapshot.data!.isEmpty) {
                              return SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height / 1.5,
                                  child:
                                      const Center(child: Text('No notes...')));
                            }
                            noteWidgets =
                                snapshot.data!.map<NoteCard>((Note note) {
                              return NoteCard(
                                contents: note.contents,
                                date: note.date,
                                getNotes: getNotes,
                              );
                            }).toList();
                          } else {
                            noteWidgets = [
                              SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height / 1.5,
                                  child:
                                      const Center(child: Text('Loading...'))),
                            ];
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            children: noteWidgets,
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
