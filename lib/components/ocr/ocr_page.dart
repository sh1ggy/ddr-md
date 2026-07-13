library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ddr_md/components/ocr/load_image.dart';
import 'package:ddr_md/components/ocr/ocr_shared.dart';
import 'package:ddr_md/components/ocr/save_score.dart';
import 'package:ddr_md/components/roi_painter.dart';
import 'package:ddr_md/helpers.dart' show parseOcrNumber;
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

enum CameraState {
  /// OCR processor or camera controller not yet initialised.
  notReady,
  /// Camera is ready but no OCR session has been started yet.
  neverRecorded,
  /// A session has been run and stopped; cached results are visible.
  inactive,
  /// Live OCR stream is active.
  active,
}

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

late Directory tempDir;
String get tempPath => '${tempDir.path}/temp.jpg';

class _OcrPageState extends State<OcrPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _isCameraActive = false;
  bool _isTogglingCamera = false;
  bool _hasRecorded = false;
  late OCRProcessor _ocrProcessor;
  final _OcrAggregator _aggregator = _OcrAggregator();
  // Editable controllers per OCR field, prefilled from the rolling average.
  final Map<String, TextEditingController> _fieldControllers = {};
  // Fields the user has manually edited or chosen an alternative for; the live
  // aggregator no longer overwrites these.
  final Set<String> _userEditedFields = {};
  double _camFrameToScreenScale = 0;
  int _rawFrameWidth = 0;
  int _rawFrameHeight = 0;

  DebugImageType _debugImageType = DebugImageType.none;
  DetectionSide _detectionSide = DetectionSide.left;
  // Whether the per-field candidate histograms are revealed (the way the user
  // picks between detected values in the stopped view).
  bool _histogramsExpanded = false;
  final ValueNotifier<Uint8List?> _debugMaskBytes = ValueNotifier(null);
  final ValueNotifier<Uint8List?> _debugCropBytes = ValueNotifier(null);
  final ValueNotifier<Uint8List?> _debugOverlayBytes = ValueNotifier(null);
  final ValueNotifier<_CaptureView?> _captureData = ValueNotifier(null);
  final ValueNotifier<(List<Rectangle<int>>, int?)> _roiData =
      ValueNotifier(([], null));
  final ValueNotifier<int> _frameTick = ValueNotifier(0);
  late final Ticker _ticker;

  final ValueNotifier<double> _fps = ValueNotifier(0);
  final List<Duration> _frameTimes = [];
  final Stopwatch _fpsClock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();

    // Add observer to listen for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Repaint the ROI overlay every frame from the last-known result.
    _ticker = createTicker((_) => _frameTick.value++)..start();

    _detectionSide = savedDetectionSide();

    _ocrProcessor = OCRProcessor();
    _ocrProcessor.side = _detectionSide;
    _ocrProcessor.streamResultController.stream.listen((result) {
      _recordFrameTime();
      // The native session reports the processed-frame dimensions (the pixel
      // space the ROIs live in). Derive the on-screen scale from those.
      if (result.frameWidth > 0) {
        _rawFrameWidth = result.frameWidth;
        _rawFrameHeight = result.frameHeight;
        _camFrameToScreenScale =
            MediaQuery.of(context).size.width / result.frameWidth;
      }
      final double scale = _camFrameToScreenScale;

      final scaled = (result.detectedRois ?? []).map((r) {
        return Rectangle<int>(
          (r.left * scale).toInt(),
          (r.top * scale).toInt(),
          (r.width * scale).toInt(),
          (r.height * scale).toInt(),
        );
      }).toList();
      _roiData.value = (scaled, result.detailsRoiIndex);
      final detailsFound =
          result.detailsRoiIndex != null && result.detailsRoiIndex! >= 0;
      if (result.debugMaskBytes != null) {
        _debugMaskBytes.value = result.debugMaskBytes;
      }
      if (result.debugDetailsCropBytes != null) {
        _debugCropBytes.value = result.debugDetailsCropBytes;
      }
      if (result.debugOverlayBytes != null) {
        _debugOverlayBytes.value = result.debugOverlayBytes;
      }
      if (result.captureBytes != null) {
        // Native reports dims already in the processed (upright) orientation,
        // so no per-platform swap is needed any more.
        _captureData.value = _CaptureView(
          bytes: result.captureBytes!,
          rois: result.detectedRois ?? const [],
          detailsRoiIndex: result.detailsRoiIndex,
          frameWidth: _rawFrameWidth,
          frameHeight: _rawFrameHeight,
        );
      }
      if (detailsFound && result.ocrStrings.isNotEmpty) {
        final added = _aggregator.add(result.ocrStrings);
        if (added) {
          _prefillFromAggregator();
          setState(() {});
        }
      }
    });

    getTemporaryDirectory().then((dir) => tempDir = dir);
    _initOcr();
  }

  @override
  void dispose() {
    // TODO: use actual lifecycle events to call asynchronous controller methods
    _ticker.dispose();
    _frameTick.dispose();
    _roiData.dispose();
    _debugMaskBytes.dispose();
    _debugCropBytes.dispose();
    _debugOverlayBytes.dispose();
    _captureData.dispose();
    _fps.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    _ocrProcessor.dispose();
    super.dispose();
  }

  void _recordFrameTime() {
    final now = _fpsClock.elapsed;
    _frameTimes.add(now);
    const window = Duration(seconds: 1);
    while (_frameTimes.isNotEmpty && now - _frameTimes.first > window) {
      _frameTimes.removeAt(0);
    }
    if (_frameTimes.length < 2) {
      _fps.value = 0;
      return;
    }
    final span = now - _frameTimes.first;
    _fps.value = span.inMicroseconds <= 0
        ? 0
        : (_frameTimes.length - 1) * 1e6 / span.inMicroseconds;
  }

  TextEditingController _controllerFor(String key) =>
      _fieldControllers.putIfAbsent(key, () => TextEditingController());

  // Pushes the rolling-average winner into each field's controller, unless the
  // user has manually edited / chosen an alternative for that field.
  void _prefillFromAggregator() {
    for (final key in kOcrFieldOrder) {
      if (_userEditedFields.contains(key)) continue;
      final best = _aggregator.best(key);
      if (best == null) continue;
      final controller = _controllerFor(key);
      if (controller.text != best.value) controller.text = best.value;
    }
  }

  Future<void> _initOcr() async {
    try {
      // init() copies the ONNX models + details template to disk, allocates
      // the native preview texture and the resident OCR instance, and returns
      // the texture id + preview dims.
      await _ocrProcessor.init();
      if (mounted) setState(() {});
    } catch (e) {
      print('Error initializing OCR session: $e');
      if (!mounted) return;
      Navigator.pushNamed(context, "/");
    }
  }

  Future<void> _toggleCamera() async {
    if (_isTogglingCamera) return;
    _isTogglingCamera = true;
    print('Toggle camera called. Current state: $_isCameraActive');
    try {
      if (_isCameraActive) {
        print('Stopping camera stream...');
        await _ocrProcessor.stop();
        setState(() {
          _isCameraActive = false;
          _hasRecorded = true;
        });
        print('Camera stopped. New state: $_isCameraActive');
      } else {
        print('Starting camera stream...');
        setState(() {
          _isCameraActive = true;
          _aggregator.clear();
          _userEditedFields.clear();
          for (final c in _fieldControllers.values) {
            c.clear();
          }
          _roiData.value = ([], null);
          _debugMaskBytes.value = null;
          _debugCropBytes.value = null;
          _debugOverlayBytes.value = null;
          _captureData.value = null;
          _frameTimes.clear();
          _fps.value = 0;
        });
        await _ocrProcessor.start();
        print('Camera started. New state: $_isCameraActive');
      }
    } catch (e) {
      print('Error toggling camera: $e');
      // Roll the UI back if start/stop threw (e.g. permission denied).
      if (mounted) setState(() => _isCameraActive = !_isCameraActive);
    } finally {
      _isTogglingCamera = false;
    }
  }

  bool get cameraReady => _ocrProcessor.isReady;

  bool get _ocrReady => _ocrProcessor.isReady;

  CameraState get cameraState {
    if (!cameraReady || !_ocrReady) return CameraState.notReady;
    if (_isCameraActive) return CameraState.active;
    if (_hasRecorded) return CameraState.inactive;
    return CameraState.neverRecorded;
  }

  @override
  Widget build(BuildContext context) {
    final bool fullyReady = cameraReady && _ocrReady;
    final bool canStart = _isCameraActive || fullyReady;

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        title: const Text(
          'Camera',
          style: TextStyle(
              fontSize: 20,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
        actions: <Widget>[
          IconButton(
            tooltip: 'Load image',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () async {
              final navigator = Navigator.of(context);
              // Stop the live session first — the subpage shouldn't run over
              // an active camera stream.
              if (_isCameraActive) await _toggleCamera();
              if (!mounted) return;
              navigator.push(
                  MaterialPageRoute(builder: (_) => const LoadImage()));
            },
          ),
        ],
      ),
      body: switch (cameraState) {
        CameraState.notReady =>
          const Center(child: CircularProgressIndicator()),
        CameraState.neverRecorded => Stack(
            children: [
              const OcrEmptyState(
                icon: Icons.videocam_outlined,
                title: 'Camera is off',
                subtitle: 'Start OCR to begin detecting scores',
              ),
              _floatingSideSelector,
            ],
          ),
        CameraState.inactive => _buildStoppedView(),
        CameraState.active => _buildActiveView(),
      },
      floatingActionButton: FloatingActionButton(
        // Disabled (null onPressed + grey) until both camera and OCR are
        // ready. Stop is always enabled once a session is active.
        onPressed: canStart ? _toggleCamera : null,
        backgroundColor: _isCameraActive
            ? Colors.red
            : canStart
                ? null // theme default
                : Colors.grey.shade400,
        child: Icon(_isCameraActive ? Icons.stop : Icons.play_arrow),
      ),
    );
  }

  Widget _buildPreview() {
    final id = _ocrProcessor.textureId;
    if (id == null) {
      return const AspectRatio(
        aspectRatio: 3 / 4,
        child: ColoredBox(color: Colors.black),
      );
    }
    // The camera renders sensor-landscape frames directly into the texture
    // (GPU path); rotate the widget to display upright. The ROI overlay is
    // painted OUTSIDE this RotatedBox (in the upright OCR pixel space), so it
    // stays aligned as long as preview and analysis share an aspect ratio.
    final ar = _ocrProcessor.previewAspectRatio;
    final rotated = RotatedBox(
      quarterTurns: _ocrProcessor.previewQuarterTurns,
      child: Texture(textureId: id),
    );
    return ar > 0 ? AspectRatio(aspectRatio: ar, child: rotated) : rotated;
  }

  Widget _buildActiveView() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                foregroundPainter: _CameraRoiPainter(_roiData, _frameTick),
                child: _buildPreview(),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _ProcessingDot(isProcessing: _ocrProcessor.isProcessing),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _FpsCounter(fps: _fps),
            ),
            _floatingSideSelector,
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildDebugControls(),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildLiveScorePanel(),
        ),
      ],
    );
  }

  void _setDetectionSide(DetectionSide side) {
    if (side == _detectionSide) return;
    setState(() => _detectionSide = side);
    _ocrProcessor.side = side;
  }

  // Floats top-centre over every camera state (off, live, stopped) so the
  // side can always be changed before the next session starts.
  Widget get _floatingSideSelector => Positioned(
        top: 12,
        left: 0,
        right: 0,
        child: DetectionSideSelector(
          value: _detectionSide,
          onChanged: _setDetectionSide,
          overlay: true,
        ),
      );

  void _openDebugViewer(String label, ValueNotifier<Uint8List?> notifier) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DebugImageViewer(label: label, bytes: notifier),
    ));
  }

  void _setDebugEnabled(bool enabled) {
    final type = enabled ? DebugImageType.on : DebugImageType.none;
    setState(() => _debugImageType = type);
    _ocrProcessor.debugImageType = type;
    if (!enabled) {
      _debugMaskBytes.value = null;
      _debugCropBytes.value = null;
      _debugOverlayBytes.value = null;
    }
  }

  Widget _buildDebugControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Debug images'),
          subtitle: const Text('Show the binarized mask and matched Details crop'),
          value: _debugImageType == DebugImageType.on,
          onChanged: _setDebugEnabled,
        ),
        if (_debugImageType == DebugImageType.on) ...[
          _buildDebugImagePanel(
            label: 'Mask (latest frame)',
            notifier: _debugMaskBytes,
            emptyText: 'Waiting for mask…',
          ),
          _buildDebugImagePanel(
            label: 'Details crop (last match)',
            notifier: _debugCropBytes,
            emptyText: 'No Details matched yet…',
          ),
          _buildDebugImagePanel(
            label: 'ROI overlay (last match)',
            notifier: _debugOverlayBytes,
            emptyText: 'No overlay yet…',
          ),
        ],
      ],
    );
  }

  Widget _buildDebugImagePanel({
    required String label,
    required ValueNotifier<Uint8List?> notifier,
    required String emptyText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
          ),
          ValueListenableBuilder<Uint8List?>(
            valueListenable: notifier,
            builder: (context, bytes, _) {
              if (bytes == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              // Zoom-in is stopped-view only: pushing the viewer over a live
              // session would leave the camera streaming behind an opaque
              // route (same reason Load Image stops the session first).
              return GestureDetector(
                onTap: _isCameraActive
                    ? null
                    : () => _openDebugViewer(label, notifier),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    color: Colors.black,
                  ),
                  child: Stack(
                    children: [
                      Image.memory(
                        bytes,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                      ),
                      if (!_isCameraActive)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(Icons.zoom_in,
                              size: 16, color: Colors.white54),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCapturePanel() {
    return ValueListenableBuilder<_CaptureView?>(
      valueListenable: _captureData,
      builder: (context, data, _) {
        if (data == null) return const SizedBox.shrink();

        final Widget framed = CustomPaint(
          foregroundPainter: _CaptureRoiPainter(
            rois: data.rois,
            detailsRoiIndex: data.detailsRoiIndex,
            frameWidth: data.frameWidth,
            frameHeight: data.frameHeight,
          ),
          child: Image.memory(
            data.bytes,
            gaplessPlayback: true,
            fit: BoxFit.contain,
          ),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  "Last capture",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // Quick access to the zoomable ROI overlay without scrolling
              // down to the debug panels; hidden unless debug produced one.
              Stack(
                children: [
                  framed,
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: DebugZoomChip(
                      label: 'ROI overlay',
                      bytes: _debugOverlayBytes,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStoppedView() {
    // Nothing detected in the last session: skip the capture/debug chrome
    // entirely and centre the empty state. The side picker stays on top —
    // switching side is the likely fix before starting OCR again.
    if (_aggregator.detailsCount == 0) {
      return Stack(
        children: [
          ListenableBuilder(
            listenable: Listenable.merge(
                [_ocrProcessor.isProcessing, _ocrProcessor.isDraining]),
            builder: (context, _) {
              final busy = _ocrProcessor.isProcessing.value ||
                  _ocrProcessor.isDraining.value;
              // Results can still land while the stop drains in-flight frames.
              if (busy) return const Center(child: CircularProgressIndicator());
              return const OcrEmptyState(
                icon: Icons.search_off,
                title: 'No score detected',
                subtitle: 'Start OCR again and keep the results screen in view',
              );
            },
          ),
          _floatingSideSelector,
        ],
      );
    }
    return Stack(
      children: [
        ListView(
          // Top padding clears the floating side picker.
          padding: const EdgeInsets.fromLTRB(16, 64, 16, 96),
          children: [
            _buildCapturePanel(),
            SaveScorePanel(
              controllers: _fieldControllers,
              initialTitle: _aggregator.best('title')?.value ?? '',
              middleChildren: [_buildEditableScorePanel()],
            ),
            // Latest debug images remain inspectable after stopping (the
            // notifiers keep their last values); the panel gates internally
            // on the toggle.
            _buildDebugControls(),
          ],
        ),
        _floatingSideSelector,
      ],
    );
  }

  // Live (recording) view: read-only rolling-average readout. Editing only
  // happens once OCR is stopped (see _buildEditableScorePanel).
  Widget _buildLiveScorePanel() {
    final rows = <Widget>[
      for (final key in kOcrFieldOrder)
        if (key != 'title')
          if (_aggregator.best(key) case final best?)
            OCRKeyValue(
              keyName: ocrFieldLabel(key),
              value: best.value,
              confidence: best.confidence,
              sampleCount: best.count,
            ),
    ];
    return _scorePanelShell(
      rows: rows,
      empty: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          "Reading score…",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // Stopped view: editable, prefilled fields. "Show values" reveals a clickable
  // candidate histogram per field — the way the user picks between detected
  // values (tapping a bar sets that field). Difficulty is excluded:
  // SaveScorePanel renders it as a dropdown of the matched song's charts.
  Widget _buildEditableScorePanel() {
    final bool showHistograms = _histogramsExpanded;
    final rows = <Widget>[
      for (final key in kOcrFieldOrder)
        if (key != 'title' && key != 'difficulty')
          if (_aggregator.best(key) case final best?)
            OCREditableField(
              keyName: key,
              controller: _controllerFor(key),
              confidence: best.confidence,
              sampleCount: best.count,
              winnerValue: best.value,
              candidates: showHistograms
                  ? [
                      for (final c in _aggregator.candidates(key))
                        OCRCandidate(c.value, c.count, c.share),
                    ]
                  : const [],
              onUserEdit: (_) => _userEditedFields.add(key),
          ),
    ];
    return _scorePanelShell(
      rows: rows,
      empty: const OcrEmptyState(
        icon: Icons.search_off,
        title: 'No score detected',
        subtitle: 'Start OCR again and keep the results screen in view',
      ),
      showToggle: true,
    );
  }

  Widget _scorePanelShell({
    required List<Widget> rows,
    required Widget empty,
    bool showToggle = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showToggle && rows.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(
                  () => _histogramsExpanded = !_histogramsExpanded),
              icon: Icon(
                _histogramsExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(_histogramsExpanded ? 'Hide values' : 'Show values'),
            ),
          ),
        if (rows.isEmpty) empty else ...rows,
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            "Successful detections: ${_aggregator.detailsCount}",
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// Fields whose readings are numbers; everything else is tallied as raw text.
const Set<String> _numericKeys = {
  'score',
  'marvelous',
  'perfect',
  'great',
  'good',
  'miss',
  'maxCombo',
};

// Renders an integer with thousands separators for display ("999940" ->
// "999,940").
String _formatOcrNumber(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

// Tallies OCR readings across frames; the modal value per field is the result.
// Numeric fields ([_numericKeys]) are tallied by their parsed integer, so
// differently formatted strings for the same number ("999,940" and "999940")
// count as one value; other fields tally by their raw text.
class _OcrAggregator {
  // key -> tally value (int for numeric fields, String otherwise) -> count
  final Map<String, Map<Object, int>> _counts = {};
  int _detailsCount = 0;

  int get detailsCount => _detailsCount;

  bool add(Map<String, String> strings) {
    bool anyAdded = false;
    strings.forEach((key, raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return;
      final Object? value =
          _numericKeys.contains(key) ? parseOcrNumber(trimmed) : trimmed;
      if (value == null) return;
      final tally = _counts.putIfAbsent(key, () => {});
      tally[value] = (tally[value] ?? 0) + 1;
      anyAdded = true;
    });
    if (anyAdded) _detailsCount++;
    return anyAdded;
  }

  void clear() {
    _counts.clear();
    _detailsCount = 0;
  }

  // Formats a tally value for display: numbers get thousands separators, text
  // passes through unchanged.
  static String _display(Object value) =>
      value is int ? _formatOcrNumber(value) : value as String;

  ({String value, double confidence, int count})? best(String key) {
    final tally = _counts[key];
    if (tally == null || tally.isEmpty) return null;
    var total = 0;
    MapEntry<Object, int>? top;
    for (final entry in tally.entries) {
      total += entry.value;
      if (top == null || entry.value > top.value) top = entry;
    }
    return (
      value: _display(top!.key),
      confidence: top.value / total,
      count: top.value,
    );
  }

  List<({String value, int count, double share})> candidates(String key) {
    final tally = _counts[key];
    if (tally == null || tally.isEmpty) return const [];
    final total = tally.values.fold<int>(0, (sum, c) => sum + c);
    final entries = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries)
        (value: _display(e.key), count: e.value, share: e.value / total),
    ];
  }
}

class _ProcessingDot extends StatefulWidget {
  const _ProcessingDot({required this.isProcessing});

  final ValueNotifier<bool> isProcessing;

  @override
  State<_ProcessingDot> createState() => _ProcessingDotState();
}

class _ProcessingDotState extends State<_ProcessingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isProcessing,
      builder: (context, active, _) {
        return AnimatedOpacity(
          opacity: active ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: FadeTransition(
            opacity: _opacity,
            child: const SizedBox(
              width: 10,
              height: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FpsCounter extends StatelessWidget {
  const _FpsCounter({required this.fps});

  final ValueNotifier<double> fps;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fps,
      builder: (context, value, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              '${value.toStringAsFixed(1)} fps',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CameraRoiPainter extends CustomPainter {
  _CameraRoiPainter(this.roiData, Listenable frameTick) : super(repaint: frameTick);

  final ValueNotifier<(List<Rectangle<int>>, int?)> roiData;

  @override
  void paint(Canvas canvas, Size size) {
    final (rois, detailsRoiIndex) = roiData.value;
    paintRois(canvas, rois, detailsRoiIndex);
  }

  @override
  bool shouldRepaint(covariant _CameraRoiPainter oldDelegate) => false;
}

class _CaptureView {
  const _CaptureView({
    required this.bytes,
    required this.rois,
    required this.detailsRoiIndex,
    required this.frameWidth,
    required this.frameHeight,
  });

  final Uint8List bytes;
  final List<Rectangle<int>> rois;
  final int? detailsRoiIndex;
  final int frameWidth;
  final int frameHeight;
}

class _CaptureRoiPainter extends CustomPainter {
  _CaptureRoiPainter({
    required this.rois,
    required this.detailsRoiIndex,
    required this.frameWidth,
    required this.frameHeight,
  });

  final List<Rectangle<int>> rois;
  final int? detailsRoiIndex;
  final int frameWidth;
  final int frameHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (frameWidth <= 0 || frameHeight <= 0) return;
    final double sx = size.width / frameWidth;
    final double sy = size.height / frameHeight;
    final scaled = rois
        .map((r) => Rectangle<int>(
              (r.left * sx).round(),
              (r.top * sy).round(),
              (r.width * sx).round(),
              (r.height * sy).round(),
            ))
        .toList();
    paintRois(canvas, scaled, detailsRoiIndex);
  }

  @override
  bool shouldRepaint(covariant _CaptureRoiPainter oldDelegate) =>
      rois != oldDelegate.rois ||
      detailsRoiIndex != oldDelegate.detailsRoiIndex ||
      frameWidth != oldDelegate.frameWidth ||
      frameHeight != oldDelegate.frameHeight;
}
