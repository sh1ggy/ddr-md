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
  notReady,
  inactive,
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
  CameraController? _controller;
  late OCRProcessor _ocrProcessor;
  ProcessResult? _lastResult;
  // Holds the most recent result where isDetected == true so the score
  // panel persists across frames that fail to detect.
  ProcessResult? _lastDetectedResult;
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
      setState(() {
        _lastResult = result;
        if (result.isDetected) _lastDetectedResult = result;
      });
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
      await _ocrProcessor.init();
      await _ocrProcessor.initActor();

      final cameras = await availableCameras();
      var cameraId = 0;

      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      _controller = CameraController(
        cameras[cameraId],
        ResolutionPreset.max,
        enableAudio: false,
      );

      //TODO if controller not initialized, reroute back to other page and put up a snackbar saying user is cring

      await _controller!.initialize();

      print('AS: ${_controller!.value.aspectRatio}'
          '   SIZE: ${_controller!.value.previewSize}'
          '   ORIENTATION: ${_controller!.value.deviceOrientation}'
          '   RES PRESET: ${_controller!.resolutionPreset}'
          '   IMG FMT GROUP: ${_controller!.imageFormatGroup}'
          '   CAMERA SENSOR: ${cameras[cameraId].sensorOrientation}');

      setState(() {
        // _controller! = controller;
      });
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
      if (!mounted) return;
      Navigator.pushNamed(context, "/");
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      Navigator.pushNamed(context, "/");
      setState(() {});
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

  CameraState get cameraState {
    if (!cameraReady) return CameraState.notReady;
    if (!_isCameraActive) return CameraState.inactive;
    return CameraState.active;
  }

  @override
  Widget build(BuildContext context) {
    // Show strings from the last detected frame, falling back to last result.
    final ocrStrings = _lastDetectedResult?.ocrStrings ?? _lastResult?.ocrStrings ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text("Camera")),
      body: Center(
        child: switch (cameraState) {
          CameraState.notReady => const Text("Camera not started"),
          CameraState.inactive => const Text("Camera stopped"),
          CameraState.active => RepaintBoundary(
              child: CustomPaint(
                foregroundPainter: _CameraRoiPainter(_roiData, _frameTick),
                child: CameraPreview(_controller!),
              ),
            ),
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_lastResult != null) ...[
                Center(
                  child: Text(
                    _lastResult!.isDetected ? "(Detected)" : "(Not Detected)",
                    style: TextStyle(
                      color:
                          _lastResult!.isDetected ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                ...ocrStrings.entries.map((e) => OCRKeyValue(
                    keyName: e.key.toUpperCase(), value: e.value)),
                const SizedBox(height: 8),
              ],
              ElevatedButton(
                onPressed: _toggleCamera,
                child: Text(
                  _isCameraActive ? 'Stop Camera' : 'Start Camera',
                ),
              ),
            ],
          ),
        ),
      ),
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
