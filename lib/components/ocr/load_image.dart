import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ddr_md/components/ocr/ocr_page.dart';
import 'package:ddr_md/components/roi_overlay.dart';
import 'package:ddr_md/ocr_processor.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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

  var _script = TextRecognitionScript.latin;
  var _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _canProcess = true;
  bool _isBusy = false;
  String? _scoreText;

  Future<void> _processImage() async {
    if (_isPicking || (!Platform.isIOS && !Platform.isAndroid)) {
      return;
    }
    setState(() => _isPicking = true);

    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: imageQuality);

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
    await _recogniseText();
    setState(() => _isProcessing = false);
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
    _initLoadImage();
  }

  @override
  void dispose() {
    _ocrProcessor.dispose();
    super.dispose();
  }

  Future<void> _recogniseText() async {
    final inputScoreImage =
        InputImage.fromFilePath('${tempDir.path}/Score_bin2.jpg');
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _scoreText = '';
    });

    final recognizedText = await _textRecognizer.processImage(inputScoreImage);
    _scoreText = recognizedText.text;
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  bool get pickedImage => _pickedImage != null;
  bool get isProcessed => _lastResult != null;
  bool get isDetected =>
      _lastResult != null &&
      _lastResult!.isDetected &&
      _lastResult!.detectedRois != null;

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
                          child: Image.file(
                            File(_pickedImage!.path),
                            width: MediaQuery.of(context).size.width,
                            fit: BoxFit.fitWidth,
                          ),
                        )
                      : Center(
                          child: Text(_pickedImage == null
                              ? "please pick image"
                              : 'No DDR chart detected. Please try another image.'),
                        ),
                  if (_scoreText != null) Row(
                    children: [
                      Image.file(File('${tempDir.path}/Score_bin2.jpg')),
                      Text(_scoreText!),
                    ],
                  )
                ],
              ),
      ),
    );
  }
}
