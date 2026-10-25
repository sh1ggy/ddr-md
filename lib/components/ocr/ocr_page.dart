/// Name: OcrPage
/// Parent: Router
/// Description: The Camera tab: a live viewfinder that reads a cabinet's
/// results screen frame by frame, then the stopped view where the readings
/// are checked and saved as a score.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ddr_md/components/ocr/load_image.dart';
import 'package:ddr_md/components/ocr/ocr_shared.dart';
import 'package:ddr_md/components/ocr/save_score.dart';
import 'package:ddr_md/components/roi_painter.dart';
import 'package:ddr_md/helpers.dart' show judgmentColor, parseOcrNumber;
import 'package:ddr_md/models/db_models.dart' show ScoreSource;
import 'package:ddr_md/ocr_processor.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
      if (!mounted) return;
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
      debugPrint('Error initializing OCR session: $e');
      if (!mounted) return;
      context.go('/songs');
    }
  }

  Future<void> _toggleCamera() async {
    if (_isTogglingCamera) return;
    _isTogglingCamera = true;
    debugPrint('Toggle camera called. Current state: $_isCameraActive');
    try {
      if (_isCameraActive) {
        debugPrint('Stopping camera stream...');
        await _ocrProcessor.stop();
        setState(() {
          _isCameraActive = false;
          _hasRecorded = true;
        });
        debugPrint('Camera stopped. New state: $_isCameraActive');
      } else {
        debugPrint('Starting camera stream...');
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
        debugPrint('Camera started. New state: $_isCameraActive');
      }
    } catch (e) {
      debugPrint('Error toggling camera: $e');
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: const Text('Camera'),
        actions: <Widget>[
          HeaderButton(
            tooltip: 'Load image',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () async {
              final navigator = Navigator.of(context);
              // Stop the live session first — the subpage shouldn't run over
              // an active camera stream.
              if (_isCameraActive) await _toggleCamera();
              if (!mounted) return;
              navigator
                  .push(MaterialPageRoute(builder: (_) => const LoadImage()));
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: switch (cameraState) {
        CameraState.notReady =>
          const Center(child: CircularProgressIndicator()),
        CameraState.neverRecorded => Stack(
            children: [
              const _Viewfinder(),
              _floatingSideSelector(MediaQuery.paddingOf(context).top + 12),
            ],
          ),
        CameraState.inactive => _buildStoppedView(),
        CameraState.active => _buildActiveView(),
      },
      // Lifted clear of the floating tab bar, which the page runs under,
      // 10 above it like the other floating buttons (the FAB slot adds 16).
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
            bottom: (MediaQuery.paddingOf(context).bottom - 6)
                .clamp(0.0, double.infinity)),
        child: SizedBox(
          width: 132,
          // Disabled until both camera and OCR are ready. Stop is always
          // enabled once a session is active.
          child: VoltButton(
            onPressed: canStart ? _toggleCamera : null,
            color: _isCameraActive ? FloorPop.coral : FloorPop.volt,
            riser: _isCameraActive ? _coralRiser : FloorPop.voltRiser,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_isCameraActive
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded),
                const SizedBox(width: 6),
                Text(_isCameraActive ? 'Stop' : 'Start'),
              ],
            ),
          ),
        ),
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
      padding: clearOfBars(context, const EdgeInsets.only(bottom: 96)),
      children: [
        Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                foregroundPainter: _CameraRoiPainter(_roiData, _frameTick),
                child: _buildPreview(),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: _roiData,
                builder: (context, roi, _) =>
                    _Brackets(locked: (roi.$2 ?? -1) >= 0),
              ),
            ),
            _floatingSideSelector(12),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  _LockPill(
                    roiData: _roiData,
                    isProcessing: _ocrProcessor.isProcessing,
                    side: _detectionSide,
                  ),
                  const Spacer(),
                  _FpsCounter(fps: _fps),
                ],
              ),
            ),
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
  // side can always be changed before the next session starts. [top] is from
  // the top of whatever it floats over: the preview, or the whole page.
  Widget _floatingSideSelector(double top) => Positioned(
        top: top,
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
          subtitle:
              const Text('Show the binarized mask and matched Details crop'),
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
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label.toUpperCase(), style: FloorPop.of(context).label),
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
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
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
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('LAST CAPTURE', style: FloorPop.of(context).label),
              ),
              // Quick access to the zoomable ROI overlay without scrolling
              // down to the debug panels; hidden unless debug produced one.
              Stack(
                children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(18), child: framed),
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
          _floatingSideSelector(MediaQuery.paddingOf(context).top + 12),
        ],
      );
    }
    return Stack(
      children: [
        ListView(
          // Top padding clears the floating side picker.
          padding:
              clearOfBars(context, const EdgeInsets.fromLTRB(16, 64, 16, 96)),
          children: [
            _buildCapturePanel(),
            SaveScorePanel(
              controllers: _fieldControllers,
              initialTitle: _aggregator.best('title')?.value ?? '',
              source: ScoreSource.camera,
              // Proof image stored with the score: the ROI overlay render
              // when the debug toggle produced one this session, else the
              // last captured full-color frame that matched.
              proofImageBytes: () async =>
                  _debugOverlayBytes.value ?? _captureData.value?.bytes,
              middleChildren: [_buildEditableScorePanel()],
            ),
            // Latest debug images remain inspectable after stopping (the
            // notifiers keep their last values); the panel gates internally
            // on the toggle.
            _buildDebugControls(),
          ],
        ),
        _floatingSideSelector(MediaQuery.paddingOf(context).top + 12),
      ],
    );
  }

  // Live (recording) view: read-only rolling-average readout, the score on
  // its own card over a grid of the rest. Editing only happens once OCR is
  // stopped (see _buildEditableScorePanel).
  Widget _buildLiveScorePanel() {
    final pop = FloorPop.of(context);
    final score = _aggregator.best('score');
    final tiles = [
      for (final key in kOcrFieldOrder)
        if (key != 'title' && key != 'score')
          if (_aggregator.best(key) case final best?)
            _ReadoutTile(
              label: _tileLabel(key),
              value: best.value,
              confidence: best.confidence,
              color: judgmentColor(key, context: context),
            ),
    ];
    if (score == null && tiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('Reading score…',
            textAlign: TextAlign.center, style: TextStyle(color: pop.haze)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (score != null)
          _ReadoutTile(
            label: 'SCORE',
            value: score.value,
            confidence: score.confidence,
            large: true,
          ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.1,
          children: tiles,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('${_aggregator.detailsCount} READS', style: pop.label),
        ),
      ],
    );
  }

  static String _tileLabel(String key) => switch (key) {
        'marvelous' => 'MARV',
        'perfect' => 'PERF',
        'exScore' => 'EX',
        'maxCombo' => 'COMBO',
        'username' => 'PLAYER',
        _ => ocrFieldLabel(key),
      };

  // Stopped view: editable, prefilled fields. "Show values" reveals a clickable
  // candidate histogram per field — the way the user picks between detected
  // values (tapping a bar sets that field). Difficulty is excluded:
  // SaveScorePanel renders it as a dropdown of the matched song's charts.
  Widget _buildEditableScorePanel() {
    final bool showHistograms = _histogramsExpanded;
    final rows = <Widget>[
      for (final key in kOcrFieldOrder)
        if (key != 'title' && key != 'difficulty' && key != 'flare')
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
    // Flare renders as a hard-set rank dropdown (I..IX, EX) instead of a
    // free-text field, and shows even when no reading landed so the rank can
    // be set by hand. The dropdown replaces the candidate histogram as the
    // way to pick between values.
    if (rows.isNotEmpty) {
      rows.add(FlareDropdownField(
        controller: _controllerFor('flare'),
        confidence: _aggregator.best('flare')?.confidence,
        sampleCount: _aggregator.best('flare')?.count,
        onUserEdit: (_) => _userEditedFields.add('flare'),
      ));
    }
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
              onPressed: () =>
                  setState(() => _histogramsExpanded = !_histogramsExpanded),
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
          child: Text('${_aggregator.detailsCount} READS',
              style: FloorPop.of(context).label),
        ),
      ],
    );
  }
}

