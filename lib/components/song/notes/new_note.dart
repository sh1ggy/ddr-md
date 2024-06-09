/// Name: NewNoteField
/// Parent: NotePage
/// Description: Widget that is contained in the BottomSheet called in
/// the parent for new notes, saving them to the database.
library;

import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NewNoteField extends StatefulWidget {
  const NewNoteField({
    super.key,
    this.contentsInit = "",
    this.date,
    this.getNotes,
  });

  final String? contentsInit;
  final String? date;
  final void Function(String)? getNotes;

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
    return Container(
      padding: const EdgeInsets.all(12),
      width: MediaQuery.of(context).size.width,
      child: SizedBox(
        height: 300,
        child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.date != null)
                  Text(formatDate(DateTime.parse(widget.date!)),
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
                  children: [
                    if (widget.getNotes != null && widget.date != null)
                      IconButton(
                        icon: const Icon(Icons.delete_forever),
                        color: Colors.redAccent,
                        tooltip: "Delete note",
                        onPressed: () async {
                          await DatabaseProvider.deleteNote(widget.date!);
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                          widget.getNotes!(songState.songInfo!.titletranslit);
                          showToast(context, "Note deleted.");
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.save),
                      color: Colors.green,
                      tooltip: "Save note",
                      onPressed: () async {
                        if (widget.contentsInit != "" && widget.date != null) {
                          await DatabaseProvider.updateNote(
                              Note(
                                  date: widget.date!,
                                  contents: _contents,
                                  songTitle: songState.songInfo!.titletranslit),
                              _contents);
                        } else {
                          await DatabaseProvider.addNote(Note(
                              date: DateTime.now().toIso8601String(),
                              contents: _contents,
                              songTitle: songState.songInfo!.titletranslit));
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
