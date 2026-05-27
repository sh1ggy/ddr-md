/// Name: OcrPage
/// Description: Page to process camera feed frames for OCR using native FFI & OpenCV
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
  // These are the pixel dimensions of the frame the native layer processed, i.e.
  // the coordinate space of both the detected ROIs and the captured JPEG.
  int _rawFrameWidth = 0;
  int _rawFrameHeight = 0;

  CameraImage? _lastFrame;

  // Whether the native pipeline is asked to return debug images; none disables
  // the debug panel and keeps the encode cost out of the hot path.
  DebugImageType _debugImageType = DebugImageType.none;
  // When true the score panel shows a per-field histogram of every OCR value
  // seen, not just the winner. Toggled by one button (in both the live and
  // stopped views), applies to all rows at once — the rows themselves are not
  // interactive.
  bool _histogramsExpanded = false;
  // Latest full-frame binarized mask — updated every processed frame.
  final ValueNotifier<Uint8List?> _debugMaskBytes = ValueNotifier(null);
  // Latest successful Details crop — only updated when a frame matched, so the
  // last good crop persists through frames that detect nothing.
  final ValueNotifier<Uint8List?> _debugCropBytes = ValueNotifier(null);

  // Last successful color capture for the stopped view. Holds the raw native
  // frame bytes plus the ROIs in raw frame-pixel space (not screen-scaled), so
  // the painter can scale and rotate them to whatever size the still image is
  // laid out at — unlike the live overlay, which is pre-scaled to the preview.
  final ValueNotifier<_CaptureView?> _captureData = ValueNotifier(null);

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
      final double scale = _camFrameToScreenScale;

      // The detected ROIs are in upright portrait pixel space on both platforms
      // (Android rotates its landscape YUV frame 90° CW in C++; iOS receives the
      // BGRA frame already portrait), so the preview — shown full-width — maps
      // them with a plain scale, no per-platform rotation math.
      final scaled = (result.detectedRois ?? []).map((r) {
        return Rectangle<int>(
          (r.left * scale).toInt(),
          (r.top * scale).toInt(),
          (r.width * scale).toInt(),
          (r.height * scale).toInt(),
        );
      }).toList();
      // Always repaint the detected candidate boxes for this frame. The details
      // index only highlights one of them and is -1 when none matched, so the
      // overlay never goes blank just because "Details" wasn't read this frame.
      _roiData.value = (scaled, result.detailsRoiIndex);
      final detailsFound =
          result.detailsRoiIndex != null && result.detailsRoiIndex! >= 0;
      // Surface the debug images without a full rebuild — the
      // ValueListenableBuilders below repaint just the panels. The mask updates
      // every frame; the Details crop only when this frame matched, so the last
      // successful crop persists through frames that detect nothing.
      if (result.debugMaskBytes != null) {
        _debugMaskBytes.value = result.debugMaskBytes;
      }
      if (result.debugDetailsCropBytes != null) {
        _debugCropBytes.value = result.debugDetailsCropBytes;
      }
      // Persist the last successful color capture with the native ROIs (in
      // frame-pixel space, matching the captured JPEG's own pixels — they come
      // from the same inputImg). The stopped view scales them to fit however the
      // still is laid out. Overwrites on each match (last wins).
      if (result.captureBytes != null) {
        // Pixel dimensions of the frame the native layer processed (= the JPEG's
        // own size and the ROI coordinate space), both already upright portrait.
        // Android rotates its landscape YUV frame 90° in C++, so its processed
        // dimensions are the raw camera dimensions swapped. iOS delivers the BGRA
        // frame already portrait and is not rotated, so its dimensions are as-is.
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
      // Only count and display when the Details ROI was actually found and
      // at least one OCR string contributed a non-empty value to the tally.
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
    // Width of the frame in the coordinate space the native layer produces ROIs
    // in (= the preview's width). Android rotates its landscape YUV frame 90° in
    // C++, so its portrait width is the raw image.height. iOS delivers the BGRA
    // frame already portrait and is NOT rotated, so its width is image.width.
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
        // Stop the camera
        print('Stopping camera stream...');
        // stopImageStream() ends new frame delivery, but frames the plugin
        // already queued keep flowing to the isolate and are processed — a late
        // detection there still lands. Enter the draining state so the stopped
        // view shows one continuous "Finalising…" until that queue is empty,
        // rather than flickering off in the gaps between queued frames.
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
          // Restarted before the previous run finished draining — drop that
          // state so the new run's indicator reflects only this session.
          _ocrProcessor.cancelDraining();
          await _controller!.startImageStream(_processImage);
          setState(() {
            _isCameraActive = true;
            // Start a fresh collection so cached values reflect this run only.
            _aggregator.clear();
            // Drop the previous run's persisted overlay, debug frames, and the
            // last capture so the stopped view reflects only this run.
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

  // Enables/disables debug image capture. Clears the last images when turning
  // it off so stale frames don't linger.
  void _setDebugEnabled(bool enabled) {
    final type = enabled ? DebugImageType.on : DebugImageType.none;
    setState(() => _debugImageType = type);
    _ocrProcessor.debugImageType = type;
    if (!enabled) {
      _debugMaskBytes.value = null;
      _debugCropBytes.value = null;
    }
  }

  // On/off toggle plus two panels: the latest full-frame mask and the latest
  // successfully matched Details crop (persisted across failed frames).
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
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
                    style: const TextStyle(color: Colors.black54),
                  ),
                );
              }
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
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

  // Renders the last successful color capture with its static ROIs painted on
  // top — the stopped-state equivalent of the load_image result view. The
  // capture is already upright portrait (both platforms rotate in C++), and the
  // ROIs are in that same pixel space, so a painter just scales them to the
  // laid-out image size. They stay aligned at any size.
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
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  "Last capture",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              framed,
            ],
          ),
        );
      },
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
        // Show one continuous "Finalising…" while the post-stop queue drains:
        // isDraining stays true across the gaps between queued frames, where
        // isProcessing alone would flicker off.
        ListenableBuilder(
          listenable: Listenable.merge(
              [_ocrProcessor.isProcessing, _ocrProcessor.isDraining]),
          builder: (context, _) {
            final busy =
                _ocrProcessor.isProcessing.value || _ocrProcessor.isDraining.value;
            if (!busy) return const SizedBox.shrink();
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
        _buildCapturePanel(),
        _buildScorePanel(live: false),
      ],
    );
  }

  // One row per OCR field showing the most-frequent (highest-confidence) value
  // and the share of detections that agreed on it. A single button expands every
  // row into a histogram of all values seen for the field, so the losing OCR
  // candidates are visible too — available in both the live and stopped views.
  // The rows stay non-interactive; one toggle controls them all.
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
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ),
            // One button toggles the value histograms for all rows, in both the
            // live and stopped views. Hidden only when there's nothing to show.
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
  // Frames where the "Details" label matched and at least one field was read
  // (one per successful [add]). The score panel is built from these.
  int _detailsCount = 0;

  int get detailsCount => _detailsCount;

  // Returns true if at least one non-empty value was added to the tally,
  // in which case _detailsCount is also incremented.
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

  // Every distinct value seen for [key], descending by count, each with its
  // [count] and [share] of the field's total reads. The first entry is the same
  // value [best] returns; the rest are the losing candidates a histogram shows.
  // Empty when the field was never read.
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

// A single histogram row: the value, a bar whose width is its share of reads,
// and the count + percentage. The winning value is tinted to stand out.
class _CandidateBar extends StatelessWidget {
  const _CandidateBar({required this.candidate, required this.isWinner});

  final ({String value, int count, double share}) candidate;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final color = isWinner ? Colors.green : Colors.grey[400]!;
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
                    Container(height: 12, color: Colors.black12),
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
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
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

// The last successful color capture for the stopped view: the native frame
// JPEG (already upright portrait, since both platforms rotate in C++) and the
// ROIs in that frame's pixel space.
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

// Paints the static capture ROIs, scaling them from the portrait frame-pixel
// space to whatever size the still image is laid out at (the canvas size). The
// capture and its ROIs share that same upright space, so they stay aligned.
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
