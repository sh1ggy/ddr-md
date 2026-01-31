import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

enum DifficultyType { None, FFXI }

enum ReturnImageType { None, DirImage, BytesImage }

class ProcessResult {
  final int score;
  final DifficultyType difficulty;
  // TODO reconsider to using a rect that can do Floats
  final Rectangle<int> roi;
  final bool isDetected;
  final ReturnImageType returnImageType;
  final Uint8List? processedImageBytes;

  ProcessResult(this.score, this.difficulty, this.roi, this.isDetected,
      this.returnImageType, this.processedImageBytes);
}

//TODO inf sending over Camera Image is too slow, send over buffer of TransferableTypedData instead
class ProcessImageRequestParams {
  // TODO This has to be multiple buffers transfered over
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int bytesPerPixel;
  // TODO Pass this in into isolate with initial request
  final String tempPath;

  ProcessImageRequestParams({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerPixel,
    required this.tempPath,
  });
}

class ProcessPickedImageRequestParams {
  final String imagePath;
  final String outputPath;

  ProcessPickedImageRequestParams({
    required this.imagePath,
    required this.outputPath,
  });
}

enum RequestType { ProcessVideoImage, ProcessPickedImage, Shutdown }

class Request {
  final RequestType type;
  final CameraImage? params;
  final String? pickedImagePath;

  Request._({
    required this.type,
    this.params,
    this.pickedImagePath,
  });

  Request.fromCamera(
    RequestType type,
    CameraImage params,
  ) : this._(
          type: type,
          params: params,
        );

  Request.fromFile(
    RequestType type,
    String path,
  ) : this._(
          type: type,
          pickedImagePath: path,
        );

  Request.death() : this._(type: RequestType.Shutdown);
}

class InitialRequest {
  final SendPort toMainThread;
  final String tempPath;
  final String appPath;

  InitialRequest(this.toMainThread, this.tempPath, this.appPath);
}

final DynamicLibrary _nativeLib = _openDynamicLibrary();

// Getting a library that holds needed symbols
DynamicLibrary _openDynamicLibrary() {
  return Platform.isAndroid
      ? DynamicLibrary.open("libnative_opencv.so")
      : DynamicLibrary.process();
}

// C Functions signatures
typedef _c_processImage = Void Function(
    Int32 width,
    Int32 height,
    Int32 bytesPerPixel,
    Pointer<Uint8> imageBytes,
    Pointer<Int32> outRoi,
    Pointer<Int32> outIsDetected,
    Pointer<Int32> outImgSize,
    Pointer<Uint8> outImgBuff,
    Pointer<Utf8> outImgPath);

typedef _c_processPickedImage = Void Function(
    Pointer<Utf8> inputImagePath,
    Pointer<Int32> outRoi,
    Pointer<Int32> outIsDetected,
    Pointer<Int32> outImgSize,
    Pointer<Uint8> outImgBuff,
    Pointer<Utf8> outImgPath);

// Dart functions signatures
typedef _dart_processImage = void Function(
    int width,
    int height,
    int bytesPerPixel,
    Pointer<Uint8> bytes,
    Pointer<Int32> outRoi,
    Pointer<Int32> outIsDetected,
    Pointer<Int32> outImgSize,
    Pointer<Uint8> outImgBuff,
    Pointer<Utf8> outImgPath);

typedef _dart_processPickedImage = void Function(
    Pointer<Utf8> inputImagePath,
    Pointer<Int32> outRoi,
    Pointer<Int32> outIsDetected,
    Pointer<Int32> outImgSize,
    Pointer<Uint8> outImgBuff,
    Pointer<Utf8> outImgPath);

// Create dart functions that invoke the C funcion
final _processCameraImageFn =
    _nativeLib.lookupFunction<_c_processImage, _dart_processImage>(
        'process_camera_image');
final _processPickedImageFn =
    _nativeLib.lookupFunction<_c_processPickedImage, _dart_processPickedImage>(
        'process_picked_image');

Future<ProcessResult> _processPickedImage(
    ProcessPickedImageRequestParams params) async {
  Pointer<Uint8> retImgBuff = nullptr; // Placeholder for processed image buffer

  Pointer<Int32> retRoi = calloc.allocate<Int32>(4 * 4); // x, y, width, height
  Pointer<Int32> retIsDetected = calloc.allocate<Int32>(4);

  Pointer<Int32> retImgSize = calloc.allocate<Int32>(4 * 2); // width, height

  print(params.imagePath);

  _processPickedImageFn(params.imagePath.toNativeUtf8(), retRoi, retIsDetected,
      retImgSize, retImgBuff, params.outputPath.toNativeUtf8());

  if (retRoi == nullptr) {
    calloc.free(retIsDetected);
    calloc.free(retRoi);
    return ProcessResult(0, DifficultyType.None, const Rectangle(0, 0, 0, 0),
        false, ReturnImageType.None, null);
  }

  final rectArray = retRoi.cast<Int32>().asTypedList(4);

  ProcessResult result = ProcessResult(
      100, // Placeholder score
      DifficultyType.FFXI, // Placeholder difficulty
      Rectangle<int>(
        rectArray[0],
        rectArray[1],
        rectArray[2],
        rectArray[3],
      ),
      retIsDetected.value != 0,
      ReturnImageType.DirImage,
      null);

  calloc.free(retRoi);
  calloc.free(retIsDetected);
  calloc.free(retImgSize);
  calloc.free(retImgBuff);

  return result;
}

