/// Name: OcrPage
/// Description: Page to process camera feed frames for OCR using native FFI & OpenCV
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:ddr_md/components/ocr/load_image.dart';
import 'package:ddr_md/components/roi_painter.dart';
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
  // True once the user has started (and stopped) at least one OCR session.
  bool _hasRecorded = false;
  CameraController? _controller;
  late OCRProcessor _ocrProcessor;
  // Accumulates OCR readings across frames; the cached values survive frames
  // that fail to read so the panel stays populated.
  final _OcrAggregator _aggregator = _OcrAggregator();
  double _camFrameToScreenScale = 0;
  // Raw camera frame dimensions (landscape BGRA on iOS) used for ROI transform.
  int _rawFrameWidth = 0;

  CameraImage? _lastFrame;

  // Last-known ROIs (scaled to screen space) painted on every frame, decoupled
  // from the throttled OCR results that feed it.
  final ValueNotifier<(List<Rectangle<int>>, int?)> _roiData =
      ValueNotifier(([], null));
  // Bumped once per vsync to drive the ROI overlay repaint.
  final ValueNotifier<int> _frameTick = ValueNotifier(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();

    // Add observer to listen for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Repaint the ROI overlay every frame from the last-known result.
    _ticker = createTicker((_) => _frameTick.value++)..start();

    _ocrProcessor = OCRProcessor();
    _ocrProcessor.streamResultController.stream.listen((result) {
      final int sensorOrientation =
          _controller?.description.sensorOrientation ?? 0;
      final double scale = _camFrameToScreenScale;
      final int frameWidth = _rawFrameWidth;

      final scaled = (result.detectedRois ?? []).map((r) {
        if (Platform.isIOS &&
            (sensorOrientation == 90 || sensorOrientation == 270)) {
          // The raw BGRA frame is landscape; CameraPreview rotates it
          // 90° CCW (sensor=90) or 90° CW (sensor=270) for portrait display.
          // Apply the same transform so ROIs land on the correct pixels.
          if (sensorOrientation == 90) {
            // 90° CCW: (x,y) -> (y, frameWidth - x - rw)
            return Rectangle<int>(
              (r.top * scale).toInt(),
              ((frameWidth - r.left - r.width) * scale).toInt(),
              (r.height * scale).toInt(),
              (r.width * scale).toInt(),
            );
          } else {
            // 90° CW: (x,y) -> (frameHeight - y - rh, x)
            // frameHeight not stored separately; use r.top + r.height boundary
            // Approximate using _rawFrameWidth as landscape height is image.height
            // (stored indirectly via scale = screenWidth / image.height).
            // landscape height = screenWidth / scale
            final int frameHeight = (MediaQuery.of(context).size.width / scale)
                .round();
            return Rectangle<int>(
              ((frameHeight - r.top - r.height) * scale).toInt(),
              (r.left * scale).toInt(),
              (r.height * scale).toInt(),
              (r.width * scale).toInt(),
            );
          }
        }
        // Android: C++ already rotates the frame 90° CW before processing,
        // so ROIs are in portrait space — direct scale is correct.
        return Rectangle<int>(
          (r.left * scale).toInt(),
          (r.top * scale).toInt(),
          (r.width * scale).toInt(),
          (r.height * scale).toInt(),
        );
      }).toList();
      _roiData.value = (scaled, result.detailsRoiIndex);
      // Only count and display when the Details ROI was actually found and
      // at least one OCR string contributed a non-empty value to the tally.
      final detailsFound =
          result.detailsRoiIndex != null && result.detailsRoiIndex! >= 0;
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
    // if (_controller != null) {
    //   _controller?.pausePreview();
    //   if (_controller!.value.isStreamingImages) {
    //     _controller?.stopImageStream();
    //   }
    // }
    _ticker.dispose();
    _frameTick.dispose();
    _roiData.dispose();
    _controller?.dispose();
    _controller = null;
    _ocrProcessor.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      // Run OCR processor init and camera discovery in parallel — Tesseract
      // loading and isolate spawn are independent of the camera controller.
      final ocrFuture = _ocrProcessor.init().then((_) => _ocrProcessor.initActor());
      final camerasFuture = availableCameras();

      // Let the camera preview appear as soon as the controller is ready,
      // without waiting for OCR (the FAB stays hidden until both are done).
      final cameras = await camerasFuture;
      if (cameras.isEmpty) throw Exception('No cameras available');

      _controller = CameraController(
        cameras[0],
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();

      // Show the preview immediately; OCR may still be loading.
      if (mounted) setState(() {});

      // Now wait for OCR to finish — after this the FAB becomes active.
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

  // TODO actually handle this to stop debug from breaking
  // @override
  // void didChangeAppLifecycleState(AppLifecycleState state) {
  //   final CameraController? cameraController = _controller;

  //   // App state changed before we got the chance to initialize.
  //   if (cameraController == null || !cameraController.value.isInitialized) {
  //     return;
  //   }

  //   if (state == AppLifecycleState.inactive) {
  //     cameraController.dispose();
  //   } else if (state == AppLifecycleState.resumed) {
  //     _initCamera();
  //   }
  // }

  void _processImage(CameraImage image) {
    // print('Processing image frame...');
    int rotation = _controller?.description.sensorOrientation ?? 0;
    var w = 0;
    if (Platform.isAndroid) {
      w = (rotation == 0 || rotation == 180) ? image.width : image.height;
    } else if (Platform.isIOS) {
      w = (rotation == 90 || rotation == 270) ? image.height : image.width;
    }

    _camFrameToScreenScale = MediaQuery.of(context).size.width / w;
    _rawFrameWidth = image.width;

    _ocrProcessor.processVideostreamFrame(image);
    _lastFrame = image;
  }

  Future<void> _toggleCamera() async {
    if (_isTogglingCamera) return;
    _isTogglingCamera = true;
    print('Toggle camera called. Current state: $_isCameraActive');
    try {
      if (_isCameraActive) {
        // Stop the camera
        print('Stopping camera stream...');
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
          await _controller!.startImageStream(_processImage);
          setState(() {
            _isCameraActive = true;
            // Start a fresh collection so cached values reflect this run only.
            _aggregator.clear();
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

  // OCR processor is ready once the isolate send-port has been established.
  // We reuse _ocrProcessor.toIsolate as the readiness signal.
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
      body: switch (cameraState) {
        CameraState.notReady =>
          const Center(child: CircularProgressIndicator()),
        CameraState.neverRecorded => const Center(
            child: Text(
              "Start OCR to begin detection",
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ),
        CameraState.inactive => _buildStoppedView(),
        CameraState.active => _buildActiveView(),
      },
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

  // Live view: the full-width camera preview (so ROIs scale by
  // screenWidth / frameWidth, exactly like the picked-image path) with the ROI
  // overlay, and the running score panel below. A ListView gives the preview the
  // full screen width and lets it scroll if it is taller than the viewport.
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
          padding: const EdgeInsets.all(16),
          child: _buildScorePanel(live: true),
        ),
      ],
    );
  }

  // Stopped view: the cached, highest-confidence readings collected this run.
  Widget _buildStoppedView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const Text(
          "Camera stopped",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _ocrProcessor.isProcessing,
          builder: (context, processing, _) {
            if (!processing) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  SizedBox(width: 6),
                  Text(
                    "Finalising…",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildScorePanel(live: false),
      ],
    );
  }

  // One row per OCR field showing the most-frequent (highest-confidence) value
  // and the share of detections that agreed on it.
  Widget _buildScorePanel({required bool live}) {
    final rows = <Widget>[
      for (final key in _ocrKeyOrder)
        if (_aggregator.best(key) case final best?)
          OCRKeyValue(
            keyName: key.toUpperCase(),
            value: best.value,
            confidence: best.confidence,
            sampleCount: best.count,
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            "Detected: ${_aggregator.detectedCount}",
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              live ? "Reading score…" : "No score captured.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

// Accumulates the OCR'd text across frames. For each field it tallies every
// non-empty value seen; the displayed value is the most-frequent one — frequency
// stands in for confidence, since the native layer reports no score — and it
// stays cached even when later frames fail to read that field. Picking the modal
// reading is the noise-robust form of "averaging" a value that should be fixed.
class _OcrAggregator {
  final Map<String, Map<String, int>> _counts = {};
  // Total detections fed in this run (one per [add]), shown as the "detected"
  // count regardless of which fields each detection read.
  int _detectedCount = 0;

  int get detectedCount => _detectedCount;

  // Returns true if at least one non-empty value was added to the tally,
  // in which case _detectedCount is also incremented.
  bool add(Map<String, String> strings) {
    bool anyAdded = false;
    strings.forEach((key, raw) {
      final value = raw.trim();
      if (value.isEmpty) return;
      final tally = _counts.putIfAbsent(key, () => <String, int>{});
      tally[value] = (tally[value] ?? 0) + 1;
      anyAdded = true;
    });
    if (anyAdded) _detectedCount++;
    return anyAdded;
  }

  void clear() {
    _counts.clear();
    _detectedCount = 0;
  }

  // Highest-confidence (most-frequent) reading for [key], the share of
  // detections that agreed on it, and how many samples agreed ([count]), or
  // null if the field was never read.
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
}

// Pinging green dot shown in the AppBar while the OCR isolate is processing.
// Animates opacity so it visibly pulses rather than being a static indicator.
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

// Repaints every frame (driven by [frameTick]) using the latest [roiData], so the
// Details ROI stays painted on the live preview between throttled OCR results.
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
