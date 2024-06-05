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
  });

  final String? contentsInit;
  final String? date;

  @override
  State<NewNoteField> createState() => NewNoteFieldState();
}

class NewNoteFieldState extends State<NewNoteField> {
  String _contents = "";

  @override
  void initState() {
    super.initState();
    if (widget.contentsInit != null) {
      _contents = widget.contentsInit!;
      return;
    }
    _contents = "";
    return;
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return Container(
      padding: const EdgeInsets.all(15),
      width: MediaQuery.of(context).size.width,
      child: SizedBox(
        height: 200,
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
                    onChanged: (value) {
                      setState(() {
                        _contents = value;
                      });
                    },
                    maxLines: 3,
                    keyboardType: TextInputType.text,
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
                IconButton(
                  icon: const Icon(Icons.save),
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
                    if (context.mounted) {
                      Navigator.pop(context, true);
                      showToast(context, "Note saved.");
                    }
                  },
                ),
              ]),
        ),
      ),
    );
  }
}
