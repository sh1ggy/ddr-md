import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ddr_md/components/roi_overlay.dart';
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

const int imageQuality = 100;
late Directory tempDir;
String get tempPath => '${tempDir.path}/';

class LoadImage extends StatefulWidget {
  const LoadImage({super.key});

  @override
  State<LoadImage> createState() => _LoadImageState();
}

class _LoadImageState extends State<LoadImage> {
  late OCRProcessor _ocrProcessor;
  bool _isPicking = false;
  bool _isProcessing = false;
  XFile? _pickedImage;
  ProcessResult? _lastResult;
  double _camFrameToScreenScale = 1.0;
  String? _scoreText;

  Future<void> _processImage() async {
    if (_isPicking || (!Platform.isIOS && !Platform.isAndroid)) {
      return;
    }
    setState(() => _isPicking = true);

    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: ImageSource.gallery);

    if (!mounted) return;
    if (pickedImage == null) {
      setState(() => _isPicking = false);
      return;
    }
    setState(() {
      _pickedImage = pickedImage;
      _isPicking = false;
      _isProcessing = true;
    });
    _ocrProcessor.processPickedImage(_pickedImage!);
    // wait for the stream listener to clear _isProcessing when a result arrives
  }

  Future<void> _initLoadImage() async {
    await _ocrProcessor.init();
    await _ocrProcessor.initActor();
  }

  @override
  void initState() {
    super.initState();
    getApplicationDocumentsDirectory().then((dir) {
      tempDir = dir;
    });
    _ocrProcessor = OCRProcessor();
    _ocrProcessor.streamResultController.stream.listen((result) async {
      // Try to read the saved temp image and compute a scale so ROI maps to
      // the displayed image width. Falls back to existing scale if file missing.
      if (_pickedImage == null) return;
      final f = File(_pickedImage!.path);
      // await _recogniseText();
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
                result.difficulty,
                null,
                detectedRois,
                result.isDetected,
                result.returnImageType,
                result.processedImageBytes,
                result.detailsRoiIndex,
                result.ocrStrings);
          });
        });
      }
    });
    _initLoadImage();
  }

  @override
  void dispose() {
    _ocrProcessor.dispose();
    super.dispose();
  }

  bool get pickedImage => _pickedImage != null;
  bool get isProcessed => _lastResult != null;
  bool get isDetected =>
      _lastResult != null &&
      _lastResult!.isDetected &&
      _lastResult!.detectedRois != null;
  bool get detailsRoiIndex =>
      _lastResult != null && _lastResult!.detailsRoiIndex != -1;
  bool get hasScore =>
      _lastResult != null && _lastResult!.ocrStrings.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Load Image"),
      ),
      bottomNavigationBar: ElevatedButton(
        onPressed: _processImage,
        child: const Text('Process photo'),
      ),
      body: Center(
        child: _isPicking
            ? const CircularProgressIndicator()
            : ListView(
                shrinkWrap: true,
                children: [
                  isDetected
                      ? RoiOverlay(
                          rois: _lastResult!.detectedRois!,
                          detailsRoiIndex: _lastResult!.detailsRoiIndex,
                          child: Image.file(
                            File(_pickedImage!.path),
                            width: MediaQuery.of(context).size.width,
                            fit: BoxFit.fitWidth,
                          ),
                        )
                      : Center(
                          child: _isProcessing
                              ? const CircularProgressIndicator()
                              : Text(_pickedImage == null
                                  ? "Please pick image"
                                  : 'No DDR chart detected.\nPlease try another image.'),
                        ),
                  if (_scoreText != null)
                    Row(
                      children: [
                        Text(_scoreText!),
                      ],
                    ),
                  detailsRoiIndex
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Center(
                              child: Text(
                            "Details detected!",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.lightGreenAccent),
                          )),
                        )
                      : Container(),
                  if (hasScore)
                    Center(
                      child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._lastResult!.ocrStrings.entries.map((entry) =>
                                  OCRKeyValue(
                                      keyName: entry.key.toUpperCase(),
                                      value: entry.value))
                            ],
                          )),
                    ),
                ],
              ),
      ),
    );
  }
}

class OCRKeyValue extends StatelessWidget {
  final String keyName;
  final String value;
  const OCRKeyValue({super.key, required this.keyName, required this.value});

  Color _colorForKey(String k) {
    final s = k.toLowerCase();
    switch (s) {
      case 'score':
        return Colors.black;
      case 'marvelous':
        return Colors.grey;
      case 'perfect':
        return Colors.yellow[700]!;
      case 'great':
        return Colors.green;
      case 'good':
        return Colors.blueAccent;
      case 'bad':
        return Colors.purpleAccent;
      default:
        return Colors.black87;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            keyName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _colorForKey(keyName),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
