import 'dart:async';
import 'dart:io';
import 'dart:math';

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
  bool _isDetected = false;
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
    setState(() {
      _isProcessed = false;
      _isWorking = true;
    });
    final pickedImage = await _pickImage();
    if (pickedImage == null) {
      return;
    }

    widget.ocrProcessor.processPickedImage(pickedImage);

    setState(() {
      _isWorking = false;
      _isProcessed = true;
    });
  }

  @override
  void initState() {
    super.initState();
    getApplicationDocumentsDirectory().then((dir) => tempDir = dir);
    widget.ocrProcessor.streamResultController.stream.listen((result) {
      setState(() {
        // This is fine to do since we are measuring from top left, width and height
        var newRoi = Rectangle<int>(
          (result.roi.left * _camFrameToScreenScale).toInt(),
          (result.roi.top * _camFrameToScreenScale).toInt(),
          (result.roi.width * _camFrameToScreenScale).toInt(),
          (result.roi.height * _camFrameToScreenScale).toInt(),
        );
        ProcessResult processedImageResult = ProcessResult(
            result.score,
            result.difficulty,
            newRoi,
            result.isDetected,
            result.returnImageType,
            result.processedImageBytes);
        _isDetected = processedImageResult.isDetected;
      });
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
                _isDetected
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: 3000, maxHeight: 300),
                        child: Image.file(
                          File(tempPath),
                          alignment: Alignment.center,
                        ),
                      )
                    : Text(_isProcessed
                        ? "please pick image"
                        : 'No DDR chart detected. Please try another image.'),
              ]),
      ),
    );
  }
}
