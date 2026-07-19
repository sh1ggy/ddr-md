import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ddr_md/components/ocr/ocr_shared.dart';
import 'package:ddr_md/components/ocr/save_score.dart';
import 'package:ddr_md/components/roi_overlay.dart';
import 'package:ddr_md/grades.dart' show flareRankIcon;
import 'package:ddr_md/helpers.dart'
    show judgmentColor, kFlareRanks, resolveOcrFlare;
import 'package:ddr_md/models/db_models.dart' show ScoreSource;
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

const int imageQuality = 100;
late Directory tempDir;
String get tempPath => '${tempDir.path}/';

class LoadImage extends StatefulWidget {
  const LoadImage({super.key});

  @override
  State<LoadImage> createState() => _LoadImageState();
}

class _LoadImageState extends State<LoadImage> {
  late OCRProcessor _ocrProcessor;
  bool _isPicking = false;
  bool _isProcessing = false;
  bool _isReady = false;
  XFile? _pickedImage;
  ProcessResult? _lastResult;
  double _camFrameToScreenScale = 1.0;
  DetectionSide _detectionSide = DetectionSide.left;
  String _ocrTitle = '';
  // Editable controllers per OCR field, prefilled from the result. Created
  // lazily when a result arrives and reused across results. Title is excluded.
  final Map<String, TextEditingController> _fieldControllers = {};
  // Latest saved ROI-overlay debug render for the processed image, read back
  // from disk (the picked-image pipeline always runs with debug capture on).
  final ValueNotifier<Uint8List?> _debugOverlayBytes = ValueNotifier(null);

