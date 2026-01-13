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
  FrameProcessResult? _lastResult;

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
    _controller?.dispose();
    _ocrProcessor.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      var cameraId = 0;

      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      var controller = CameraController(
        cameras[cameraId],
        ResolutionPreset.max,
        enableAudio: false,
      );

      //TODO if controller not initialized, reroute back to other page and put up a snackbar saying user is cring

      await controller.initialize();

      await controller.stopImageStream();

      await controller.startImageStream(_processImage);


      print('AS: ${controller.value.aspectRatio}'
          '   SIZE: ${controller.value.previewSize}'
          '   ORIENTATION: ${controller.value.deviceOrientation}'
          '   RES PRESET: ${controller.resolutionPreset}'
          '   IMG FMT GROUP: ${controller.imageFormatGroup}'
          '   CAMERA SENSOR: ${cameras[cameraId].sensorOrientation}');


      if (!mounted) return;


      setState(() {
        _controller = controller;
      });

    } on CameraException catch (e) {
      setState(() {});
    } catch (e) {
      setState(() {});
    }
  }

  void _processImage(CameraImage image) {
    _ocrProcessor.processFrame(image);
  }

  void showVersion() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final snackbar = SnackBar(
      content: Text('OpenCV version: ${opencvVersion()}'),
    );

    scaffoldMessenger
      ..removeCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
      ..showSnackBar(snackbar);
  }

  void takeSnapshot() {
    try {
      cameraSnapshot(tempPath);

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final snackbar = SnackBar(
        content: Text('Snapshot saved to: $tempPath'),
      );

      scaffoldMessenger
        ..removeCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
        ..showSnackBar(snackbar);

      setState(() {
        _isImageLoaded = true;
      });
    } catch (e) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final snackbar = SnackBar(
        content: Text('Error taking snapshot: $e'),
      );

      scaffoldMessenger
        ..removeCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
        ..showSnackBar(snackbar);
    }
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
                    ElevatedButton(
                      onPressed: showVersion,
                      child: const Text('Show version'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: takeSnapshot,
                      child: const Text('Take Camera Snapshot'),
                    ),
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
