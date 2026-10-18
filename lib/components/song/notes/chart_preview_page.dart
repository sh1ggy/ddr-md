/// Name: ChartPreviewPage
/// Parent: SongPage (opened via the "Chart preview" button), SnippetsPage
/// Description: Full-screen route hosting the scrolling chart renderer for one
/// song/mode/difficulty. Kept off the song page itself so its running Ticker
/// and full-height canvas only exist while the user is actually watching the
/// preview, not while scrolling the song details.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/notes/chart_models.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song/notes/section_bar.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/parity_labels.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChartPreviewPage extends StatefulWidget {
  const ChartPreviewPage({
    super.key,
    required this.stepsFuture,
    required this.mode,
    required this.difficultyKey,
    required this.difficultyLevel,
    required this.title,
    required this.songLength,
    required this.chartBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.bpms,
    required this.stops,
    this.sync,
    this.timeSignatures = const [],
    this.initialSecond,
    this.snippet,
    this.newSnippet = false,
    this.feedActive,
    this.playbackRate = 1.0,
    this.onPlaybackRateChanged,
    this.feedLabel,
  });

  /// The preview of [info]'s [mode] [difficultyKey], its timing taken from the
  /// chart that difficulty uses. [stepsFuture] reuses a load already under way.
  factory ChartPreviewPage.forChart(
    SongInfo info,
    Modes mode,
    String difficultyKey, {
    Key? key,
    Future<SongSteps?>? stepsFuture,
    double? initialSecond,
    Snippet? snippet,
    bool newSnippet = false,
    bool? feedActive,
    double playbackRate = 1.0,
    ValueChanged<double>? onPlaybackRateChanged,
    String? feedLabel,
  }) {
    final difficulty = mode == Modes.singles ? info.singles : info.doubles;
    // Per-chart timing is listed by difficulty, Beginner to Challenge, for SP
    // and DP alike.
    final i = kInGameDifficultyNames.keys.toList().indexOf(difficultyKey);
    final chart = info.perChart
        ? info.charts[i.clamp(0, info.charts.length - 1)]
        : info.charts.first;
    return ChartPreviewPage(
      key: key,
      stepsFuture: stepsFuture ?? StepsLoader.load(info.name),
      mode: mode,
      difficultyKey: difficultyKey,
      difficultyLevel: difficulty.toJson()[difficultyKey] as int?,
      title: info.title,
      songLength: info.songLength,
      chartBpm: chart.dominantBpm,
      minBpm: chart.trueMin,
      maxBpm: chart.trueMax,
      bpms: chart.bpms,
      stops: chart.stops,
      // The song page's Sync card reading (cabinet block when present, else
      // simfile), so ARCADE SYNC can report the song's own bias.
      sync: info.displaySyncFor(chart),
      timeSignatures: info.timeSignatures,
      initialSecond: initialSecond,
      snippet: snippet,
      newSnippet: newSnippet,
      feedActive: feedActive,
      playbackRate: playbackRate,
      onPlaybackRateChanged: onPlaybackRateChanged,
      feedLabel: feedLabel,
    );
  }

  /// A saved snippet: its section loops, and Edit moves it.
  final Snippet? snippet;

  /// Opens picking a new snippet's section; Add saves it and pops with it.
  final bool newSnippet;

  /// See [ChartScroller.feedActive] and [ChartScroller.playbackRate].
  final bool? feedActive;
  final double playbackRate;
  final ValueChanged<double>? onPlaybackRateChanged;
  final String? feedLabel;

  /// The (already in-flight) lazy load of the song's step file, shared with the
  /// song page so opening the preview doesn't re-read the asset.
  final Future<SongSteps?> stepsFuture;
  final Modes mode;
  final String difficultyKey;

  /// The chart's meter/level number (e.g. 14), shown next to the difficulty
  /// name in the header. Null when the song data has no level for this key.
  final int? difficultyLevel;
  final String title;
  final double songLength;
  final int chartBpm;

  /// The chart's authored BPM extremes (`true_min`/`true_max` from [Chart]),
  /// with [chartBpm] as the core (dominant) tempo between them. This is the
  /// same (min, core, max) trio the cabinet hands its speed option, and
  /// [maxBpm] is the divisor REAL SPEED derives its multiplier from.
  final int minBpm;
  final int maxBpm;

  /// BPM segments and stops for this chart, in seconds (from [Chart]). Rendered
  /// as timing markers in the scroller so the preview reflects tempo shifts.
  final List<Bpm> bpms;
  final List<Stop> stops;

  /// The song's measured audio-vs-chart sync — the same block the song page's
  /// Sync card displays (cabinet when available, else simfile). Surfaced under
  /// ARCADE SYNC so the offsets are dialled against the song's known bias
  /// rather than in the dark. Null when the song ships no sync data.
  final Sync? sync;

  /// The song's bar lengths ([SongInfo.timeSignatures]).
  final List<TimeSignature> timeSignatures;

  /// Opens on this second rather than the top, straight into the footing
  /// editor where there is one — to judge a moment picked elsewhere.
  final double? initialSecond;

  @override
  State<ChartPreviewPage> createState() => _ChartPreviewPageState();
}

