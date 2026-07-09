/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
library;

import 'package:ddr_md/components/song/song_difficulty_picker.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Method for formatting time from a given time (s)
formattedTime({required int timeInSecond}) {
  int sec = timeInSecond % 60;
  int min = (timeInSecond / 60).floor();
  String minute = min.toString().length <= 1 ? "$min" : "$min";
  String second = sec.toString().length <= 1 ? "0$sec" : "$sec";
  return "$minute:$second";
}

class SongDetails extends StatelessWidget {
  const SongDetails({
    super.key,
    required this.songInfo,
    required this.chart,
  });

  final SongInfo songInfo;
  final Chart? chart;

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();

    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          GestureDetector(
            child: Hero(
              tag: "imgZoom",
              child: _ResolvedJacketImage(
                songName: songInfo.name,
                assetPrefix: 'assets/jackets-160/',
                height: 100,
                fallbackSize: 100,
              ),
            ),
            // Zooming image onTap
            onTap: () {
              Navigator.of(context).push(PageRouteBuilder(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  opaque: true,
                  barrierDismissible: true,
                  pageBuilder: (BuildContext context, _, __) {
                    return GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Hero(
                        tag: "imgZoom",
                        transitionOnUserGestures: true,
                        child: _ResolvedJacketImage(
                          songName: songInfo.name,
                          assetPrefix: 'assets/jackets/',
                          height: MediaQuery.of(context).size.height * .7,
                          fallbackSize: 100,
                        ),
                      ),
                    );
                  }));
            },
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (chart != null)
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 15.5,
                        color: DefaultTextStyle.of(context).style.color),
                    children: <TextSpan>[
                      TextSpan(
                        text: "${chart!.dominantBpm} BPM",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (chart!.trueMax != chart!.trueMin) ...[
                        if (!chart!.bpmRange.contains(chart!.trueMin.toString()))
                          TextSpan(text: ' (${chart!.trueMin}~) '),
                        TextSpan(text: ' ${chart!.bpmRange}'),
                        if (!chart!.bpmRange.contains(chart!.trueMax.toString()))
                          TextSpan(text: ' (~${chart!.trueMax}) '),
                      ],
                    ],
                  ),
                ),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: 16.0,
                      color: DefaultTextStyle.of(context).style.color),
                  children: <TextSpan>[
                    TextSpan(
                      text: (formattedTime(
                              timeInSecond: songInfo.songLength.toInt()) +
                          " min"),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Text(
                songInfo.version,
                style: const TextStyle(
                    fontSize: 15.5,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic),
              ),
              Align(
                  alignment: AlignmentDirectional.bottomCenter,
                  child: () {
                    Difficulty songDifficulty = songState.modes == Modes.singles
                        ? songInfo.singles
                        : songInfo.doubles;
                    // Every song has per-difficulty radar data, so the
                    // difficulty is always selectable.
                    return SongDifficultyPicker(difficulty: songDifficulty);
                  }()),
            ],
          ),
        ]);
  }
}

class _JacketLookup {
  const _JacketLookup({required this.exactPaths, required this.normalizedPath});

  final Set<String> exactPaths;
  final Map<String, String> normalizedPath;
}

class _ResolvedJacketImage extends StatefulWidget {
  const _ResolvedJacketImage({
    required this.songName,
    required this.assetPrefix,
    required this.height,
    required this.fallbackSize,
  });

  final String songName;
  final String assetPrefix;
  final double height;
  final double fallbackSize;

  @override
  State<_ResolvedJacketImage> createState() => _ResolvedJacketImageState();
}

class _ResolvedJacketImageState extends State<_ResolvedJacketImage> {
  static final Map<String, Future<_JacketLookup>> _lookupByPrefix =
      <String, Future<_JacketLookup>>{};

  static String _normalize(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _jacketBaseName(String filename) {
    if (!filename.endsWith('.png')) {
      return filename;
    }
    final noExt = filename.substring(0, filename.length - '.png'.length);
    if (noExt.endsWith('-jacket')) {
      return noExt.substring(0, noExt.length - '-jacket'.length);
    }
    return noExt;
  }

  static Future<_JacketLookup> _buildLookup(String assetPrefix) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
      .where((path) => path.startsWith(assetPrefix) && path.endsWith('.png'))
        .toList();

    final exact = <String>{};
    final normalized = <String, String>{};
    for (final path in assets) {
      exact.add(path);
      final file = path.substring(assetPrefix.length);
      final base = _jacketBaseName(file);
      normalized.putIfAbsent(_normalize(base), () => path);
    }

    return _JacketLookup(exactPaths: exact, normalizedPath: normalized);
  }

  @override
  Widget build(BuildContext context) {
    final lookupFuture = _lookupByPrefix.putIfAbsent(
      widget.assetPrefix,
      () => _buildLookup(widget.assetPrefix),
    );

    return FutureBuilder<_JacketLookup>(
      future: lookupFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            height: widget.height,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
          );
        }

        final lookup = snapshot.data!;
        final exactPngPath = '${widget.assetPrefix}${widget.songName}.png';
        final exactLegacyPath = '${widget.assetPrefix}${widget.songName}-jacket.png';
        final resolvedPath = lookup.exactPaths.contains(exactPngPath)
          ? exactPngPath
          : lookup.exactPaths.contains(exactLegacyPath)
            ? exactLegacyPath
            : lookup.normalizedPath[_normalize(widget.songName)];

        if (resolvedPath == null) {
          return Icon(Icons.music_note, size: widget.fallbackSize);
        }

        return Image(
          image: AssetImage(resolvedPath),
          height: widget.height,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.music_note, size: widget.fallbackSize),
        );
      },
    );
  }
}
