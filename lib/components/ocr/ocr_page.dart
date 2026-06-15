library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:ddr_md/components/ocr/load_image.dart';
import 'package:ddr_md/components/roi_painter.dart';
import 'package:ddr_md/models/settings_model.dart';
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

// Stable display order for the OCR'd score fields.
const List<String> _ocrKeyOrder = [
  'score',
  'marvelous',
  'perfect',
  'great',
  'good',
  'miss',
];

class _OcrPageState extends State<OcrPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _isCameraActive = false;
  bool _isTogglingCamera = false;
  bool _hasRecorded = false;
  CameraController? _controller;
  late OCRProcessor _ocrProcessor;
  final _OcrAggregator _aggregator = _OcrAggregator();
  double _camFrameToScreenScale = 0;
  int _rawFrameWidth = 0;
  int _rawFrameHeight = 0;

  CameraImage? _lastFrame;

  DebugImageType _debugImageType = DebugImageType.none;
  DetectionSide _detectionSide = DetectionSide.left;
  bool _histogramsExpanded = false;
  final ValueNotifier<Uint8List?> _debugMaskBytes = ValueNotifier(null);
  final ValueNotifier<Uint8List?> _debugCropBytes = ValueNotifier(null);
  final ValueNotifier<_CaptureView?> _captureData = ValueNotifier(null);
  final ValueNotifier<(List<Rectangle<int>>, int?)> _roiData =
      ValueNotifier(([], null));
  final ValueNotifier<int> _frameTick = ValueNotifier(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();

    // Add observer to listen for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Repaint the ROI overlay every frame from the last-known result.
    _ticker = createTicker((_) => _frameTick.value++)..start();

    final savedSideIndex = Settings.getInt(Settings.detectionSideKey);
    // Stored as enum index; fall back to left when unset or invalid (the
    // SharedPreferences default of 0 maps to DetectionSide.first which we
    // never expose as a user choice).
    if (savedSideIndex == DetectionSide.right.index) {
      _detectionSide = DetectionSide.right;
    } else {
      _detectionSide = DetectionSide.left;
    }

    _ocrProcessor = OCRProcessor();
    _ocrProcessor.side = _detectionSide;
    _ocrProcessor.streamResultController.stream.listen((result) {
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
      if (result.captureBytes != null) {
        final int srcW = Platform.isAndroid ? _rawFrameHeight : _rawFrameWidth;
        final int srcH = Platform.isAndroid ? _rawFrameWidth : _rawFrameHeight;
        _captureData.value = _CaptureView(
          bytes: result.captureBytes!,
          rois: result.detectedRois ?? const [],
          detailsRoiIndex: result.detailsRoiIndex,
          frameWidth: srcW,
          frameHeight: srcH,
        );
      }
      if (detailsFound && result.ocrStrings.isNotEmpty) {
        final added = _aggregator.add(result.ocrStrings);
        if (added) setState(() {});
      }
    });

    getTemporaryDirectory().then((dir) => tempDir = dir);
    _initCamera();
  }

  @override
  void dispose() {
    // TODO: use actual lifecycle events to call asynchronous controller methods
    _ticker.dispose();
    _frameTick.dispose();
    _roiData.dispose();
    _debugMaskBytes.dispose();
    _debugCropBytes.dispose();
    _captureData.dispose();
    _controller?.dispose();
    _controller = null;
    _ocrProcessor.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final ocrFuture = _ocrProcessor.init().then((_) => _ocrProcessor.initActor());
      final camerasFuture = availableCameras();

      final cameras = await camerasFuture;
      if (cameras.isEmpty) throw Exception('No cameras available');

      _controller = CameraController(
        cameras[0],
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();

      if (mounted) setState(() {});

      await ocrFuture;

      print('AS: ${_controller!.value.aspectRatio}'
          '   SIZE: ${_controller!.value.previewSize}'
          '   ORIENTATION: ${_controller!.value.deviceOrientation}'
          '   RES PRESET: ${_controller!.resolutionPreset}'
          '   IMG FMT GROUP: ${_controller!.imageFormatGroup}'
          '   CAMERA SENSOR: ${cameras[0].sensorOrientation}');

      if (mounted) setState(() {});
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
      if (!mounted) return;
      Navigator.pushNamed(context, "/");
    } catch (e) {
      if (!mounted) return;
      Navigator.pushNamed(context, "/");
    }
  }

  void _requestDump() async {
    if (_lastFrame == null) {
      print('No frame to dump.');
      return;
    }
    var image = _lastFrame!;

    Directory? dir = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();

    if (dir == null) {
      print('no dir');
      return;
    }
    print(dir.path);
    if (Platform.isAndroid) {
      _dumpAndroidYuv(image, dir);
    } else if (Platform.isIOS) {
      _dumpIos(image, dir);
    }
  }

  void _dumpAndroidYuv(CameraImage image, Directory dir) async {
    // Write Y plane
    final yFile = File('${dir.path}/yuv_y_plane.raw');
    await yFile.writeAsBytes(image.planes[0].bytes);

    // Write U plane
    final uFile = File('${dir.path}/yuv_u_plane.raw');
    await uFile.writeAsBytes(image.planes[1].bytes);

    // Write V plane
    final vFile = File('${dir.path}/yuv_v_plane.raw');
    await vFile.writeAsBytes(image.planes[2].bytes);

    // Write metadata
    final metaFile = File('${dir.path}/yuv_metadata.txt');
    await metaFile.writeAsString('''
Width: ${image.width}
Height: ${image.height}
Y size: ${image.planes[0].bytes.length}
U size: ${image.planes[1].bytes.length}
V size: ${image.planes[2].bytes.length}
Format: ${image.format.group}
    ''');
    print("ANDROID DUMPED");
  }

  void _dumpIos(CameraImage image, Directory dir) async {
    final bgraFile = File('${dir.path}/bgra8888.raw');
    await bgraFile.writeAsBytes(image.planes[0].bytes);

    final metaFile = File('${dir.path}/metadata.txt');
    await metaFile.writeAsString('''
Platform: iOS
Format: BGRA8888
Width: ${image.width}
Height: ${image.height}
Bytes: ${image.planes[0].bytes.length}
BytesPerRow: ${image.planes[0].bytesPerRow}
''');
    print("iOS DUMPED");
  }

  // TODO: handle lifecycle events to stop debug from breaking
  void _processImage(CameraImage image) {
    int rotation = _controller?.description.sensorOrientation ?? 0;
    int w = 0;
    if (Platform.isAndroid) {
      w = (rotation == 0 || rotation == 180) ? image.width : image.height;
    } else if (Platform.isIOS) {
      w = image.width;
    }

    _camFrameToScreenScale = MediaQuery.of(context).size.width / w;
    _rawFrameWidth = image.width;
    _rawFrameHeight = image.height;

    _ocrProcessor.processVideostreamFrame(image, rotation);
    _lastFrame = image;
  }

  Future<void> _toggleCamera() async {
    if (_isTogglingCamera) return;
    _isTogglingCamera = true;
    print('Toggle camera called. Current state: $_isCameraActive');
    try {
      if (_isCameraActive) {
        print('Stopping camera stream...');
        _ocrProcessor.beginDraining();
        if (_controller?.value.isStreamingImages ?? false) {
          await _controller!.stopImageStream();
        }
        setState(() {
          _isCameraActive = false;
          _hasRecorded = true;
        });
        print('Camera stopped. New state: $_isCameraActive');
      } else {
        // Start the camera
        print('Starting camera stream...');
        if (_controller != null &&
            _controller!.value.isInitialized &&
            !(_controller!.value.isStreamingImages)) {
          _ocrProcessor.cancelDraining();
          await _controller!.startImageStream(_processImage);
          setState(() {
            _isCameraActive = true;
            _aggregator.clear();
            _roiData.value = ([], null);
            _debugMaskBytes.value = null;
            _debugCropBytes.value = null;
            _captureData.value = null;
          });
          print('Camera started. New state: $_isCameraActive');
        } else {
          print('Controller not initialized, null, or already streaming');
        }
      }
    } catch (e) {
      print('Error toggling camera: $e');
    } finally {
      _isTogglingCamera = false;
    }
  }

  bool get cameraReady =>
      _controller != null && _controller!.value.isInitialized;

  bool get _ocrReady => _ocrProcessor.toIsolate != null;

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
        title: const Text("Camera"),
      ),
      body: Column(
        children: [
          _buildSideSelector(),
          Expanded(
            child: switch (cameraState) {
              CameraState.notReady =>
                const Center(child: CircularProgressIndicator()),
              CameraState.neverRecorded => Center(
                  child: Text(
                    "Start OCR to begin detection",
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              CameraState.inactive => _buildStoppedView(),
              CameraState.active => _buildActiveView(),
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Disabled (null onPressed + grey) until both camera and OCR are
        // ready. Stop is always enabled once a session is active.
        onPressed: canStart ? _toggleCamera : null,
        backgroundColor: _isCameraActive
            ? Colors.red
            : canStart
                ? null // theme default
                : Colors.grey.shade400,
        icon: Icon(_isCameraActive ? Icons.stop : Icons.play_arrow),
        label: Text(_isCameraActive ? 'Stop OCR' : 'Start OCR'),
      ),
    );
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
                child: CameraPreview(_controller!),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _ProcessingDot(isProcessing: _ocrProcessor.isProcessing),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildDebugControls(),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildScorePanel(live: true),
        ),
      ],
    );
  }

  void _setDetectionSide(DetectionSide side) {
    if (side == _detectionSide) return;
    setState(() => _detectionSide = side);
    _ocrProcessor.side = side;
    Settings.setInt(Settings.detectionSideKey, side.index);
  }

  Widget _buildSideSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: SegmentedButton<DetectionSide>(
          segments: const [
            ButtonSegment(
                value: DetectionSide.left, label: Text('Left (1P)')),
            ButtonSegment(
                value: DetectionSide.right, label: Text('Right (2P)')),
          ],
          selected: {_detectionSide},
          onSelectionChanged: (s) => _setDetectionSide(s.first),
        ),
      ),
    );
  }

  void _setDebugEnabled(bool enabled) {
    final type = enabled ? DebugImageType.on : DebugImageType.none;
    setState(() => _debugImageType = type);
    _ocrProcessor.debugImageType = type;
    if (!enabled) {
      _debugMaskBytes.value = null;
      _debugCropBytes.value = null;
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
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  color: Colors.black,
                ),
                child: Image.memory(
                  bytes,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
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
              framed,
            ],
          ),
        );
      },
    );
  }

  Widget _buildStoppedView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const Text(
          "Camera stopped",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ListenableBuilder(
          listenable: Listenable.merge(
              [_ocrProcessor.isProcessing, _ocrProcessor.isDraining]),
          builder: (context, _) {
            final busy =
                _ocrProcessor.isProcessing.value || _ocrProcessor.isDraining.value;
            if (!busy) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Finalising…",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildCapturePanel(),
        _buildScorePanel(live: false),
      ],
    );
  }

  Widget _buildScorePanel({required bool live}) {
    final bool showHistograms = _histogramsExpanded;
    final rows = <Widget>[
      for (final key in _ocrKeyOrder)
        if (_aggregator.best(key) case final best?) ...[
          OCRKeyValue(
            keyName: key.toUpperCase(),
            value: best.value,
            confidence: best.confidence,
            sampleCount: best.count,
          ),
          if (showHistograms)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, c) in _aggregator.candidates(key).indexed)
                    _CandidateBar(candidate: c, isWinner: i == 0),
                ],
              ),
            ),
        ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  "Details detections: ${_aggregator.detailsCount}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (rows.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(
                    () => _histogramsExpanded = !_histogramsExpanded),
                icon: Icon(
                  _histogramsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(_histogramsExpanded ? 'Hide values' : 'Show values'),
              ),
          ],
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              live ? "Reading score…" : "No score captured.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

