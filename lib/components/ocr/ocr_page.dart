/// Name: OcrPage
/// Description: Page to process camera feed frames for OCR using native FFI & OpenCV
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:ddr_md/components/ocr/load_image.dart';
import 'package:ddr_md/components/roi_overlay.dart';
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';
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

class _OcrPageState extends State<OcrPage> with WidgetsBindingObserver {
  bool _isImageLoaded = false;
  bool _isCameraActive = false;
  CameraController? _controller;
  late OCRProcessor _ocrProcessor;
  ProcessResult? _lastResult;
  double _camFrameToScreenScale = 0;
  int _processedFrames = 0;
  double lastTimeProcessed = 0.0;

  CameraImage? _lastFrame;

  @override
  void initState() {
    super.initState();

    // Add observer to listen for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    _ocrProcessor = OCRProcessor();
    _ocrProcessor.streamResultController.stream.listen((result) {
      setState(() {
        if (result.roi == null) {
          return;
        }
        // This is fine to do since we are measuring from top left, width and height
        var newRoi = Rectangle<int>(
          (result.roi!.left * _camFrameToScreenScale).toInt(),
          (result.roi!.top * _camFrameToScreenScale).toInt(),
          (result.roi!.width * _camFrameToScreenScale).toInt(),
          (result.roi!.height * _camFrameToScreenScale).toInt(),
        );

        // TODO here is where the state for the result should be created and processed instead of this
        var fin = ProcessResult(
            result.score,
            result.difficulty,
            newRoi,
            null,
            result.isDetected,
            result.returnImageType,
            result.processedImageBytes);

        _lastResult = fin;
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

    _ocrProcessor.processVideostreamFrame(image);
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

  bool get cameraReady =>
      _controller != null && _controller!.value.isInitialized;

  bool get hasRoi =>
      _lastResult?.isDetected == true && _lastResult?.roi != null;

  CameraState get cameraState {
    if (!cameraReady) return CameraState.notReady;
    if (!_isCameraActive) return CameraState.inactive;
    return CameraState.active;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("OCR Page"),
        actions: [
          ElevatedButton(
            onPressed: () async {
              await Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (context) => const LoadImage()));
            },
            child: const Text("Load Image"),
          ),
        ],
      ),
      body: Center(
        child: switch (cameraState) {
          CameraState.notReady => const Text("Camera not started"),
          CameraState.inactive => const Text("Camera stopped"),
          CameraState.active => RoiOverlay(
              rois: hasRoi ? [_lastResult!.roi!] : const [],
              child: CameraPreview(_controller!),
            ),
        },
        // // Dump button
        // Positioned(
        //   bottom: 80,
        //   left: 0,
        //   right: 0,
        //   child: Center(
        //     child: ElevatedButton.icon(
        //       onPressed: _requestDump,
        //       icon: Icon(Icons.save),
        //       label: Text('Dump YUV Frame'),
        //       style: ElevatedButton.styleFrom(
        //         padding:
        //             const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        //         backgroundColor: Colors.blue,
        //       ),
        //     ),
        //   ),
        // ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_lastResult != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _lastResult!.isDetected ? "(Detected)" : "(Not Detected)",
                    style: TextStyle(
                      color:
                          _lastResult!.isDetected ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                Text(
                    'Difficulty: ${_lastResult!.difficulty} Score: ${_lastResult!.score}'),
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
