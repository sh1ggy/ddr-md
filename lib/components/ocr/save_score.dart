/// Name: SaveScorePanel
/// Description: Shared by the load-image and camera pages. Fuzzy-matches the
/// OCR'd title against the master song list ([Songs]) via Levenshtein
/// distance and saves the score fields to that song's record in SQLite.
/// Change opens a searchable picker (ranked by the same distance) to override
/// the automatic match. The difficulty is a menu of the charts that exist on
/// the matched song, pre-selected by matching the raw OCR reading against
/// them (see [resolveOcrDifficulty]) — mirroring how the song itself is
/// matched-but-overridable. The score sits on its own card with its grade,
/// lamp and the change against the chart's best.
library;

import 'dart:typed_data';

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/scores/score_card.dart'
    show judgedLampArt;
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/grades.dart' show gradeForScore, gradeIcon;
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/score_images.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Below this similarity the match is shown as a warning and likely wrong;
// the user can still fix the title field or pick from the list.
const double _kWeakMatchThreshold = 0.5;

class SaveScorePanel extends StatefulWidget {
  // The per-field OCR controllers owned by the parent page, keyed by the
  // kOcrFieldOrder names (excluding 'title'). Values are read at save time.
  final Map<String, TextEditingController> controllers;
  // Raw OCR'd title string used as the initial Levenshtein query. May be empty
  // when OCR didn't detect a title — the user can still open the picker.
  final String initialTitle;
  // Optional content rendered between the match header and save button.
  // Used by OCR pages to place editable fields above the save button.
  final List<Widget> middleChildren;
  // Called at save time for the proof image to store alongside the score
  // (the parent page's ROI overlay render or captured frame). Null result
  // saves the score without an image.
  final Future<Uint8List?> Function()? proofImageBytes;
  // How this score is being captured. A load-image screenshot carries no
  // capture time, so its play date is user-set here and editable later; a
  // camera score is stamped with the current time and its date is fixed.
  final ScoreSource source;
  // Beside the save button, e.g. the camera's scan-again.
  final Widget? saveTrailing;

  const SaveScorePanel({
    super.key,
    required this.controllers,
    required this.initialTitle,
    this.middleChildren = const [],
    this.proofImageBytes,
    required this.source,
    this.saveTrailing,
  });

  @override
  State<SaveScorePanel> createState() => _SaveScorePanelState();
}

class _SaveScorePanelState extends State<SaveScorePanel> {
  // Song explicitly chosen from the picker; overrides the automatic match.
  SongInfo? _selectedSong;
  // Difficulty explicitly chosen from the dropdown; overrides the automatic
  // match. Ignored when the current song doesn't have that chart (e.g. after
  // picking a different song).
  String? _pickedDifficulty;
  bool _savedOnce = false;

  // The play date for the score. Seeded to now; for load-image scores the user
  // can change the day via the date row (camera scores keep the capture time).
  DateTime _playedAt = DateTime.now();

  // Dancer name from the linked e-amusement profile, read once. Empty when
  // no profile is linked (warning disabled).
  final String _savedUsername =
      Settings.getString(Settings.eamuseNameKey).trim();