// Fields whose readings are numbers; everything else is tallied as raw text.
const Set<String> _numericKeys = {
  'score',
  'exScore',
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

  // Formats a tally value for display: numbers get thousands separators
  // (except EX score, which the game renders without them), text passes
  // through unchanged.
  static String _display(String key, Object value) =>
      value is int && key != 'exScore' ? _formatOcrNumber(value) : '$value';

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
      value: _display(key, top!.key),
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
        (value: _display(key, e.key), count: e.value, share: e.value / total),
    ];
  }
}

// The hard edge under the coral Stop button.
const _coralRiser = Color(0xFFB02E47);

/// The camera off: an empty viewfinder on the speed stripes.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return DecoratedBox(
      decoration: pop.stripes(color: pop.ink),
      child: Padding(
        padding:
            clearOfBars(context, const EdgeInsets.fromLTRB(40, 72, 40, 96)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: pop.riser.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const Positioned.fill(child: _Brackets(locked: false)),
                Center(
                  child:
                      Icon(Icons.videocam_outlined, size: 40, color: pop.haze),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Text('CAMERA IS OFF',
                style: FloorPop.display(18,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('Start, then hold the results screen in the frame',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: pop.haze)),
          ],
        ),
      ),
    );
  }
}

/// Viewfinder corners: Volt once the results panel is found, faint until.
class _Brackets extends StatelessWidget {
  const _Brackets({required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(
        color: locked ? FloorPop.volt : Colors.white.withValues(alpha: 0.5),
        width: 4);
    const r = Radius.circular(18);
    Widget corner(Alignment at) => Align(
          alignment: at,
          child: AnimatedContainer(
            duration: FloorPop.sixteenth,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border(
                top: at.y < 0 ? side : BorderSide.none,
                bottom: at.y > 0 ? side : BorderSide.none,
                left: at.x < 0 ? side : BorderSide.none,
                right: at.x > 0 ? side : BorderSide.none,
              ),
              borderRadius: BorderRadius.only(
                topLeft: at == Alignment.topLeft ? r : Radius.zero,
                topRight: at == Alignment.topRight ? r : Radius.zero,
                bottomLeft: at == Alignment.bottomLeft ? r : Radius.zero,
                bottomRight: at == Alignment.bottomRight ? r : Radius.zero,
              ),
            ),
          ),
        );
    return IgnorePointer(
      child: Stack(children: [
        corner(Alignment.topLeft),
        corner(Alignment.topRight),
        corner(Alignment.bottomLeft),
        corner(Alignment.bottomRight),
      ]),
    );
  }
}

