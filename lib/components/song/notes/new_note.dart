/// Name: NewNoteField
/// Parent: NotesTab
/// Description: Widget that is contained in the BottomSheet called in
/// the parent for new notes, saving them to the database.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class NewNoteField extends StatefulWidget {
  const NewNoteField({
    super.key,
    this.contentsInit = "",
    this.id,
    this.createdAt,
    this.getNotes,
  });

  final String? contentsInit;
  // Identity of the note being edited; null when composing a new note.
  final String? id;
  // Creation timestamp of the note being edited, shown at the top.
  final String? createdAt;
  final void Function(String, Modes)? getNotes;

  @override
  State<NewNoteField> createState() => NewNoteFieldState();
}

class NewNoteFieldState extends State<NewNoteField> {
  var noteTextController = TextEditingController();

  String _contents = "";

  @override
  void initState() {
    super.initState();
    if (widget.contentsInit != null) {
      _contents = widget.contentsInit!;
      noteTextController.text = _contents;
      return;
    }
    _contents = "";
    return;
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: 300,
        child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.createdAt != null)
                  Text(formatDate(DateTime.parse(widget.createdAt!)),
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: TextField(
                    controller: noteTextController,
                    onChanged: (value) {
                      setState(() {
                        _contents = value;
                      });
                    },
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        hintText: _contents == ""
                            ? 'Enter new note here...'
                            : _contents,
                        hintStyle: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.color)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.getNotes != null && widget.id != null)
                      IconButton(
                        icon: const Icon(Icons.delete_forever),
                        color: Colors.redAccent,
                        tooltip: "Delete note",
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          await DatabaseProvider.deleteNote(widget.id!);
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                          widget.getNotes!(
                              songState.songInfo!.titletranslit,
                              songState.modes);
                          showToast(context, "Note deleted.");
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.save),
                      color: Colors.green,
                      tooltip: "Save note",
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        if (widget.id != null) {
                          await DatabaseProvider.updateNote(
                              Note(
                                  id: widget.id!,
                                  createdAt: widget.createdAt!,
                                  contents: _contents,
                                  songTitle: songState.songInfo!.titletranslit,
                                  mode: songState.modes),
                              _contents);
                        } else {
                          await DatabaseProvider.addNote(Note(
                              createdAt: DateTime.now().toIso8601String(),
                              contents: _contents,
                              songTitle: songState.songInfo!.titletranslit,
                              mode: songState.modes));
                        }
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                        showToast(context, "Note saved.");
                      },
                    ),
                  ],
                ),
              ]),
        ),
      ),
    );
  }
}