  @override
  void initState() {
    super.initState();
    // Fresh bests for the delta on the score card, this panel's scores
    // included once saved.
    ChartBests.load(Provider.of<SongState>(context, listen: false).modes)
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  String _text(String key) => widget.controllers[key]?.text.trim() ?? '';

  int? _number(String key) => parseOcrNumber(_text(key));

  Difficulty _levels(SongInfo song, Modes mode) =>
      mode == Modes.singles ? song.singles : song.doubles;

  // The played step count, summed from the judgment fields. Null unless all
  // five were read — a missing one would silently undercount the total.
  int? _judgedNoteTotal() {
    var total = 0;
    for (final key in const ['marvelous', 'perfect', 'great', 'good', 'miss']) {
      final n = _number(key);
      if (n == null) return null;
      total += n;
    }
    return total;
  }

  // Snaps the noisy OCR'd difficulty reading (e.g. "ert 16") to the in-game
  // name of a chart that exists on [song] in [mode], using the chart's
  // difficulty names and levels as evidence, with the judged step count vs
  // the charts' note counts as a fallback. Null when nothing matches.
  String? _resolvedDifficulty(SongInfo song, Modes mode) =>
      resolveOcrDifficulty(
        _text('difficulty'),
        _levels(song, mode),
        notecounts: mode == Modes.singles
            ? song.singlesNotecounts
            : song.doublesNotecounts,
        totalNotes: _judgedNoteTotal(),
      );

  // The difficulty the score will be saved under: the user's dropdown pick
  // when it exists on this song, else the automatic OCR match.
  String? _effectiveDifficulty(SongInfo song, Modes mode) {
    final options = difficultyOptions(_levels(song, mode));
    if (options.any((o) => o.$1 == _pickedDifficulty)) {
      return _pickedDifficulty;
    }
    return _resolvedDifficulty(song, mode);
  }

  // The chart's note count for the OCR'd (in-game) difficulty name, keyed to
  // the StepMania-style fields of [Difficulty]. Null when the difficulty
  // doesn't resolve or the song has no note-count data.
  int? _chartNoteCount(SongInfo song, Modes mode) {
    final counts =
        mode == Modes.singles ? song.singlesNotecounts : song.doublesNotecounts;
    return switch (
        _effectiveDifficulty(song, mode) ?? _text('difficulty').toUpperCase()) {
      'BEGINNER' => counts.beginner,
      'BASIC' => counts.easy,
      'DIFFICULT' => counts.medium,
      'EXPERT' => counts.hard,
      'CHALLENGE' => counts.challenge,
      _ => null,
    };
  }

  // Max combo renders on screen as "combo/total note count". The OCR pipeline
  // keeps only the combo, but a misread '/' leaves the two numbers
  // concatenated — when the value exceeds the chart's note count and its
  // digits end with that count, strip the suffix to recover the combo.
  int? _maxCombo(SongInfo song, Modes mode) {
    final raw = _number('maxCombo');
    if (raw == null) return null;
    final noteCount = _chartNoteCount(song, mode);
    if (noteCount == null || noteCount <= 0 || raw <= noteCount) return raw;
    final digits = raw.toString();
    final suffix = noteCount.toString();
    if (!digits.endsWith(suffix)) return raw;
    final combo = int.parse(digits.substring(0, digits.length - suffix.length));
    return combo <= noteCount ? combo : raw;
  }

  Future<void> _save(SongInfo song) async {
    if (_savedOnce) return;
    // OCR results don't say which side was played, so file the score
    // under the app's currently selected mode.
    final mode = Provider.of<SongState>(context, listen: false).modes;
    // The dropdown selection (user pick or automatic match) is always a
    // canonical chart name; only an unresolvable reading with no pick falls
    // back to the raw OCR text.
    final difficulty = _effectiveDifficulty(song, mode) ?? _text('difficulty');
    // Build the row first so it owns its generated id; the proof image is then
    // written under that id and the path folded back in. Writing the image
    // before the insert means the row never points at a path that failed to
    // save; an image that can't be produced isn't fatal.
    var score = Score(
      playedAt: _playedAt.toIso8601String(),
      source: widget.source,
      songTitle:
          song.titletranslit.isNotEmpty ? song.titletranslit : song.title,
      mode: mode,
      difficulty: difficulty,
      username: _text('username'),
      // The dropdown writes canonical ranks into the controller; only an
      // unresolvable reading the user never touched falls back to raw text.
      flare: resolveOcrFlare(_text('flare')) ?? _text('flare'),
      score: _number('score'),
      exScore: _number('exScore'),
      marvelous: _number('marvelous'),
      perfect: _number('perfect'),
      great: _number('great'),
      good: _number('good'),
      miss: _number('miss'),
      maxCombo: _maxCombo(song, mode),
    );
    final bytes = await widget.proofImageBytes?.call();
    if (bytes != null) {
      final imagePath = await ScoreImages.save(bytes, score.id);
      score = score.copyWith(imagePath: imagePath);
    }
    await DatabaseProvider.addScore(score);
    if (!mounted) return;
    setState(() => _savedOnce = true);
    showToast(context, 'Score saved for ${song.title}');
  }

  Future<void> _openPicker() async {
    final picked = await showModalBottomSheet<SongInfo>(
      context: context,
      isScrollControlled: true,
      // Keep the sheet out of the top notch when the keyboard pushes it up
      // on small screens.
      useSafeArea: true,
      builder: (context) => _SongSearchSheet(initialQuery: widget.initialTitle),
    );
    if (picked != null) {
      setState(() => _selectedSong = picked);
    }
  }

  ({SongInfo? song, SongMatch? match, bool isPicked, bool isWeak})
      _resolveMatchState() {
    if (Songs.list.isEmpty) {
      return (song: null, match: null, isPicked: false, isWeak: true);
    }
    final match =
        _selectedSong == null ? Songs.matchTitle(widget.initialTitle) : null;
    final isPicked = _selectedSong != null;
    final song = _selectedSong ?? match?.song;
    final isWeak =
        !isPicked && (match == null || match.similarity < _kWeakMatchThreshold);
    return (song: song, match: match, isPicked: isPicked, isWeak: isWeak);
  }

  @override
  Widget build(BuildContext context) {
    final state = _resolveMatchState();
    final mode = context.watch<SongState>().modes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMatchContent(
          context,
          song: state.song,
          match: state.match,
          isPicked: state.isPicked,
          isWeak: state.isWeak,
          mode: mode,
        ),
        const SizedBox(height: 12),
        if (widget.controllers.containsKey('score')) ...[
          _buildScoreCard(state.song, mode),
          const SizedBox(height: 6),
        ],
        ...widget.middleChildren,
        if (widget.source == ScoreSource.loadImage) _buildDateRow(),
        _buildUsernameMismatchWarning(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _buildSaveButton(state.song)),
          if (widget.saveTrailing != null) ...[
            const SizedBox(width: 10),
            widget.saveTrailing!,
          ],
        ]),
      ],
    );
  }

  // The charts that exist on [song] in [mode], drawn in the cabinet's
  // lettering and pre-selected with the automatic match for the raw OCR
  // reading — the difficulty counterpart of the matched-but-overridable song.
  Widget _buildDifficultyPicker(SongInfo song, Modes mode) {
    final pop = FloorPop.of(context);
    final options = difficultyOptions(_levels(song, mode));
    if (options.isEmpty) return const SizedBox.shrink();
    final isPicked = options.any((o) => o.$1 == _pickedDifficulty);
    final value = _effectiveDifficulty(song, mode);
    final level = options.where((o) => o.$1 == value).firstOrNull?.$2;
    final raw = _text('difficulty');
    return PopupMenuButton<String>(
      tooltip: 'Chart',
      enabled: !_savedOnce,
      initialValue: value,
      // An empty value is the way back to the automatic match.
      onSelected: (v) =>
          setState(() => _pickedDifficulty = v.isEmpty ? null : v),
      itemBuilder: (context) => [
        for (final (name, level) in options)
          PopupMenuItem(
              value: name,
              child: DifficultyLabel(difficulty: name, level: level)),
        if (isPicked)
          const PopupMenuItem(value: '', child: Text('Back to the match')),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (value != null)
          DifficultyLabel(difficulty: value, level: level, height: 16)
        else
          Text(
            // No chart matched the reading — show it so the user knows
            // what the scan said while they pick.
            raw.isEmpty ? 'Pick chart' : '"$raw"?',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: pop.down),
          ),
        Icon(Icons.expand_more, size: 18, color: pop.haze),
      ]),
    );
  }

  // The score on its own riser: editable, with the grade and full-combo lamp
  // it earns and how far it lands from the best on this chart.
  Widget _buildScoreCard(SongInfo? song, Modes mode) {
    final pop = FloorPop.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(widget.controllers.values.toList()),
      builder: (context, _) {
        final score = _number('score');
        final lamp = judgedLampArt(_number('marvelous'), _number('perfect'),
            _number('great'), _number('good'), _number('miss'));
        final best = song == null ? null : _bestOn(song, mode);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: pop.riser, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: widget.controllers['score'],
                enabled: !_savedOnce,
                style: FloorPop.readout(34),
                decoration: const InputDecoration.collapsed(hintText: 'Score'),
              ),
            ),
            if (score != null) ...[
              const SizedBox(width: 8),
              Image.asset(gradeIcon(gradeForScore(score)), height: 26),
            ],
            if (lamp != null) ...[
              const SizedBox(width: 8),
              Image.asset(lamp, height: 20),
            ],
            if (score != null && best != null) ...[
              const SizedBox(width: 8),
              _BestDelta(score - best),
            ],
          ]),
        );
      },
    );
  }

  // The best score on the chart this one will be saved under, before it.
  int? _bestOn(SongInfo song, Modes mode) {
    final difficulty = _effectiveDifficulty(song, mode);
    final index = _levels(song, mode)
        .availableTypes
        .indexWhere((k) => kInGameDifficultyNames[k] == difficulty);
    return index < 0 ? null : ChartBests.at(song, mode, index)?.score;
  }

  // Editable play-date row, shown only for load-image scores (a screenshot has
  // no capture time of its own). Day-granularity: tapping opens a calendar
  // picker and the time is pinned to noon so the stored timestamp can't drift
  // across a day boundary under a timezone offset.
  Widget _buildDateRow() {
    final pop = FloorPop.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 14, right: 4),
        decoration: BoxDecoration(
            color: pop.riser, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Text('PLAY DATE', style: pop.label),
            const Spacer(),
            TextButton.icon(
              onPressed: _savedOnce ? null : _pickPlayDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                formatPlayDate(_playedAt),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPlayDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _playedAt,
      firstDate: DateTime(2016), // DDR A (2016) is the earliest scoring era.
      lastDate: now,
    );
    if (picked == null) return;
    // Keep day granularity, pin the time to noon (see _buildDateRow).
    setState(
        () => _playedAt = DateTime(picked.year, picked.month, picked.day, 12));
  }

  // Gentle heads-up when the detected player name isn't the linked e-amusement
  // dancer name — the screenshot may be someone else's score (e.g. the other
  // player's side, or a friend's photo). Purely informational: saving is not
  // blocked. Listens to the username controller so edits to the field update
  // the warning live. Silent when no e-amusement profile is linked or no name
  // was detected.
  Widget _buildUsernameMismatchWarning() {
    final controller = widget.controllers['username'];
    if (_savedUsername.isEmpty || controller == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final detected = value.text.trim();
        if (detected.isEmpty ||
            detected.toUpperCase() == _savedUsername.toUpperCase()) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Detected player "$detected" doesn\'t match '
            'your dancer name "$_savedUsername".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: FloorPop.of(context).down),
          ),
        );
      },
    );
  }

  // Volt until saved, then the panel stays down on its riser.
  Widget _buildSaveButton(SongInfo? song) {
    if (!_savedOnce) {
      return VoltButton(
        onPressed: song == null ? null : () => _save(song),
        child: const Text('Save score'),
      );
    }
    final pop = FloorPop.of(context);
    return Container(
      height: 56,
      margin: const EdgeInsets.only(top: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: pop.riser, borderRadius: BorderRadius.circular(18)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_rounded, color: pop.voltText),
        const SizedBox(width: 8),
        Text('Saved',
            style: TextStyle(
                fontFamily: kDisplayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface)),
      ]),
    );
  }

  Widget _buildMatchContent(
    BuildContext context, {
    required SongInfo? song,
    required SongMatch? match,
    required bool isPicked,
    required bool isWeak,
    required Modes mode,
  }) {
    final pop = FloorPop.of(context);
    if (Songs.list.isEmpty) {
      return Text(
        'Song list not loaded — cannot link score to a song.',
        textAlign: TextAlign.center,
        style: TextStyle(color: pop.down),
      );
    }
    final similarity = '${((match?.similarity ?? 0) * 100).round()}%';
    final (subtitle, color) = song == null
        ? ('No song matched — tap Choose to search', pop.down)
        : isPicked
            ? ('Picked by hand', pop.haze)
            : isWeak
                ? ('Weak match · $similarity — check the song', pop.down)
                : ('Matched · $similarity', pop.haze);
    return ScanSongHeader(
      song: song,
      subtitle: subtitle,
      subtitleColor: color,
      difficulty: song == null ? null : _buildDifficultyPicker(song, mode),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isPicked)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Back to automatic match',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _selectedSong = null),
          ),
        TextButton(
          onPressed: _openPicker,
          style: TextButton.styleFrom(
            backgroundColor: pop.riser,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(song == null ? 'Choose' : 'Change'),
        ),
      ]),
    );
  }
}

