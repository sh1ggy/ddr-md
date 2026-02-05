import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ddr_md/components/roi_painter.dart';
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

const int imageQuality = 100;
late Directory tempDir;
String get tempPath => '${tempDir.path}/temp.jpg';

class LoadImage extends StatefulWidget {
  final OCRProcessor ocrProcessor;

  const LoadImage({super.key, required this.ocrProcessor});

  @override
  State<LoadImage> createState() => _LoadImageState();
}

class _LoadImageState extends State<LoadImage> {
  final _picker = ImagePicker();
  bool _isProcessed = false;
  bool _isWorking = false;
  String? _pickedImagePath;
  ProcessResult? _lastResult;
  double _camFrameToScreenScale = 1.0;

  Future<XFile?> _pickImage() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return null;
    }
    return _picker
        .pickImage(source: ImageSource.gallery, imageQuality: imageQuality)
        .then((pickedFile) {
      return pickedFile;
    });
  }

  Future<void> _pickImageAndProcess() async {
    final pickedImage = await _pickImage();

    if (pickedImage == null) {
      return;
    }

    setState(() {
      _isProcessed = false;
      _isWorking = true;
    });

    widget.ocrProcessor.processPickedImage(pickedImage);

    setState(() {
      _isWorking = false;
      _isProcessed = true;
      _pickedImagePath = pickedImage.path;
    });
  }

  @override
  void initState() {
    super.initState();
    getApplicationDocumentsDirectory().then((dir) => tempDir = dir);
    widget.ocrProcessor.streamResultController.stream.listen((result) async {
      // Try to read the saved temp image and compute a scale so ROI maps to
      // the displayed image width. Falls back to existing scale if file missing.
      final f = File(tempPath);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        ui.decodeImageFromList(bytes, (img) {
          final screenW = MediaQuery.of(context).size.width;
          final scale =
              img.width > 0 ? screenW / img.width : _camFrameToScreenScale;

          List<Rectangle<int>> detectedRois = [];
          setState(() {
            _camFrameToScreenScale = scale;
            if (result.detectedRois == null) {
              return;
            }
            for (int i = 0; i < result.detectedRois!.length; i++) {
              final roi = result.detectedRois![i];
              print(
                  'Detected ROI $i: left=${roi.left}, top=${roi.top}, width=${roi.width}, height=${roi.height}');

              Rectangle<int> roiToAdd = Rectangle<int>(
                (roi.left * _camFrameToScreenScale).toInt(),
                (roi.top * _camFrameToScreenScale).toInt(),
                (roi.width * _camFrameToScreenScale).toInt(),
                (roi.height * _camFrameToScreenScale).toInt(),
              );
              detectedRois.add(roiToAdd);
            }
            _lastResult = ProcessResult(
                result.score,
                result.difficulty,
                null,
                detectedRois,
                result.isDetected,
                result.returnImageType,
                result.processedImageBytes);
          });
        });
      }
    });
  }

  @override
  void dispose() {
    widget.ocrProcessor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Load Image")),
      bottomNavigationBar: ElevatedButton(
        onPressed: _pickImageAndProcess,
        child: const Text('Process photo'),
      ),
      body: Center(
        child: _isWorking
            ? const CircularProgressIndicator()
            : ListView(shrinkWrap: true, children: [
                _lastResult != null &&
                        _lastResult!.isDetected &&
                        _lastResult!.detectedRois != null &&
                        _pickedImagePath != null
                    ? Stack(
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: Image.file(
                              File(_pickedImagePath!),
                              alignment: Alignment.topCenter,
                              width: MediaQuery.of(context).size.width,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                          _lastResult!.detectedRois!.isNotEmpty
                              ? Positioned.fill(
                                  child: CustomPaint(
                                    painter: RoiResultPainter(
                                        rois: _lastResult!.detectedRois!),
                                    size: Size.infinite,
                                  ),
                                )
                              : Container(),
                        ],
                      )
                    : Text(_isProcessed
                        ? "please pick image"
                        : 'No DDR chart detected. Please try another image.'),
              ]),
      ),
    );
  }
}
