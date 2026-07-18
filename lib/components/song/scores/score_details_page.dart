/// Name: ScoreDetailsPage
/// Parent: ScoreCard (tapped from the scores list)
/// Description: Full view of one saved score: every recorded field plus the
/// proof image captured when it was saved (tap to inspect full screen). The
/// pencil in the app bar enters edit mode, turning the fields into inputs so
/// mistakes can be corrected against the image; the check saves the row in
/// place. List pages refresh when this route pops.
library;

import 'dart:io';

import 'package:ddr_md/components/ocr/load_image.dart'
    show FlareDropdownField, OCREditableField;
import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/score_images.dart';
import 'package:flutter/material.dart';

// Editable columns of the scores table, in card display order. Date, song,
// mode and the image stay fixed — they identify the score being corrected.
const List<String> _kEditableKeys = [
  'difficulty',
  'username',
  'flare',
  'score',
  'marvelous',
  'perfect',
  'great',
  'good',
  'miss',
  'maxCombo',
];

class ScoreDetailsPage extends StatefulWidget {
  const ScoreDetailsPage({super.key, required this.score});

  final Score score;

  @override
  State<ScoreDetailsPage> createState() => _ScoreDetailsPageState();
}

class _ScoreDetailsPageState extends State<ScoreDetailsPage> {
  late Score _score = widget.score;
  bool _editing = false;
  late final Future<File?> _imageFile = ScoreImages.resolve(_score.imagePath);
  final Map<String, TextEditingController> _controllers = {};
  // Working play date while editing; only load-image scores can change it.
  late DateTime _editPlayedAt;

  // A screenshot import has no inherent capture time, so its play date is
  // user-set and stays editable here; a camera score's date is fixed.
  bool get _dateEditable => _score.source == ScoreSource.loadImage;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fieldText(String key) {
    final value = switch (key) {
      'difficulty' => _score.difficulty,
      'username' => _score.username,
      'flare' => _score.flare,
      'score' => _score.score?.toString(),
      'marvelous' => _score.marvelous?.toString(),
      'perfect' => _score.perfect?.toString(),
      'great' => _score.great?.toString(),
      'good' => _score.good?.toString(),
      'miss' => _score.miss?.toString(),
      'maxCombo' => _score.maxCombo?.toString(),
      _ => null,
    };
    return value ?? '';
  }

  void _enterEditMode() {
    for (final key in _kEditableKeys) {
      _controllers
          .putIfAbsent(key, () => TextEditingController())
          .text = _fieldText(key);
    }
    _editPlayedAt = DateTime.parse(_score.playedAt);
    setState(() => _editing = true);
  }

  Future<void> _pickPlayDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _editPlayedAt,
      firstDate: DateTime(2016), // DDR A (2016) is the earliest scoring era.
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    // Day granularity; time pinned to noon so the timestamp can't drift across
    // a day boundary under a timezone offset (mirrors the capture flow).
    setState(() =>
        _editPlayedAt = DateTime(picked.year, picked.month, picked.day, 12));
  }

  String _text(String key) => _controllers[key]?.text.trim() ?? '';

  // Numeric fields accept separators ("999,940"); an empty or unparsable
  // entry clears the field, matching how an unread OCR field is stored.
  int? _number(String key) => parseOcrNumber(_text(key));

  Future<void> _saveEdits() async {
    final updated = Score(
      // Preserve identity and source. The play date changes only for
      // load-image scores; camera scores keep their capture timestamp.
      id: _score.id,
      playedAt:
          _dateEditable ? _editPlayedAt.toIso8601String() : _score.playedAt,
      source: _score.source,
      songTitle: _score.songTitle,
      mode: _score.mode,
      difficulty: _text('difficulty'),
      username: _text('username'),
      // The dropdown writes canonical ranks into the controller; only a
      // pre-existing unresolvable value left untouched stays raw.
      flare: resolveOcrFlare(_text('flare')) ?? _text('flare'),
      score: _number('score'),
      marvelous: _number('marvelous'),
      perfect: _number('perfect'),
      great: _number('great'),
      good: _number('good'),
      miss: _number('miss'),
      maxCombo: _number('maxCombo'),
      imagePath: _score.imagePath,
    );
    await DatabaseProvider.updateScore(updated);
    if (!mounted) return;
    setState(() {
      _score = updated;
      _editing = false;
    });
    showToast(context, 'Score updated');
  }

  // Tappable play-date row in edit mode, load-image scores only. Matches the
  // OCREditableField row layout (bold label + value on the right).
  Widget _buildEditDateRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'PLAY DATE',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickPlayDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  formatPlayDate(_editPlayedAt),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        centerTitle: true,
        title: const Text(
          'Score Details',
          style: TextStyle(
              fontSize: 20,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
        actions: _editing
            ? [
                IconButton(
                  tooltip: 'Discard changes',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _editing = false),
                ),
                IconButton(
                  tooltip: 'Save changes',
                  icon: const Icon(Icons.check),
                  onPressed: _saveEdits,
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Edit score',
                  icon: const Icon(Icons.edit),
                  onPressed: _enterEditMode,
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Text(
            _score.songTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // In view mode the ScoreCard below already carries the source
              // badge; only show the icon here while editing (card hidden).
              if (_editing) ...[
                Icon(
                  _score.source == ScoreSource.loadImage
                      ? Icons.photo_library_outlined
                      : Icons.videocam_outlined,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
              ],
              if (_editing)
                Flexible(
                  child: Text(
                    // In view mode the ScoreCard below already shows the date.
                    // While editing (card hidden) it's shown here instead,
                    // reflecting the working (possibly changed) play date.
                    formatDate(_dateEditable
                        ? _editPlayedAt
                        : DateTime.parse(_score.playedAt)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_editing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_dateEditable) _buildEditDateRow(),
                  for (final key in _kEditableKeys)
                    if (key == 'flare')
                      FlareDropdownField(controller: _controllers[key]!)
                    else
                      OCREditableField(
                        keyName: key,
                        controller: _controllers[key]!,
                      ),
                ],
              ),
            )
          else
            ScoreCard(score: _score),
          const SizedBox(height: 8),
          _ScoreImageSection(imageFile: _imageFile),
        ],
      ),
    );
  }
}

// The proof image captured with the score, tappable to inspect full screen.
// Shows a muted placeholder when the score has no image (pre-v5 rows) or the
// file is gone from disk.
class _ScoreImageSection extends StatelessWidget {
  const _ScoreImageSection({required this.imageFile});

  final Future<File?> imageFile;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return FutureBuilder<File?>(
      future: imageFile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final file = snapshot.data;
        if (file == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No image was saved with this score.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: mutedColor),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Saved capture',
                style: TextStyle(fontSize: 12, color: mutedColor),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _FullScreenImagePage(file: file),
              )),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  color: Colors.black,
                ),
                child: Stack(
                  children: [
                    Image.file(file, fit: BoxFit.contain),
                    const Positioned(
                      top: 4,
                      right: 4,
                      child:
                          Icon(Icons.zoom_in, size: 16, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Full-screen pinch-zoomable viewer for the saved capture.
class _FullScreenImagePage extends StatelessWidget {
  const _FullScreenImagePage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Saved capture', style: TextStyle(fontSize: 16)),
      ),
      body: InteractiveViewer(
        maxScale: 12,
        child: Center(
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
