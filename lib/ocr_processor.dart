import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';

enum DifficultyType { None, FFXI }

class ProcessImageResult {
  final int score;
  final DifficultyType difficulty;
  // TODO reconsider to using a rect that can do Floats
  final Rectangle<int> roi;

  ProcessImageResult(this.score, this.difficulty, this.roi);
}

class ProcessImageParams {
  // TODO This has to be multiple buffers transfered over
  final TransferableTypedData bytes;
  // final TransferableTypedData bytes;
  // final TransferableTypedData bytes;

  final int width;
  final int height;
  final int bytesPerPixel;

  ProcessImageParams({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerPixel,
  });
}

final DynamicLibrary _nativeLib = _openDynamicLibrary();

// Getting a library that holds needed symbols
DynamicLibrary _openDynamicLibrary() {
  return Platform.isAndroid
      ? DynamicLibrary.open("libnative_opencv.so")
      : DynamicLibrary.process();
}

// C Functions signatures
typedef _c_processImage = Void Function(Int32 width, Int32 height,
    Int32 bytesPerPixel, Pointer<Uint8> imageBytes, Pointer<Int32> outRoi);

// Dart functions signatures
typedef _dart_processImage = void Function(int width, int height,
    int bytesPerPixel, Pointer<Uint8> bytes, Pointer<Int32> outRoi);

// Create dart functions that invoke the C funcion
final _processImageFn = _nativeLib
    .lookupFunction<_c_processImage, _dart_processImage>('process_image');

Future<ProcessImageResult> _processFrameIsolate(
    ProcessImageParams params) async {
  final bytes = params.bytes.materialize().asUint8List();
  // final bytes = params.bytes;

  Pointer<Uint8> imageBuffer = calloc<Uint8>(bytes.length);
  imageBuffer.asTypedList(bytes.length).setAll(0, bytes);

  Pointer<Int32> retRoi = calloc.allocate<Int32>(4 * 4); // x, y, width, height
  _processImageFn(
      params.width, params.height, params.bytesPerPixel, imageBuffer, retRoi);

  if (retRoi == nullptr) {
    calloc.free(retRoi);
    calloc.free(imageBuffer);
    return ProcessImageResult(
        0, DifficultyType.None, const Rectangle(0, 0, 0, 0));
  }

  final rectArray = retRoi.cast<Int32>().asTypedList(4);

  ProcessImageResult result = ProcessImageResult(
    100, // Placeholder score
    DifficultyType.FFXI, // Placeholder difficulty
    Rectangle<int>(
      rectArray[0],
      rectArray[1],
      rectArray[2],
      rectArray[3],
    ),
  );

  calloc.free(retRoi);
  calloc.free(imageBuffer);

  return result;
}

class OCRProcessor {
  static OCRProcessor? _instance;

  bool _isProcessing = false;

  final streamResultController = StreamController<ProcessImageResult>();

  factory OCRProcessor() {
    _instance ??= OCRProcessor._internal();
    return _instance!;
  }

  OCRProcessor._internal() {}

  Future<void> processFrame(CameraImage image) async {
    // Pointer<Uint8> ptr = image.planes.first.bytes.address.address;
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      Pointer<Uint8>? _imageBuffer;
      if (image.format.group == ImageFormatGroup.yuv420) {
        // On Android the image format is YUV and we get a buffer per channel,
        // in iOS the format is BGRA and we get a single buffer for all channels.
        // So the yBuffer variable on Android will be just the Y channel but on iOS it will be
        // the entire image
        var planes = image.planes;
        var yBuffer = planes[0].bytes;
      }

      // Convert CameraImage to Uint8List
      final bytes = image.planes.first.bytes;

      // Create TransferableTypedData for zero-copy transfer (theoretically we relinquish ownership here but should be fine)
      final transferable = TransferableTypedData.fromList([bytes]);

      final params = ProcessImageParams(
        bytes: transferable,
        // bytes: bytes,
        width: image.width,
        height: image.height,
        bytesPerPixel: 4,
      );

      // final result = await compute(_processFrameIsolate, params);

      // if (result != null && !streamResultController.isClosed) {
      //   streamResultController.add(result);
      // }
    } catch (e) {
      print('Error processing frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void dispose() {
    streamResultController.close();
    _instance = null;
  }
}
