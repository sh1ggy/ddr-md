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
    show OCREditableField;
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
    setState(() => _editing = true);
  }

  String _text(String key) => _controllers[key]?.text.trim() ?? '';

  // Numeric fields accept separators ("999,940"); an empty or unparsable
  // entry clears the field, matching how an unread OCR field is stored.
  int? _number(String key) => parseOcrNumber(_text(key));

  Future<void> _saveEdits() async {
    final updated = Score(
      date: _score.date,
      songTitle: _score.songTitle,
      mode: _score.mode,
      difficulty: _text('difficulty'),
      username: _text('username'),
      flare: _text('flare'),
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
          Text(
            '${_score.mode.name} • ${formatDate(DateTime.parse(_score.date))}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_editing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final key in _kEditableKeys)
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
