import 'dart:math';

import 'package:camera/camera.dart';
import 'package:ddr_md/native_ocr_ffi.dart';
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

late Directory tempDir;
String get tempPath => '${tempDir.path}/temp.jpg';

class _OcrPageState extends State<OcrPage> {
  bool _isImageLoaded = false;
  CameraController? _controller;
  late OCRProcessor _ocrProcessor;
  ProcessImageResult? _lastResult;

  int _processedFrames = 0;
  double lastTimeProcessed = 0.0;

  CameraImage? _lastFrame;

  @override
  void initState() {
    super.initState();
    _ocrProcessor = OCRProcessor();
    _ocrProcessor.streamResultController.stream.listen((result) {
      setState(() {
        _lastResult = result;
      });
    });

    getTemporaryDirectory().then((dir) => tempDir = dir);
    _initCamera();
  }

  @override
  void dispose() {
    if (_controller != null) {
      if (_controller!.value.isStreamingImages) {
        _controller?.stopImageStream();
      }
    }

    _controller?.dispose();
    _ocrProcessor.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      await _ocrProcessor.init();

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

      await _controller!.startImageStream(_processImage);

      print('AS: ${_controller!.value.aspectRatio}'
          '   SIZE: ${_controller!.value.previewSize}'
          '   ORIENTATION: ${_controller!.value.deviceOrientation}'
          '   RES PRESET: ${_controller!.resolutionPreset}'
          '   IMG FMT GROUP: ${_controller!.imageFormatGroup}'
          '   CAMERA SENSOR: ${cameras[cameraId].sensorOrientation}');

      // if (!mounted) return;

      setState(() {
        // _controller! = controller;
      });
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
      setState(() {});
    } catch (e) {
      setState(() {});
    }
  }

  void _requestDump() async {
    if (_lastFrame == null) {
      print('No frame to dump.');
      return;
    }
    var image = _lastFrame!;

    final dir = await getExternalStorageDirectory();

    // Write Y plane
    final yFile = File('${dir!.path}/yuv_y_plane.raw');
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

    print('Dumped YUV data to ${dir.path}');
  }

// TODO actually handle this to stop debug from breaking

//   @override
// void didChangeAppLifecycleState(AppLifecycleState state) {
//   final CameraController? cameraController = controller;

//   // App state changed before we got the chance to initialize.
//   if (cameraController == null || !cameraController.value.isInitialized) {
//     return;
//   }

//   if (state == AppLifecycleState.inactive) {
//     cameraController.dispose();
//   } else if (state == AppLifecycleState.resumed) {
//     _initializeCameraController(cameraController.description);
//   }
// }

  void _processImage(CameraImage image) {
    // print('Processing image frame...');
    _ocrProcessor.processFrame(image);
    _lastFrame = image;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OCR Page")),
      body: Stack(
        children: <Widget>[
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator()),
          if (_lastResult != null)
            CustomPaint(
              painter: OCRResultPainter(roi: _lastResult!.roi),
              size: Size.infinite,
            ),
          Center(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                Column(
                  children: [
                    if (_lastResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Column(
                          children: [
                            Text('Score: ${_lastResult!.score}'),
                            Text('Difficulty: ${_lastResult!.difficulty}'),
                          ],
                        ),
                      ),
                  ],
                )
              ],
            ),
          ),

          // Dump button
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _requestDump,
                icon: Icon(Icons.save),
                label: Text('Dump YUV Frame'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Colors.blue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OCRResultPainter extends CustomPainter {
  OCRResultPainter({required this.roi});

  final Rectangle<int> roi;

  final _paint = Paint()
    ..strokeWidth = 3.0
    ..color = Colors.green
    ..style = PaintingStyle.stroke;

  final _fillPaint = Paint()
    ..color = Colors.green.withOpacity(0.1)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (roi.width <= 0 || roi.height <= 0) {
      return;
    }

    final rect = Rect.fromLTWH(
      roi.left.toDouble(),
      roi.top.toDouble(),
      roi.width.toDouble(),
      roi.height.toDouble(),
    );

    canvas.drawRect(rect, _fillPaint);
    canvas.drawRect(rect, _paint);
  }

  @override
  bool shouldRepaint(OCRResultPainter oldDelegate) {
    return roi != oldDelegate.roi;
  }
}