/// Whether the latest frame found the results panel, for which side, with a
/// dot that pulses while a frame is being read.
class _LockPill extends StatefulWidget {
  const _LockPill(
      {required this.roiData, required this.isProcessing, required this.side});

  final ValueNotifier<(List<Rectangle<int>>, int?)> roiData;
  final ValueNotifier<bool> isProcessing;
  final DetectionSide side;

  @override
  State<_LockPill> createState() => _LockPillState();
}

class _LockPillState extends State<_LockPill>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: FloorPop.beat)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.side == DetectionSide.right ? '2P' : '1P';
    return ListenableBuilder(
      listenable: Listenable.merge([widget.roiData, widget.isProcessing]),
      builder: (context, _) {
        final locked = (widget.roiData.value.$2 ?? -1) >= 0;
        final color = locked ? FloorPop.volt : Colors.white;
        return AnimatedContainer(
          duration: FloorPop.sixteenth,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: locked
                ? const Color(0xE616122C)
                : Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            FadeTransition(
              opacity: widget.isProcessing.value
                  ? Tween(begin: 0.3, end: 1.0).animate(_pulse)
                  : const AlwaysStoppedAnimation(1),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Text(locked ? 'Locked on · $player' : 'Searching · $player',
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
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
        return Container(
          height: 34,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text('${value.toStringAsFixed(1)} FPS',
              style: FloorPop.readout(13, color: Colors.white)),
        );
      },
    );
  }
}

/// One live reading on a riser: label, value in the readout face, and a bar
/// for how many frames agree on it.
class _ReadoutTile extends StatelessWidget {
  const _ReadoutTile({
    required this.label,
    required this.value,
    required this.confidence,
    this.color,
    this.large = false,
  });

  final String label, value;
  final double confidence;
  final Color? color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: pop.riser,
          borderRadius: BorderRadius.circular(large ? 18 : 12)),
      child: Stack(children: [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: large ? 14 : 10, vertical: large ? 12 : 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label,
                  style: pop.label
                      .copyWith(letterSpacing: 0.7, color: color ?? pop.haze)),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: BeatSwap(
                    child: Text(value,
                        key: ValueKey(value),
                        style: FloorPop.readout(large ? 34 : 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          right: 0,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: FloorPop.eighth,
              curve: FloorPop.settle,
              widthFactor: confidence.clamp(0.0, 1.0),
              child: Container(
                  height: 3, color: FloorPop.volt.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CameraRoiPainter extends CustomPainter {
  _CameraRoiPainter(this.roiData, Listenable frameTick)
      : super(repaint: frameTick);

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
