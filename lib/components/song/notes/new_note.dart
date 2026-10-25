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
import 'package:ddr_md/theme.dart';
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
    final pop = FloorPop.of(context);
    final editing = widget.getNotes != null && widget.id != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.id == null ? 'New note' : 'Edit note',
                style: Theme.of(context).textTheme.titleLarge),
            if (widget.createdAt != null)
              Text(formatDate(DateTime.parse(widget.createdAt!)),
                  style: TextStyle(fontSize: 12, color: pop.haze)),
            const SizedBox(height: 12),
            TextField(
              controller: noteTextController,
              autofocus: widget.id == null,
              onChanged: (value) {
                setState(() {
                  _contents = value;
                });
              },
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  hintText: 'What to remember about this chart…'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (editing) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: pop.down),
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await DatabaseProvider.deleteNote(widget.id!);
                      if (!context.mounted) return;
                      Navigator.pop(context, true);
                      widget.getNotes!(
                          songState.songInfo!.titletranslit, songState.modes);
                      showToast(context, "Note deleted.");
                    },
                    child: const Icon(Icons.delete_outline),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _contents.trim().isEmpty
                        ? null
                        : () async {
                            HapticFeedback.lightImpact();
                            if (widget.id != null) {
                              await DatabaseProvider.updateNote(
                                  Note(
                                      id: widget.id!,
                                      createdAt: widget.createdAt!,
                                      contents: _contents,
                                      songTitle:
                                          songState.songInfo!.titletranslit,
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
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