// Tallies OCR readings across frames; the modal value per field is the result.
class _OcrAggregator {
  final Map<String, Map<String, int>> _counts = {};
  int _detailsCount = 0;

  int get detailsCount => _detailsCount;

  bool add(Map<String, String> strings) {
    bool anyAdded = false;
    strings.forEach((key, raw) {
      final value = raw.trim();
      if (value.isEmpty) return;
      final tally = _counts.putIfAbsent(key, () => <String, int>{});
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

  ({String value, double confidence, int count})? best(String key) {
    final tally = _counts[key];
    if (tally == null || tally.isEmpty) return null;
    var total = 0;
    MapEntry<String, int>? top;
    for (final entry in tally.entries) {
      total += entry.value;
      if (top == null || entry.value > top.value) top = entry;
    }
    return (value: top!.key, confidence: top.value / total, count: top.value);
  }

  List<({String value, int count, double share})> candidates(String key) {
    final tally = _counts[key];
    if (tally == null || tally.isEmpty) return const [];
    final total = tally.values.fold<int>(0, (sum, c) => sum + c);
    final entries = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries)
        (value: e.key, count: e.value, share: e.value / total),
    ];
  }
}

class _CandidateBar extends StatelessWidget {
  const _CandidateBar({required this.candidate, required this.isWinner});

  final ({String value, int count, double share}) candidate;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isWinner ? Colors.green : scheme.surfaceContainerHighest;
    return Padding(
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
                    Container(height: 12, color: scheme.surfaceContainerHigh),
                    FractionallySizedBox(
                      widthFactor: candidate.share.clamp(0.0, 1.0),
                      child: Container(height: 12, color: color),
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
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
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
