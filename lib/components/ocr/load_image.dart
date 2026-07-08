import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ddr_md/components/ocr/save_score.dart';
import 'package:ddr_md/components/roi_overlay.dart';
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
  // Editable controllers per OCR field, prefilled from the result. Created
  // lazily when a result arrives and reused across results.
  final Map<String, TextEditingController> _fieldControllers = {};

  // Prefills the editable controllers from the OCR result, creating missing
  // ones. Only keys present (and non-empty) in [ocrStrings] get a field.
  void _syncFieldControllers(Map<String, String> ocrStrings) {
    for (final key in kOcrFieldOrder) {
      final value = ocrStrings[key]?.trim() ?? '';
      if (value.isEmpty) continue;
      final controller =
          _fieldControllers.putIfAbsent(key, () => TextEditingController());
      controller.text = value;
    }
  }

  List<String> get _populatedKeys =>
      kOcrFieldOrder.where((k) => _fieldControllers.containsKey(k)).toList();

  Future<void> _processImage() async {
    if (!_isReady || _isPicking || (!Platform.isIOS && !Platform.isAndroid)) {
      return;
    }
    setState(() {
      _isPicking = true;
      _lastResult = null; // Clear previous ROI data immediately
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
    await _ocrProcessor.init();
    if (mounted) setState(() => _isReady = true);
  }

  @override
  void initState() {
    super.initState();
    getApplicationDocumentsDirectory().then((dir) {
      tempDir = dir;
    });
    _ocrProcessor = OCRProcessor();
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
            _syncFieldControllers(result.ocrStrings);
          });
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
    _ocrProcessor.dispose();
    super.dispose();
  }

  bool get pickedImage => _pickedImage != null;
  bool get isProcessed => _lastResult != null;
  bool get isDetected =>
      _lastResult != null &&
      _lastResult!.isDetected &&
      _lastResult!.detectedRois != null;
  bool get detailsRoiIndex =>
      _lastResult != null && _lastResult!.detailsRoiIndex != -1;
  bool get hasScore =>
      _lastResult != null && _lastResult!.ocrStrings.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Load Image"),
      ),
      bottomNavigationBar: ElevatedButton(
        onPressed: _isReady ? _processImage : null,
        child: Text(_isReady ? 'Process photo' : 'Initialising…'),
      ),
      body: Center(
        child: _isPicking
            ? const CircularProgressIndicator()
            : ListView(
                shrinkWrap: true,
                children: [
                  isDetected
                      ? RoiOverlay(
                          rois: _lastResult!.detectedRois!,
                          detailsRoiIndex: _lastResult!.detailsRoiIndex,
                          child: Image.file(
                            File(_pickedImage!.path),
                            width: MediaQuery.of(context).size.width,
                            fit: BoxFit.fitWidth,
                          ),
                        )
                      : Center(
                          child: _isProcessing
                              ? const CircularProgressIndicator()
                              : Text(_pickedImage == null
                                  ? "Please pick image"
                                  : 'No DDR chart detected.\nPlease try another image.'),
                        ),
                  detailsRoiIndex
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Center(
                              child: Text(
                            "Details detected!",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.lightGreenAccent),
                          )),
                        )
                      : Container(),
                  if (hasScore)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final key in _populatedKeys)
                            OCREditableField(
                              keyName: key,
                              controller: _fieldControllers[key]!,
                            ),
                          SaveScorePanel(controllers: _fieldControllers),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// Human-readable label for an OCR field key (the maps use camelCase keys).
String ocrFieldLabel(String key) {
  switch (key) {
    case 'maxCombo':
      return 'MAX COMBO';
    default:
      return key.toUpperCase();
  }
}

// Accent color for an OCR field key — shared by the read-only and editable
// widgets. Returns null for keys with no special color so the caller falls back
// to the theme's default text color (important for dark mode).
Color? ocrColorForKey(String k) {
  switch (k.toLowerCase()) {
    case 'marvelous':
      return Colors.grey;
    case 'perfect':
      return Colors.yellow[700]!;
    case 'great':
      return Colors.green;
    case 'good':
      return Colors.blueAccent;
    case 'bad':
      return Colors.purpleAccent;
    default:
      return null;
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
                    color: ocrColorForKey(keyName),
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
              color: ocrColorForKey(keyName),
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
