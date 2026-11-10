/// Name: ListenSheet
/// Parent: LiveDock, AppSettingsPage, ChartPreviewPage
/// Description: Song ID's sheet: listens to the cab until it places the
/// song, then shows its jacket and where the cab is in it, with a chart to
/// open or follow along. In a session the song is noted on the running
/// credit (Undo takes it back). Resyncing a chart preview listens for the
/// same song and returns where it is now.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/notes/chart_preview_page.dart';
import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/content_updater.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/song_id_listener.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// Listens for the song the cab is playing. Pages it opens go on [context]'s
/// navigator, so they stay on the tab it was opened from.
Future<void> showListenSheet(BuildContext context) {
  final host = Navigator.of(context);
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => ListenSheet(host: host),
  );
}

/// Listens again for [song], for a preview following the cab; null when it
/// wasn't heard.
Future<SongIdFollow?> relisten(BuildContext context, String song,
        {double? near}) =>
    showModalBottomSheet<SongIdFollow>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => ListenSheet(resyncing: song, near: near),
    );

enum _Phase { listening, heard, missed, noMic }

class ListenSheet extends StatefulWidget {
  const ListenSheet({super.key, this.host, this.resyncing, this.near});

  final NavigatorState? host;
  final String? resyncing;

  /// Where in the song the cab should be when resyncing starts.
  final double? near;

  @override
  State<ListenSheet> createState() => _ListenSheetState();
}