class _ChartPreviewPageState extends State<ChartPreviewPage> {
  bool _showFootGuide = false;

  // Footing edit mode (debug builds): a distinct mode, entered from the
  // header rather than the viewing options.
  late bool _editFooting = kDebugMode && widget.initialSecond != null;

  // Same-foot trails, split out of the foot guide so the movement can be read
  // without the badges (and vice versa). Persisted like the other viewing aids.
  bool _showFootTrails = Settings.getInt(Settings.footTrailsOnKey) == 1;

  void _toggleFootTrails() {
    setState(() => _showFootTrails = !_showFootTrails);
    Settings.setInt(Settings.footTrailsOnKey, _showFootTrails ? 1 : 0);
  }

  // Assist tick: audible tick as each note row crosses the receptors during
  // playback (chart-derived, no song audio involved). Persisted across previews.
  bool _assistTick = Settings.getInt(Settings.assistTickOnKey) == 1;

  void _toggleAssistTick() {
    setState(() => _assistTick = !_assistTick);
    Settings.setInt(Settings.assistTickOnKey, _assistTick ? 1 : 0);
  }

  // Measure rules, persisted the same way.
  bool _measureLines = Settings.getInt(Settings.measureLinesOnKey) == 1;

  void _toggleMeasureLines() {
    setState(() => _measureLines = !_measureLines);
    Settings.setInt(Settings.measureLinesOnKey, _measureLines ? 1 : 0);
  }

  // The dancing-feet pad, likewise persisted: it's a way of reading charts you
  // either want on or don't, not a per-song choice.
  bool _dancingFeet = Settings.getInt(Settings.dancingFeetOnKey) == 1;

  void _toggleDancingFeet() {
    setState(() => _dancingFeet = !_dancingFeet);
    Settings.setInt(Settings.dancingFeetOnKey, _dancingFeet ? 1 : 0);
  }

  // Full quantisation colouring; off is the cabinet's coarser palette.
  // QuantColors reads a global rather than taking the flag per call, so seed it
  // from the stored setting on the way in.
  bool _quantColors = Settings.getInt(Settings.quantColorsOnKey) == 1;

  // The cabinet's blinking arrow art, on unless static sprites were chosen.
  bool _arrowBlink = Settings.getInt(Settings.staticArrowsOnKey) == 0;

  void _toggleArrowBlink() {
    setState(() => _arrowBlink = !_arrowBlink);
    Settings.setInt(Settings.staticArrowsOnKey, _arrowBlink ? 0 : 1);
  }

  // Freeze heads drawn as quantised taps, persisted the same way.
  bool _quantFreezeHeads = Settings.getInt(Settings.quantFreezeHeadsOnKey) == 1;

