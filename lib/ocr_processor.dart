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

//TODO inf sending over Camera Image is too slow, send over buffer of TransferableTypedData instead
class ProcessImageRequestParams {
  // TODO This has to be multiple buffers transfered over
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int bytesPerPixel;

  ProcessImageRequestParams({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerPixel,
  });
}

enum ReqeustType { ProcessImage, Shutdown }

class Request {
  final ReqeustType type;
  // final ProcessImageRequestParams? params;
  final CameraImage? params;

  Request(this.type, this.params);
}

class InitialRequest {
  final SendPort toMainThread;

  InitialRequest(this.toMainThread);
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
    ProcessImageRequestParams params) async {
  final bytes = params.bytes.materialize().asUint8List();
  // final bytes = params.bytes;

  Pointer<Uint8> imageBuffer = calloc<Uint8>(bytes.length);
  var uintImgBuffer = imageBuffer.asTypedList(bytes.length);
  uintImgBuffer.setAll(0, bytes);

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

void isolateEntryPoint(InitialRequest initReq) {
  // Save the port on which we will send messages to the main thread
  SendPort _toMainThread = initReq.toMainThread;

  // Create a port on which the main thread can send us messages and listen to it
  ReceivePort fromMainThread = ReceivePort();
  fromMainThread.listen((data) {
    if (data is Request) {
      switch (data.type) {
        case ReqeustType.ProcessImage:
          ProcessImageResult? res;

          var image = data.params!;
          Uint8List bytes;

          if (image.format.group == ImageFormatGroup.yuv420) {
            // On Android the image format is YUV and we get a buffer per channel,
            // in iOS the format is BGRA and we get a single buffer for all channels.
            // So the yBuffer variable on Android will be just the Y channel but on iOS it will be
            // the entire image
            var planes = image.planes;
            var yBuffer = planes[0].bytes;
            var uBuffer = planes[1].bytes;
            var vBuffer = planes[2].bytes;
            int totalSize = yBuffer.lengthInBytes +
                uBuffer.lengthInBytes +
                vBuffer.lengthInBytes;
            bytes = Uint8List(totalSize);
            bytes.setAll(0, yBuffer);
            //Swap the u and v buffers since thats what opencv wants for some reason 
            //(flutter opencv stream processing says so)

            bytes.setAll(yBuffer.lengthInBytes, vBuffer);
            bytes.setAll(
                yBuffer.lengthInBytes + vBuffer.lengthInBytes, uBuffer);
          } else {
            bytes = image.planes.first.bytes;
          }

          // Create TransferableTypedData for zero-copy transfer (theoretically we relinquish ownership here but should be fine)
          final transferable = TransferableTypedData.fromList([bytes]);

          final params = ProcessImageRequestParams(
            bytes: transferable,
            width: image.width,
            height: image.height,
            bytesPerPixel: 4,
          );

          _processFrameIsolate(params).then((result) {
            res = result;
            // Send the result back to the main thread
            _toMainThread.send(res);
          });
          break;

        case ReqeustType.Shutdown:
          // Clean up and exit
          fromMainThread.close();
          Isolate.exit();
          break;
        default:
          print('Unknown method: ${data.type.name}');
      }
    }
  });

  // Send the main thread the port on which it can send us messages
  _toMainThread.send(fromMainThread.sendPort);
}

class OCRProcessor {
  static OCRProcessor? _instance;

  final streamResultController = StreamController<ProcessImageResult>();
  factory OCRProcessor() {
    _instance ??= OCRProcessor._internal();
    return _instance!;
  }

  bool _isProcessing = false;
  ReceivePort fromIsolate = ReceivePort();
  SendPort? toIsolate;
  Isolate? _isolate;

  OCRProcessor._internal() {}

  Future<void> init() {
    Completer<void> completer = Completer<void>();

    // Start the isolate
    Isolate.spawn(isolateEntryPoint, InitialRequest(fromIsolate.sendPort))
        .then((isolate) {
      _isolate = isolate;
      // Wait for the isolate to send us its port
      fromIsolate.listen((data) {
        if (data is SendPort) {
          // We have received the SendPort from the isolate
          toIsolate = data;
          completer.complete();
        } else if (data is ProcessImageResult) {
          // We have received a result from the isolate
          _isProcessing = false;
          streamResultController.add(data);
        }
      });
    });

    return completer.future;
  }

  int MAX_SKIPPED_FRAMES = 20;

  int _cameraFrames = 0;
  int skippedFrames = 0;

  void panicFromNotProcessing() {
    _isProcessing = false;
    skippedFrames = 0;
    print('Panic reset of OCR processing state invoked.');
    dispose();
  }

  void processFrame(CameraImage image) async {
    _cameraFrames++;
    if (_cameraFrames % 10 != 0) {
      return;
    }

    if (_isProcessing) {
      skippedFrames++;
      if (skippedFrames > MAX_SKIPPED_FRAMES) {
        // panicFromNotProcessing();
      }
      return;
    }

    print('Processing image frame... Camera frame #: $_cameraFrames');

    final request = Request(ReqeustType.ProcessImage, image);
    _isProcessing = true;

    toIsolate?.send(request);
  }

  void dispose() {
    final request = Request(ReqeustType.Shutdown, null);
    fromIsolate.sendPort.send(request);
    fromIsolate.close();

    _isolate?.kill(priority: Isolate.immediate);

    streamResultController.close();
    _instance = null;
  }
}
