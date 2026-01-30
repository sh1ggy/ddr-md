import 'dart:async';
import 'dart:io';

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

    widget.ocrProcessor.processImage(pickedImage);

    setState(() {
      _isWorking = true;
    });
  }

  @override
  void initState() {
    super.initState();
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
      body: Center(
        child: ListView(shrinkWrap: true, children: [
          if (_isProcessed && !_isWorking)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 3000, maxHeight: 300),
              child: Image.file(
                File(tempPath),
                alignment: Alignment.center,
              ),
            ),
          ElevatedButton(
            onPressed: _pickImageAndProcess,
            child: const Text('Process photo'),
          ),
        ]),
      ),
    );
  }
}