  void _toggleQuantFreezeHeads() {
    setState(() => _quantFreezeHeads = !_quantFreezeHeads);
    Settings.setInt(Settings.quantFreezeHeadsOnKey, _quantFreezeHeads ? 1 : 0);
  }

  @override
  void initState() {
    super.initState();
    QuantColors.arcadeMode = !_quantColors;
  }

  bool get _isSnippet => widget.snippet != null || widget.newSnippet;

  // The snippet's section and whether taps are picking it.
  late BeatRange? _section = switch (widget.snippet) {
    final s? => (s.startBeat, s.endBeat),
    null => null,
  };
  late bool _picking = widget.newSnippet;

  Future<void> _saveSnippet(SongSteps song, ChartSteps steps) async {
    final section = _section;
    if (section == null) return;
    final hash = chartHash(steps.notes);
    final Snippet snippet;
    if (widget.snippet case final s?) {
      snippet = s.copyWith(
          chartHash: hash, startBeat: section.$1, endBeat: section.$2);
    } else {
      final label = await _askLabel(section);
      if (label == null) return;
      snippet = Snippet(
        createdAt: DateTime.now().toIso8601String(),
        song: song.name,
        mode: widget.mode,
        difficulty: widget.difficultyKey,
        chartHash: hash,
        startBeat: section.$1,
        endBeat: section.$2,
        label: label,
      );
    }
    await DatabaseProvider.saveSnippet(snippet);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (widget.newSnippet) {
      Navigator.of(context).pop(snippet);
    } else {
      setState(() => _picking = false);
    }
  }