Future<ProcessResult> _processFrame(ProcessImageRequestParams params) async {
  final bytes = params.bytes.materialize().asUint8List();
  // final bytes = params.bytes;

  Pointer<Uint8> imageBuffer = calloc<Uint8>(bytes.length);
  var uintImgBuffer = imageBuffer.asTypedList(bytes.length);
  uintImgBuffer.setAll(0, bytes);

  Pointer<Int32> retRoi = calloc.allocate<Int32>(4 * 4); // x, y, width, height
  Pointer<Int32> retIsDetected = calloc.allocate<Int32>(4);

  Pointer<Int32> retImgSize = calloc.allocate<Int32>(4 * 2); // width, height

  // return ProcessImageResult(
  //   100, // Placeholder score
  //   DifficultyType.FFXI, // Placeholder difficulty
  //   const Rectangle<int>(0, 0, 1100, 100),
  //   true,
  //   null,
  // );

  Pointer<Uint8> retImgBuff = nullptr; // Placeholder for processed image buffer

  print(params.tempPath);

  _processCameraImageFn(
      params.width,
      params.height,
      params.bytesPerPixel,
      imageBuffer,
      retRoi,
      retIsDetected,
      retImgSize,
      retImgBuff,
      params.tempPath.toNativeUtf8());

  if (retRoi == nullptr) {
    calloc.free(retIsDetected);
    calloc.free(retRoi);
    calloc.free(imageBuffer);
    return ProcessResult(0, DifficultyType.None, const Rectangle(0, 0, 0, 0),
        false, ReturnImageType.None, null);
  }

  final rectArray = retRoi.cast<Int32>().asTypedList(4);

  // final imgArray = retImgBuff.cast<Uint8>().asTypedList(
  //     params.width * params.height * params.bytesPerPixel); // Assuming RGBA

  ProcessResult result = ProcessResult(
      100, // Placeholder score
      DifficultyType.FFXI, // Placeholder difficulty
      Rectangle<int>(
        rectArray[0],
        rectArray[1],
        rectArray[2],
        rectArray[3],
      ),
      retIsDetected.value != 0,
      ReturnImageType.BytesImage,
      null);

  calloc.free(retRoi);
  calloc.free(imageBuffer);
  calloc.free(retIsDetected);
  calloc.free(retImgSize);
  calloc.free(retImgBuff);

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
        case RequestType.ProcessPickedImage:
          ProcessResult? res;
          var path = data.pickedImagePath!;
          var appPath = initReq.appPath;
          final params = ProcessPickedImageRequestParams(
            imagePath: path,
            outputPath: appPath,
          );
          _processPickedImage(params).then((result) {
            res = result;
            // Send the result back to the main thread
            _toMainThread.send(res);
          });
          break;
        case RequestType.ProcessVideoImage:
          ProcessResult? res;

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
            tempPath: initReq.tempPath,
          );

          _processFrame(params).then((result) {
            res = result;
            // Send the result back to the main thread
            _toMainThread.send(res);
          });
          break;

        case RequestType.Shutdown:
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

  Directory? tempDir;
  Directory? appDir; // for iOS

  final streamResultController = StreamController<ProcessResult>.broadcast();
  factory OCRProcessor() {
    _instance ??= OCRProcessor._internal();
    return _instance!;
  }

  bool _isProcessing = false;
  ReceivePort fromIsolate = ReceivePort();
  SendPort? toIsolate;
  Isolate? _isolate;

  OCRProcessor._internal() {}

  Future<void> init() async {
    tempDir = await getTemporaryDirectory();
    appDir = await getApplicationDocumentsDirectory();
  }

  Future<void> init_camera_actor() {
    Completer<void> completer = Completer<void>();
    // Prepare temp directory
    String tempPath = '${tempDir!.path}/temp.jpg';
    String appPath = '${appDir!.path}/temp.jpg';

    // Start the isolate
    Isolate.spawn(isolateEntryPoint,
            InitialRequest(fromIsolate.sendPort, tempPath, appPath))
        .then((isolate) {
      _isolate = isolate;
      // Wait for the isolate to send us its port
      fromIsolate.listen((data) {
        if (data is SendPort) {
          // We have received the SendPort from the isolate
          toIsolate = data;
          completer.complete();
        } else if (data is ProcessResult) {
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
  int FRAME_THRESHOLD = 10;

  void panicFromNotProcessing() {
    _isProcessing = false;
    skippedFrames = 0;
    print('Panic reset of OCR processing state invoked.');
    dispose();
  }

  void processPickedImage(XFile image) async {
    // Placeholder implementation
    print('Processing image from file: ${image.path}');
    final request =
        Request.fromFile(RequestType.ProcessPickedImage, image.path);
    _isProcessing = true;
    toIsolate?.send(request);
  }

  void processVideostreamFrame(CameraImage image) async {
    _cameraFrames++;
    if (_cameraFrames % FRAME_THRESHOLD != 0) {
      return;
    }

    if (_isProcessing) {
      skippedFrames++;
      if (skippedFrames > MAX_SKIPPED_FRAMES) {
        panicFromNotProcessing();
      }
      return;
    }

    print('Processing image frame... Camera frame #: $_cameraFrames');

    final request = Request.fromCamera(RequestType.ProcessVideoImage, image);
    _isProcessing = true;

    toIsolate?.send(request);
  }

  void dispose() {
    final request = Request.death();
    fromIsolate.sendPort.send(request);
    fromIsolate.close();

    _isolate?.kill(priority: Isolate.immediate);

    streamResultController.close();
    _instance = null;
  }
}
