/// Name: MusicPage
/// Parent: AppSettingsPage
/// Description: Your Music: where to put song files and how to name them, then
/// which songs have music, which files nearly match, and what's left over.
library;

import 'dart:io';

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/models/music_library.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> with WidgetsBindingObserver {
  MusicScan? _scan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rescan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Files are added outside the app, so coming back may mean there are more.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _rescan();
  }

  Future<void> _rescan() async {
    final scan = await MusicLibrary.scan(Songs.list.map((song) => song.name));
    if (mounted) setState(() => _scan = scan);
  }

  Future<void> _confirm(String song, String file) async {
    await MusicLibrary.confirm(song, file);
    await _rescan();
  }

  Future<void> _shareMissing(BuildContext context, List<String> missing) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final list = File(
        '${(await getTemporaryDirectory()).path}/DDR MD missing music.txt');
    await list.writeAsString(
        missing
            .map((song) => '${MusicLibrary.fileNameFor(song)}.ogg')
            .join('\n'),
        flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(list.path, mimeType: 'text/plain')],
      sharePositionOrigin: origin,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    return HomeSubpage(
      title: 'Your Music',
      body: scan == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) => ListView(
                padding: clearOfBars(
                    context, const EdgeInsets.fromLTRB(8, 8, 8, 24)),
                children: [
                  _summary(context, scan),
                  if (scan.close.isNotEmpty) _closeMatches(context, scan),
                  if (scan.unused.isNotEmpty)
                    _list(
                      'Not Used',
                      "These don't match a song, or repeat one that already has "
                          'music.',
                      [for (final file in scan.unused) p.basename(file)],
                    ),
                  if (scan.missing.isNotEmpty)
                    _list('Missing', null, scan.missing),
                ],
              ),
            ),
    );
  }

  Widget _summary(BuildContext context, MusicScan scan) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${scan.matched.length} of ${Songs.list.length} songs have music',
                style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
                'Hear your own copy of a song in its chart preview. DDR MD '
                "doesn't include any music.",
                style: text.bodyMedium),
            const SizedBox(height: 12),
            Text(
                Platform.isIOS
                    ? 'Put files in Files → On My iPhone → DDR MD → music. '
                        'Subfolders are fine.'
                    : "Put files in the music folder in DDR MD's documents. "
                        'Subfolders are fine.',
                style: text.bodyMedium),
            const SizedBox(height: 8),
            Text(
                'Name each file after its song, as OGG, MP3, FLAC or WAV: '
                '“Silent Hill-song.ogg” or “Silent Hill.ogg”.',
                style: text.bodyMedium),
            if (scan.missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (button) => OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share Missing File Names'),
                  onPressed: () => _shareMissing(button, scan.missing),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _closeMatches(BuildContext context, MusicScan scan) => Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Close Matches',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final MapEntry(key: song, value: file) in scan.close.entries)
              ListTile(
                title: Text(song),
                subtitle: Text(p.basename(file)),
                trailing: IconButton(
                  tooltip: 'Use for $song',
                  icon: const Icon(Icons.check),
                  onPressed: () => _confirm(song, file),
                ),
              ),
          ],
        ),
      );

  Widget _list(String title, String? note, List<String> names) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: Text('$title (${names.length})',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: note == null ? null : Text(note),
          shape: const Border(),
          children: [
            for (final name in names) ListTile(dense: true, title: Text(name)),
          ],
        ),
      );
}