  // An optional name; null when cancelled.
  Future<String?> _askLabel(BeatRange section) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add snippet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              hintText: sectionLabel(section, widget.timeSignatures)),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
  }

  void _toggleQuantColors() {
    setState(() {
      _quantColors = !_quantColors;
      QuantColors.arcadeMode = !_quantColors;
    });
    Settings.setInt(Settings.quantColorsOnKey, _quantColors ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final diffColor = difficultyColor(widget.difficultyKey);
    // Edge-to-edge: the field owns the whole screen (including behind the status
    // bar) and the controls float over it, so no AppBar / SafeArea chrome here.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A0E),
        body: FutureBuilder<SongSteps?>(
          future: widget.stepsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final steps =
                snapshot.data?.chartFor(widget.mode, widget.difficultyKey);
            if (steps == null || steps.notes.isEmpty) {
              return Stack(
                children: [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        "No chart data available for this difficulty.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  // Still offer a way back when there's nothing to show.
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.blueGrey),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ChartScroller(
              key: ValueKey(
                  "${widget.title}-${widget.mode.name}-${widget.difficultyKey}"),
              steps: steps,
              feedActive: widget.feedActive,
              playbackRate: widget.playbackRate,
              onPlaybackRateChanged: widget.onPlaybackRateChanged,
              mode: widget.mode,
              songLength: widget.songLength,
              chartBpm: widget.chartBpm,
              minBpm: widget.minBpm,
              maxBpm: widget.maxBpm,
              bpms: widget.bpms,
              stops: widget.stops,
              sync: widget.sync,
              timeSignatures: widget.timeSignatures,
              showFootGuide: _showFootGuide,
              showFootTrails: _showFootTrails,
              showDancingFeet: _dancingFeet,
              showMeasureLines: _measureLines,
              assistTickOn: _assistTick,
              quantColorsOn: _quantColors,
              arrowBlinkOn: _arrowBlink,
              quantFreezeHeadsOn: _quantFreezeHeads,
              onToggleMeasureLines: _toggleMeasureLines,
              onToggleFootGuide: () =>
                  setState(() => _showFootGuide = !_showFootGuide),
              onToggleFootTrails: _toggleFootTrails,
              onToggleDancingFeet: _toggleDancingFeet,
              onToggleAssistTick: _toggleAssistTick,
              onToggleQuantColors: _toggleQuantColors,
              onToggleArrowBlink: _toggleArrowBlink,
              onToggleQuantFreezeHeads: _toggleQuantFreezeHeads,
              headerBuilder: (context, patternsButton) => _buildHeader(
                  context,
                  diffColor,
                  patternsButton,
                  () => _saveSnippet(snapshot.data!, steps)),
              // The footing editor stays a debug tool until it ships to users,
              // and keeps out of snippets, where taps pick the section.
              footingRef: kDebugMode && !_isSnippet
                  ? ChartRef(
                      snapshot.data!.name,
                      widget.mode == Modes.doubles ? 'dp' : 'sp',
                      widget.difficultyKey)
                  : null,
              editFooting: _editFooting,
              initialSecond: widget.initialSecond,
              section: _section,
              pickSection: _picking,
              onSaveSection: () => _saveSnippet(snapshot.data!, steps),
              onSectionChanged: (s) => setState(() => _section = s),
            );
          },
        ),
      ),
    );
  }

  // The floating top bar laid over the field: back + title/mode/difficulty only.
  // The assist-tick and foot-guide toggles moved into the scroller's settings
  // shade (its own segment); the shade itself opens from the scroller's menu
  // pull-tab, so the header carries no action affordances at all. A translucent
  // gradient alone keeps it legible against the scrolling arrows — it fades into
  // the field rather than being fenced off by a rule.
  Widget _buildHeader(BuildContext context, Color diffColor,
      Widget patternsButton, VoidCallback onSaveSnippet) {
    final difficultyLabel = widget.difficultyLevel != null
        ? "${_pretty(widget.difficultyKey)} ${widget.difficultyLevel}"
        : _pretty(widget.difficultyKey);
    // Beside the patterns: the snippet's Add/Save while picking, else its
    // Edit; outside snippets, the footing editor's toggle (debug builds).
    final Widget? action = _isSnippet
        ? _picking
            ? IconButton(
                icon: Icon(Icons.check,
                    color: _section == null ? Colors.white24 : kSectionColor),
                tooltip: widget.newSnippet ? 'Add snippet' : 'Save section',
                onPressed: _section == null ? null : onSaveSnippet,
              )
            : IconButton(
                icon: const Icon(Icons.edit, color: Colors.blueGrey),
                tooltip: 'Edit section',
                onPressed: () => setState(() => _picking = true),
              )
        : kDebugMode
            ? IconButton(
                icon: Icon(_editFooting ? Icons.check : Icons.edit_note,
                    color: _editFooting ? Colors.white : Colors.blueGrey),
                tooltip: _editFooting ? 'Done editing' : 'Edit footing',
                onPressed: () => setState(() => _editFooting = !_editFooting),
              )
            : null;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.blueGrey),
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (action != null) const SizedBox(width: 48),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18,
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.feedLabel != null)
                      Text(widget.feedLabel!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    if (kInGameDifficultyColors
                        .containsKey(_pretty(widget.difficultyKey)))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: DifficultyLabel(
                            difficulty: _pretty(widget.difficultyKey),
                            level: widget.difficultyLevel,
                            height: 16),
                      )
                    else
                      Text(
                        difficultyLabel,
                        style: TextStyle(
                            fontSize: 12,
                            color: diffColor,
                            fontWeight: FontWeight.w900),
                      ),
                  ],
                ),
              ),
              // The pattern breakdown, balanced by an empty slot on the left
              // when an action joins it.
              if (widget.feedActive == null) patternsButton,
              if (action != null) action,
            ],
          ),
        ),
      ),
    );
  }
}

// The in-game name (BASIC/DIFFICULT/EXPERT…), not the StepMania-style data key
// — "medium" is a field name, never something a player sees.
String _pretty(String difficultyKey) =>
    kInGameDifficultyNames[difficultyKey] ??
    (difficultyKey.isEmpty
        ? ""
        : difficultyKey[0].toUpperCase() + difficultyKey.substring(1));
