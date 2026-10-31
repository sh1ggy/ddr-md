/// Name: EditionShare
/// Parent: EditionViewer
/// Description: A card as an image to send. Away from the score card, it
/// carries its own grade and flare stickers and the band of style,
/// difficulty and score, under the song's title. Previewed, then handed to
/// the system share sheet.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'edition_model.dart';
import 'jacket_edition.dart';

const _stamped = (
  borderId: 'gilded',
  effects: true,
  motion: false,
  modeStamp: true,
  gradeStamp: true,
  difficultyStamp: true,
  tierSuffix: true
);

Future<void> showEditionShare(BuildContext context,
        {required EditionFacts facts, required Widget artwork}) =>
    showDialog<void>(
        context: context,
        builder: (_) => _SharePreview(facts: facts, artwork: artwork));

class _SharePreview extends StatefulWidget {
  const _SharePreview({required this.facts, required this.artwork});
  final EditionFacts facts;
  final Widget artwork;
  @override
  State<_SharePreview> createState() => _SharePreviewState();
}

class _SharePreviewState extends State<_SharePreview> {
  final _image = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _image.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final origin = boundary.localToGlobal(Offset.zero) & boundary.size;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${(await getTemporaryDirectory()).path}/card.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          sharePositionOrigin: origin));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song =
        Songs.list.where((s) => s.name == widget.facts.chart.song).firstOrNull;
    return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RepaintBoundary(
              key: _image,
              child: ColoredBox(
                  color: const Color(0xFF15131C),
                  child: Padding(
                      // Room for the flare's aura.
                      padding: const EdgeInsets.fromLTRB(36, 48, 36, 18),
                      child: SizedBox(
                          width: 300,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                    aspectRatio: 1,
                                    child: JacketEdition(
                                        facts: widget.facts,
                                        options: _stamped,
                                        frozenLight: const Offset(.3, .25),
                                        child: widget.artwork)),
                                const SizedBox(height: 16),
                                if (song != null)
                                  Text(song.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: FloorPop.display(18,
                                          color: Colors.white)),
                                if (song != null && song.artist.isNotEmpty)
                                  Text(song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 13)),
                                const SizedBox(height: 10),
                                Text('DDR MD',
                                    style: FloorPop.readout(11,
                                        color: Colors.white38)),
                              ]))))),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: const Text('Share')),
        ]));
  }
}
