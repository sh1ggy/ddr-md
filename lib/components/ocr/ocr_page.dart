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
  bool _isCameraActive = false;
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
    int orientation = _controller?.description.sensorOrientation ?? 0;
    
    _ocrProcessor.processFrame(image);
    _lastFrame = image;
  }

  Future<void> _toggleCamera() async {
    print('Toggle camera called. Current state: $_isCameraActive');
    if (_isCameraActive) {
      // Stop the camera
      print('Stopping camera stream...');
      await _controller?.stopImageStream();
      setState(() {
        _isCameraActive = false;
      });
      print('Camera stopped. New state: $_isCameraActive');
    } else {
      // Start the camera
      print('Starting camera stream...');
      if (_controller != null && _controller!.value.isInitialized) {
        await _controller!.startImageStream(_processImage);
        setState(() {
          _isCameraActive = true;
        });
        print('Camera started. New state: $_isCameraActive');
      } else {
        print('Controller not initialized or null');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OCR Page")),
      body: Stack(
        children: <Widget>[
          if (_controller != null &&
              _controller!.value.isInitialized &&
              _isCameraActive)
            CameraPreview(_controller!)
          else if (_controller == null || !_controller!.value.isInitialized)
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
                      onPressed: _toggleCamera,
                      child: Text(
                          _isCameraActive ? 'Stop Camera' : 'Start Camera'),
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