/// The song a scan is for: jacket, title with its chart, and a line under it
/// on how it was found. Shared by the live readout and the save panel.
class ScanSongHeader extends StatelessWidget {
  const ScanSongHeader({
    super.key,
    required this.song,
    required this.subtitle,
    this.subtitleColor,
    this.difficulty,
    this.trailing,
  });

  final SongInfo? song;
  final String subtitle;
  final Color? subtitleColor;
  final Widget? difficulty;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.square(
          dimension: 52,
          child: song != null
              ? JacketImage(song!, iconSize: 24)
              : ColoredBox(
                  color: pop.riser,
                  child: Icon(Icons.music_note, size: 24, color: pop.haze)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                child: Text(
                  song?.title ?? 'No song yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (difficulty != null) ...[
                const SizedBox(width: 8),
                difficulty!,
              ],
            ]),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: subtitleColor ?? pop.haze),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ]);
  }
}

/// How far a score lands from the chart's best: Sun for a new best.
class _BestDelta extends StatelessWidget {
  const _BestDelta(this.delta);

  final int delta;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final up = delta > 0;
    final color = up ? FloorPop.onVolt : pop.haze;
    return Tooltip(
      message: 'Against your best',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: up ? FloorPop.sun : pop.line,
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (up) Icon(Icons.keyboard_arrow_up, size: 16, color: color),
          Text(
            up
                ? '+${formatScore(delta)}'
                : delta == 0
                    ? '±0'
                    : '−${formatScore(-delta)}',
            style: FloorPop.readout(14, color: color),
          ),
        ]),
      ),
    );
  }
}

// Bottom-sheet song picker: a search field prefilled with the OCR'd title and
// a result list ranked by Levenshtein similarity, updating as the user types.
// Pops with the chosen SongInfo.
class _SongSearchSheet extends StatefulWidget {
  final String initialQuery;

  const _SongSearchSheet({required this.initialQuery});

  @override
  State<_SongSearchSheet> createState() => _SongSearchSheetState();
}

class _SongSearchSheetState extends State<_SongSearchSheet> {
  late final TextEditingController _searchController =
      TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = Songs.matchTitles(_searchController.text, limit: 20);
    return Padding(
      // Keep the sheet above the on-screen keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search songs…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.trim().isEmpty
                            ? 'Type to search the song list.'
                            : 'No songs found.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final m = matches[i];
                        final translit = m.song.titletranslit;
                        return ListTile(
                          dense: true,
                          title: Text(m.song.title),
                          subtitle:
                              translit.isNotEmpty && translit != m.song.title
                                  ? Text(translit)
                                  : null,
                          trailing: Text(
                            '${(m.similarity * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, m.song),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