  // The native picked-image path writes its composite ROI overlay to a
  // timestamped ocr_debug_* dir under the app documents dir's debug/ subdir
  // on every run that warped. Surface the newest one for on-device
  // troubleshooting.
  Future<void> _loadLatestDebugOverlay() async {
    try {
      final dirs = Directory('${tempDir.path}/debug')
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.split('/').last.startsWith('ocr_debug_'))
          .toList()
        // Timestamped names sort lexicographically; newest last.
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final d in dirs.reversed) {
        final f = File('${d.path}/roi_overlay.png');
        if (await f.exists()) {
          _debugOverlayBytes.value = await f.readAsBytes();
          return;
        }
      }
      _debugOverlayBytes.value = null;
    } catch (_) {
      _debugOverlayBytes.value = null;
    }
  }

  // Prefills the editable controllers from the OCR result, creating missing
  // ones. Title is excluded — it drives song matching directly, not a field.
  // Only keys present (and non-empty) in [ocrStrings] get a field.
  void _syncFieldControllers(Map<String, String> ocrStrings) {
    // Flare always gets a controller: it renders as a hard-set rank dropdown
    // that can be set even when OCR read nothing.
    _fieldControllers.putIfAbsent('flare', () => TextEditingController());
    for (final key in kOcrFieldOrder) {
      if (key == 'title') continue;
      final value = ocrStrings[key]?.trim() ?? '';
      if (value.isEmpty) continue;
      final controller =
          _fieldControllers.putIfAbsent(key, () => TextEditingController());
      controller.text = value;
    }
  }

  // Difficulty is excluded: SaveScorePanel renders it as a dropdown of the
  // matched song's charts instead of a free-text field.
  List<String> get _populatedKeys => kOcrFieldOrder
      .where((k) => k != 'difficulty' && _fieldControllers.containsKey(k))
      .toList();

  Future<void> _processImage() async {
    if (!_isReady || _isPicking || (!Platform.isIOS && !Platform.isAndroid)) {
      return;
    }
    setState(() {
      _isPicking = true;
      _lastResult = null; // Clear previous ROI data immediately
      _debugOverlayBytes.value = null;
      _isProcessing = false;
    });

    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);

    if (!mounted) return;
    if (pickedImage == null) {
      setState(() => _isPicking = false);
      return;
    }
    setState(() {
      _pickedImage = pickedImage;
      _isPicking = false;
      _isProcessing = true;
    });
    _ocrProcessor.processPickedImage(_pickedImage!);
    // wait for the stream listener to clear _isProcessing when a result arrives
  }

  Future<void> _initLoadImage() async {
    // init() (model asset copy) and initActor() (isolate spawn + create_ocr_instance)
    // must still be sequential — the isolate needs the app path from init() —
    // but we kick them off immediately so the page renders while they run in the
    // background. The button stays disabled until both complete.
    // No camera session: this page only runs the picked-image FFI path, and it
    // is pushed over the live camera page whose session must stay the only one.
    await _ocrProcessor.init(cameraSession: false);
    if (mounted) setState(() => _isReady = true);
  }

  @override
  void initState() {
    super.initState();
    getApplicationDocumentsDirectory().then((dir) {
      tempDir = dir;
    });
    _detectionSide = savedDetectionSide();
    _ocrProcessor = OCRProcessor();
    _ocrProcessor.side = _detectionSide;
    _ocrProcessor.streamResultController.stream.listen((result) async {
      // Try to read the saved temp image and compute a scale so ROI maps to
      // the displayed image width. Falls back to existing scale if file missing.
      if (_pickedImage == null) {
        setState(() => _isProcessing = false);
        return;
      }
      final f = File(_pickedImage!.path);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        ui.decodeImageFromList(bytes, (img) {
          final screenW = MediaQuery.of(context).size.width;
          final scale =
              img.width > 0 ? screenW / img.width : _camFrameToScreenScale;

          List<Rectangle<int>> detectedRois = [];
          setState(() {
            _isProcessing = false;
            _camFrameToScreenScale = scale;
            if (result.detectedRois == null) {
              return;
            }
            for (int i = 0; i < result.detectedRois!.length; i++) {
              final roi = result.detectedRois![i];
              print(
                  'Detected ROI $i: left=${roi.left}, top=${roi.top}, width=${roi.width}, height=${roi.height}');

              Rectangle<int> roiToAdd = Rectangle<int>(
                (roi.left * _camFrameToScreenScale).toInt(),
                (roi.top * _camFrameToScreenScale).toInt(),
                (roi.width * _camFrameToScreenScale).toInt(),
                (roi.height * _camFrameToScreenScale).toInt(),
              );
              detectedRois.add(roiToAdd);
            }
            _lastResult = ProcessResult(
                result.difficulty,
                null,
                detectedRois,
                result.isDetected,
                result.returnImageType,
                result.debugMaskBytes,
                result.debugDetailsCropBytes,
                result.captureBytes,
                result.detailsRoiIndex,
                result.ocrStrings);
            _ocrTitle = result.ocrStrings['title']?.trim() ?? '';
            _syncFieldControllers(result.ocrStrings);
          });
          // The overlay PNG is written before the FFI call returns, so the
          // newest ocr_debug_* dir is this run's. A run that never warped
          // writes none — clear instead of showing a stale previous overlay.
          if (result.isDetected) {
            _loadLatestDebugOverlay();
          } else {
            _debugOverlayBytes.value = null;
          }
        });
      } else {
        setState(() => _isProcessing = false);
      }
    });
    _initLoadImage();
  }

  @override
  void dispose() {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    _debugOverlayBytes.dispose();
    _ocrProcessor.dispose();
    super.dispose();
  }

  void _onSideChanged(DetectionSide side) {
    setState(() {
      _detectionSide = side;
      _ocrProcessor.side = side;
      // Re-run OCR on the already-picked image so the result
      // reflects the newly selected side.
      if (!_isPicking) {
        _lastResult = null;
        _isProcessing = true;
      }
    });
    if (!_isPicking) {
      _ocrProcessor.processPickedImage(_pickedImage!);
    }
  }

  // Tap-to-pick: when the side heuristics anchor on the wrong box (easy with
  // 3+ candidates), tapping the correct box re-runs OCR with that blob forced
  // as the Details badge. Taps outside every box are ignored. [pos] is in the
  // displayed-image space; the ROIs in _lastResult are already scaled to it,
  // and dividing by the same scale recovers original-image pixels for native.
  void _onRoiTap(Offset pos) {
    final rois = _lastResult?.detectedRois;
    if (rois == null || _isProcessing || _pickedImage == null) return;
    final scale = _camFrameToScreenScale;
    if (scale <= 0) return;
    const slop = 12.0;
    final hit = rois.any((r) => Rect.fromLTWH(r.left - slop, r.top - slop,
            r.width + 2 * slop, r.height + 2 * slop)
        .contains(pos));
    if (!hit) return;
    setState(() {
      _lastResult = null;
      _isProcessing = true;
    });
    _ocrProcessor.processPickedImage(
      _pickedImage!,
      tapPoint:
          Point<int>((pos.dx / scale).round(), (pos.dy / scale).round()),
    );
  }

  // Floats over the loaded screenshot — and over the no-detection empty
  // state, where switching sides is how you retry the same image.
  Widget get _floatingSideSelector => Positioned(
        top: 12,
        left: 0,
        right: 0,
        child: DetectionSideSelector(
          value: _detectionSide,
          onChanged: _onSideChanged,
          overlay: true,
        ),
      );

  bool get pickedImage => _pickedImage != null;
  bool get isProcessed => _lastResult != null;
  bool get isDetected =>
      _lastResult != null &&
      _lastResult!.isDetected &&
      _lastResult!.detectedRois != null;
  bool get hasScore =>
      _lastResult != null && _lastResult!.ocrStrings.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        centerTitle: true,
        title: const Text(
          'Load Image',
          style: TextStyle(
              fontSize: 20,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Disabled (null onPressed + grey) until OCR init completes,
        // matching the camera page's Start OCR FAB.
        onPressed: _isReady ? _processImage : null,
        backgroundColor: _isReady ? null : Colors.grey.shade400,
        icon: const Icon(Icons.add_photo_alternate),
        label: Text(_isReady ? 'Process photo' : 'Initialising…'),
      ),
      body: _isPicking || _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : !pickedImage
              ? const OcrEmptyState(
                  icon: Icons.image_search,
                  title: 'No image loaded',
                  subtitle: 'Pick a results screenshot to scan your score',
                )
              : !isDetected
                  ? Stack(
                      children: [
                        const OcrEmptyState(
                          icon: Icons.search_off,
                          title: 'No score detected',
                          subtitle: 'Please try another image',
                        ),
                        _floatingSideSelector,
                      ],
                    )
                  : ListView(
                      shrinkWrap: true,
                      // Bottom gap so the score panel's Save button can
                      // scroll clear of the floating Process photo FAB.
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        Stack(
                          children: [
                            GestureDetector(
                              onTapUp: (d) => _onRoiTap(d.localPosition),
                              child: RoiOverlay(
                                rois: _lastResult!.detectedRois!,
                                detailsRoiIndex: _lastResult!.detailsRoiIndex,
                                child: Image.file(
                                  File(_pickedImage!.path),
                                  width: MediaQuery.of(context).size.width,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ),
                            _floatingSideSelector,
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: DebugZoomChip(
                                label: 'ROI overlay',
                                bytes: _debugOverlayBytes,
                              ),
                            ),
                          ],
                        ),
                        if (_lastResult!.detectedRois!.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Text(
                              'Wrong box highlighted? Tap the correct Details '
                              'box to re-scan.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                        if (hasScore)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SaveScorePanel(
                              controllers: _fieldControllers,
                              initialTitle: _ocrTitle,
                              source: ScoreSource.loadImage,
                              // Proof image stored with the score: the ROI
                              // overlay render when this run produced one,
                              // else the original screenshot.
                              proofImageBytes: () async {
                                final overlay = _debugOverlayBytes.value;
                                if (overlay != null) return overlay;
                                final f = File(_pickedImage!.path);
                                return await f.exists()
                                    ? await f.readAsBytes()
                                    : null;
                              },
                              middleChildren: [
                                for (final key in _populatedKeys)
                                  if (key == 'flare')
                                    FlareDropdownField(
                                      controller: _fieldControllers[key]!,
                                    )
                                  else
                                    OCREditableField(
                                      keyName: key,
                                      controller: _fieldControllers[key]!,
                                    ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}

// Human-readable label for an OCR field key (the maps use camelCase keys).
String ocrFieldLabel(String key) {
  switch (key) {
    case 'maxCombo':
      return 'MAX COMBO';
    case 'exScore':
      return 'EX SCORE';
    default:
      return key.toUpperCase();
  }
}


// A single candidate reading for a field, used to render the clickable
// histogram in the camera flow (ordered by how many frames detected the value).
class OCRCandidate {
  final String value;
  final int count;
  // Fraction of samples that agreed on this value (0..1), drives the bar width.
  final double share;
  const OCRCandidate(this.value, this.count, this.share);
}

// An editable OCR field: a labelled TextField prefilled with the OCR result.
// In the camera flow it also renders a clickable [candidates] histogram (sorted
// by frame count); tapping a bar sets the field to that reading.
class OCREditableField extends StatelessWidget {
  final String keyName;
  final TextEditingController controller;
  // Optional alternative readings shown as a clickable histogram below the field.
  final List<OCRCandidate> candidates;
  // The current winning value, highlighted in the histogram.
  final String? winnerValue;
  // Called when the user changes the value — either by typing in the field or
  // tapping a histogram bar — so the parent can stop auto-prefilling this field.
  final ValueChanged<String>? onUserEdit;
  final double? confidence;
  final int? sampleCount;

  const OCREditableField({
    super.key,
    required this.keyName,
    required this.controller,
    this.candidates = const [],
    this.winnerValue,
    this.onUserEdit,
    this.confidence,
    this.sampleCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  ocrFieldLabel(keyName),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: judgmentColor(keyName),
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        onChanged: onUserEdit,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '—',
                          border: UnderlineInputBorder(),
                        ),
                      ),
                    ),
                    if (confidence != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          sampleCount != null
                              ? '${(confidence! * 100).round()}% ($sampleCount)'
                              : '${(confidence! * 100).round()}%',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (candidates.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in candidates)
                    _CandidateBar(
                      candidate: c,
                      isWinner: c.value == winnerValue,
                      onTap: () {
                        controller.text = c.value;
                        controller.selection = TextSelection.collapsed(
                            offset: c.value.length);
                        onUserEdit?.call(c.value);
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// The flare counterpart of SaveScorePanel's difficulty dropdown: a hard-set
// dropdown of the canonical flare ranks (I..IX, EX — the DDR World flare
// gauge), pre-selected by resolving the raw OCR reading (see
// [resolveOcrFlare]) and overridable by the user. Picking a rank writes the
// canonical value back into [controller] so the save flow reads it like any
// other field; the clear button empties it ("no flare"). Shared by the
// load-image and camera pages.
class FlareDropdownField extends StatelessWidget {
  final TextEditingController controller;
  // Called when the user picks a rank or clears the field, so the camera flow
  // can stop auto-prefilling it from the rolling average.
  final ValueChanged<String>? onUserEdit;
  final double? confidence;
  final int? sampleCount;

  const FlareDropdownField({
    super.key,
    required this.controller,
    this.onUserEdit,
    this.confidence,
    this.sampleCount,
  });

  @override
  Widget build(BuildContext context) {
    // Listen to the controller so live prefills from the camera aggregator
    // (which write straight into it) update the selected rank.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final raw = value.text.trim();
        final rank = resolveOcrFlare(raw);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'FLARE',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: rank,
                        isExpanded: true,
                        hint: Text(
                          // No rank matched the reading — show it so the user
                          // knows what the scan said while they pick.
                          raw.isEmpty ? 'None' : '"$raw"?',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        items: [
                          for (final r in kFlareRanks)
                            DropdownMenuItem(
                              value: r,
                              child: Row(
                                children: [
                                  Image.asset(flareRankIcon(r), height: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    r,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          controller.text = v;
                          onUserEdit?.call(v);
                        },
                      ),
                    ),
                    if (raw.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'No flare',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          controller.clear();
                          onUserEdit?.call('');
                        },
                      ),
                    if (confidence != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          sampleCount != null
                              ? '${(confidence! * 100).round()}% ($sampleCount)'
                              : '${(confidence! * 100).round()}%',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// A clickable histogram bar for one candidate reading. Tapping it sets the
// field to this value. The winning (modal) value is highlighted green.
class _CandidateBar extends StatelessWidget {
  const _CandidateBar({
    required this.candidate,
    required this.isWinner,
    required this.onTap,
  });

  final OCRCandidate candidate;
  final bool isWinner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = isWinner ? Colors.green : Colors.grey[400]!;
    final labelColor = theme.colorScheme.onSurface;
    final mutedColor = theme.colorScheme.onSurface.withOpacity(0.6);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                candidate.value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: labelColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: isWinner ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Stack(
                    children: [
                      Container(height: 12, color: theme.dividerColor),
                      FractionallySizedBox(
                        widthFactor: candidate.share.clamp(0.0, 1.0),
                        child: Container(height: 12, color: barColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '${candidate.count} · ${(candidate.share * 100).round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: mutedColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OCRKeyValue extends StatelessWidget {
  final String keyName;
  final String value;
  // Optional agreement ratio (0..1) shown as a faint percentage; used by the
  // live camera panel to convey how consistently this value was read.
  final double? confidence;
  // Optional number of samples that agreed on this value, shown as "(N)" beside
  // the percentage.
  final int? sampleCount;
  const OCRKeyValue(
      {super.key,
      required this.keyName,
      required this.value,
      this.confidence,
      this.sampleCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            keyName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: judgmentColor(keyName),
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (confidence != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    sampleCount != null
                        ? '${(confidence! * 100).round()}% ($sampleCount)'
                        : '${(confidence! * 100).round()}%',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