class _ListenSheetState extends State<ListenSheet> {
  var _phase = _Phase.listening;
  SongIdListener? _listener;
  Timer? _ticker;
  SongIdFollow? _follow;
  SongInfo? _song;
  int _chart = 0;
  String? _heardId;
  String? _updateNote;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _listener?.stop();
    super.dispose();
  }

  Future<void> _listen() async {
    final listener = _listener = SongIdListener();
    setState(() => _phase = _Phase.listening);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250),
        (_) => mounted ? setState(() {}) : null);
    if (!await listener.hasPermission()) {
      _ticker?.cancel();
      if (mounted) setState(() => _phase = _Phase.noMic);
      return;
    }
    SongIdFollow? follow;
    try {
      follow = await listener.listen(only: widget.resyncing, near: widget.near);
    } catch (e) {
      debugPrint('Song ID: $e');
    }
    _ticker?.cancel();
    if (!mounted || listener != _listener) return;
    final song = follow == null
        ? null
        : Songs.list.where((s) => s.name == follow!.song).firstOrNull;
    if (widget.resyncing != null) {
      if (song?.name == widget.resyncing ||
          (follow?.sameMusic.contains(widget.resyncing) ?? false)) {
        Navigator.of(context).pop(follow);
        return;
      }
      setState(() => _phase = _Phase.missed);
      return;
    }
    if (song == null) {
      setState(() => _phase = _Phase.missed);
      return;
    }
    HapticFeedback.mediumImpact();
    final types = _levels(song).availableTypes;
    setState(() {
      _phase = _Phase.heard;
      _follow = follow;
      _song = song;
      _chart = types.contains('hard')
          ? types.indexOf('hard')
          : (types.length - 1).clamp(0, 4);
    });
    final session = context.read<SessionState>();
    if (session.active) {
      _heardId = await session.noteHeard(song.name);
      if (mounted) setState(() {});
    }
  }

  Modes get _mode => context.read<SongState>().modes;

  /// Another song with the same music: the credit's note moves to it.
  Future<void> _pick(SongInfo song) async {
    final types = _levels(song).availableTypes;
    setState(() {
      _song = song;
      _chart = types.contains('hard')
          ? types.indexOf('hard')
          : (types.length - 1).clamp(0, 4);
    });
    final session = context.read<SessionState>();
    if (_heardId case final id?) {
      await session.forgetHeard(id);
      _heardId = await session.noteHeard(song.name);
      if (mounted) setState(() {});
    }
  }

  Difficulty _levels(SongInfo song) =>
      _mode == Modes.singles ? song.singles : song.doubles;

  Future<void> _undo() async {
    final id = _heardId;
    if (id == null) return;
    _heardId = null;
    await context.read<SessionState>().forgetHeard(id);
    if (mounted) setState(() {});
  }

  void _openSong() {
    final song = _song!;
    context.read<SongState>()
      ..setSongInfo(song)
      ..setChosenDifficulty(_chart);
    Navigator.of(context).pop();
    widget.host
        ?.push(MaterialPageRoute<void>(builder: (_) => const SongPage()));
  }

  void _followAlong() {
    final song = _song!;
    final types = _levels(song).availableTypes;
    if (types.isEmpty) return;
    final follow = _follow!;
    // Full screen, over the tab bar and live dock, which would cover the
    // follow bar; the sheet is already on the root navigator.
    final root = Navigator.of(context);
    root.pop();
    root.push(MaterialPageRoute<void>(
        builder: (_) => ChartPreviewPage.forChart(song, _mode, types[_chart],
            follow: follow)));
  }

  Future<void> _checkUpdates() async {
    setState(() => _updateNote = 'Checking…');
    String note;
    try {
      final applied =
          await ContentUpdater.update(await getApplicationSupportDirectory());
      note =
          applied ? 'New songs added. Try again.' : 'Song list is up to date';
    } catch (_) {
      note = "Couldn't check for updates";
    }
    if (mounted) setState(() => _updateNote = note);
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    // Scrolls on a screen too short for it (a small phone on its side).
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: AnimatedSize(
          duration: FloorPop.eighth,
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: switch (_phase) {
            _Phase.listening => _listening(pop),
            _Phase.heard => _heard(pop),
            _Phase.missed => _missed(pop),
            _Phase.noMic => _noMic(pop),
          },
        ),
      ),
    );
  }

  Widget _title(String text) => Transform(
        transform: FloorPop.titleLean,
        child: Text(text,
            style: FloorPop.display(22,
                color: Theme.of(context).colorScheme.onSurface)),
      );

  Widget _listening(FloorPop pop) {
    final seconds = _listener?.seconds ?? 0;
    final credit = context.watch<SessionState>().credit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          if (credit != null)
            Text('CREDIT ${credit.number}',
                style: pop.label.copyWith(color: pop.voltText)),
          const Spacer(),
          Text('0:${seconds.toString().padLeft(2, '0')}',
              style: pop.label.copyWith(color: pop.haze)),
        ]),
        const SizedBox(height: 28),
        const _ListeningPad(),
        const SizedBox(height: 28),
        _title(widget.resyncing == null ? 'Listening…' : 'Catching up…'),
        const SizedBox(height: 8),
        Text("Point it at the cab's speakers. Usually a few seconds.",
            textAlign: TextAlign.center, style: TextStyle(color: pop.haze)),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (seconds / SongIdListener.maxSeconds).clamp(0, 1),
            minHeight: 6,
            color: FloorPop.volt,
            backgroundColor: pop.riser,
          ),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline, size: 14, color: pop.haze),
          const SizedBox(width: 6),
          Text('Matched on your phone · nothing is recorded or sent',
              style: TextStyle(fontSize: 12, color: pop.haze)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: GhostButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
        ),
      ],
    );
  }

  Widget _heard(FloorPop pop) {
    final song = _song!;
    final levels = _levels(song).toJson();
    final types = _levels(song).availableTypes;
    final at = _follow!.now();
    final credit = context.watch<SessionState>().credit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox.square(
              dimension: min(280, MediaQuery.sizeOf(context).height * 0.36),
              child: Stack(fit: StackFit.expand, children: [
                SongArtwork(
                    songName: song.name,
                    title: song.title,
                    fullResolution: true),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          FloorPop.night.ink.withValues(alpha: 0),
                          FloorPop.night.ink.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Transform(
                            transform: FloorPop.titleLean,
                            child: Text(song.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    FloorPop.display(19, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Lean(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: FloorPop.volt,
                                borderRadius: BorderRadius.circular(8)),
                            child: Upright(
                              child: Text(
                                  '${at ~/ 60}:${(at % 60).floor().toString().padLeft(2, '0')} IN',
                                  style: FloorPop.readout(13,
                                      color: FloorPop.onVolt)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (_follow!.sameMusic.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final name in [_follow!.song, ..._follow!.sameMusic])
              if (Songs.list.where((s) => s.name == name).firstOrNull
                  case final other?)
                ChoiceChip(
                  label: Text(other.title),
                  selected: other.name == song.name,
                  onSelected: (_) => _pick(other),
                ),
          ]),
        ],
        if (types.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < types.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Material(
                  color: pop.riser,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: i == _chart
                        ? const BorderSide(color: FloorPop.volt, width: 2)
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _chart = i),
                    child: SizedBox(
                      height: 52,
                      child: Center(
                        child: LevelNumber(
                          level: levels[types[i]] as int,
                          difficulty: kInGameDifficultyNames[types[i]]!,
                          dimmed: i != _chart,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ],
        if (credit != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
                color: pop.riser, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(_heardId == null ? Icons.remove : Icons.check,
                  size: 16, color: _heardId == null ? pop.haze : pop.up),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    _heardId == null
                        ? 'Not noted on credit ${credit.number}'
                        : 'Noted on credit ${credit.number} · offered first when you scan',
                    style: const TextStyle(fontSize: 13)),
              ),
              if (_heardId != null)
                TextButton(onPressed: _undo, child: const Text('Undo')),
              if (_heardId == null) const SizedBox(height: 44),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        Row(children: [
          GhostButton(
              height: 56, onPressed: _openSong, child: const Text('Open song')),
          const SizedBox(width: 10),
          Expanded(
            child: VoltButton(
              onPressed: types.isEmpty ? null : _followAlong,
              child: const Text('Follow along'),
            ),
          ),
        ]),
        TextButton(
          onPressed: () {
            _undo();
            _listen();
          },
          child:
              Text('Not it? Listen again', style: TextStyle(color: pop.haze)),
        ),
      ],
    );
  }

  Widget _tip(IconData icon, String title, String detail, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color ?? FloorPop.of(context).haze),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail,
                  style: TextStyle(
                      fontSize: 13, color: FloorPop.of(context).haze)),
            ]),
          ),
        ]),
      );

  Widget _missed(FloorPop pop) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(children: [
            const PadGlyph(size: 44, color: FloorPop.coral),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title(widget.resyncing == null
                        ? "Couldn't place it"
                        : 'Lost the song'),
                    const SizedBox(height: 6),
                    Text(
                        widget.resyncing == null
                            ? '${SongIdListener.maxSeconds} s of listening, no song stood out'
                            : "Didn't hear it again. It may have ended",
                        style: TextStyle(fontSize: 13, color: pop.haze)),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          _tip(Icons.volume_up_outlined, 'Get closer to a speaker',
              'The cab next door or the crowd can drown it'),
          _tip(Icons.schedule, 'Wait for the song to start',
              "Menus and the result screen aren't songs"),
          if (widget.resyncing == null)
            _tip(
                Icons.download_outlined,
                'It might be newer than your song list',
                _updateNote ?? 'Check for song updates',
                color: FloorPop.sun),
          const SizedBox(height: 16),
          Row(children: [
            if (widget.resyncing == null) ...[
              GhostButton(
                  height: 56,
                  onPressed: _updateNote == 'Checking…' ? null : _checkUpdates,
                  child: const Text('Check updates')),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: VoltButton(
                  onPressed: _listen, child: const Text('Listen again')),
            ),
          ]),
        ],
      );

  Widget _noMic(FloorPop pop) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Icon(Icons.mic_off_outlined, size: 40, color: pop.haze),
          const SizedBox(height: 12),
          Center(child: _title('Song ID needs the mic')),
          const SizedBox(height: 8),
          Text(
              Platform.isIOS || Platform.isMacOS
                  ? 'Allow DDR MD under Settings → Privacy → Microphone. It only listens while this sheet is open.'
                  : 'Allow the microphone for DDR MD in Settings. It only listens while this sheet is open.',
              textAlign: TextAlign.center,
              style: TextStyle(color: pop.haze)),
          const SizedBox(height: 20),
          GhostButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      );
}

/// The pad, its four arrows stepping on the beat while it listens.
class _ListeningPad extends StatefulWidget {
  const _ListeningPad();

  @override
  State<_ListeningPad> createState() => _ListeningPadState();
}

class _ListeningPadState extends State<_ListeningPad>
    with SingleTickerProviderStateMixin {
  late final _beat =
      AnimationController(vsync: this, duration: FloorPop.beat * 4)..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final riser = FloorPop.of(context).riser;
    // Up, right, down, left around the pad, a beat each.
    const arrows = {1: 0, 5: 1, 7: 2, 3: 3};
    return AnimatedBuilder(
      animation: _beat,
      builder: (context, _) {
        final t = _beat.value * 4;
        return SizedBox(
          width: 46 * 3 + 16,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var cell = 0; cell < 9; cell++)
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: switch (arrows[cell]) {
                      final beat? => Color.lerp(riser, FloorPop.volt,
                          (1 - ((t - beat) % 4) / 1.2).clamp(0.25, 1))!,
                      null => riser,
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
