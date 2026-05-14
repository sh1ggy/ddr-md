import 'dart:async';
import 'dart:ffi';
import 'ocr_config.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum DifficultyType { None, FFXI }

enum DetectionSide { first, left, right }

const DetectionSide kDetectionSide = DetectionSide.left;

enum ReturnImageType { None, DirImage, BytesImage }

class ProcessResult {
  final DifficultyType difficulty;
  // TODO reconsider to using a rect that can do Floats
  final Rectangle<int>? roi;
  final List<Rectangle<int>>? detectedRois;
  final bool isDetected;
  final ReturnImageType returnImageType;
  final Uint8List? processedImageBytes;
  final int? detailsRoiIndex;
  final Map<String, String> ocrStrings;

  ProcessResult(
      this.difficulty,
      this.roi,
      this.detectedRois,
      this.isDetected,
      this.returnImageType,
      this.processedImageBytes,
      this.detailsRoiIndex,
      this.ocrStrings);
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

// Mirrors C COCRConfig struct — layout must match exactly (348 bytes).
// offset  0: border               Int32
// offset  4: psm_eng              Int32
// offset  8: psm_engjp            Int32
// offset 12: gaussian_blur_size   Int32
// offset 16: simplification_epsilon Double
// offset 24: area_min_factor      Double
// offset 32: area_max_factor      Double
// offset 40: resolution_scale     Double
// offset 48: tophat_kernel_size   Int32
// offset 52: morph_width          Int32
// offset 56: morph_height         Int32
// offset 60: roi[12][6]           Array<Array<Int32>>
final class COCRConfig extends Struct {
  @Int32()
  external int border;
  @Int32()
  external int psmEng;
  @Int32()
  external int psmEngJP;
  @Int32()
  external int gaussianBlurSize;
  @Double()
  external double simplificationEpsilon;
  @Double()
  external double areaMinFactor;
  @Double()
  external double areaMaxFactor;
  @Double()
  external double resolutionScale;
  @Int32()
  external int tophatKernelSize;
  @Int32()
  external int morphWidth;
  @Int32()
  external int morphHeight;
  @Array(12, 6)
  external Array<Array<Int32>> roi;
}

final class COCRStrings extends Struct {
  external Pointer<Char> score;
  external Pointer<Char> marvelous;
  external Pointer<Char> perfect;
  external Pointer<Char> great;
  external Pointer<Char> good;
  external Pointer<Char> miss;
  external Pointer<Char> flare;
  external Pointer<Char> title;
  external Pointer<Char> username;
  external Pointer<Char> difficulty;
  external Pointer<Char> maxCombo;
}

// C Functions signatures
typedef _c_processCameraImage = Void Function(
    Int32 imgWidth,
    Int32 imgHeight,
    Int32 bytesPerPixel,
    Pointer<Uint8> imgBuffer,
    Pointer<Int32> outputRoi,
    Pointer<Int32> outputIsDetected,
    Pointer<Int32> outputImgSize,
    Pointer<Uint8> outputImgBuff,
    Pointer<Utf8> outputImgPath);

typedef _c_processPickedImage = Void Function(
  Pointer<Utf8> inputImagePath,
  Pointer<Int32> outputIsRoisDetected,
  Pointer<Utf8> outputImgPath,
  Pointer<Pointer<Int32>> outputRois,
  Pointer<Int32> outputRoisCount,
  Pointer<Int32> outputdetailsRoiIndex,
  Pointer<COCRStrings> outStrings,
  Int32 side,
);

// Dart functions signatures
typedef _dart_processCameraImage = void Function(
    int imgWidth,
    int imgHeight,
    int bytesPerPixel,
    Pointer<Uint8> imgBuffer,
    Pointer<Int32> outputRoi,
    Pointer<Int32> outputIsDetected,
    Pointer<Int32> outputImgSize,
    Pointer<Uint8> outputImgBuff,
    Pointer<Utf8> outputImgPath);

typedef _dart_processPickedImage = void Function(
  Pointer<Utf8> inputImagePath,
  Pointer<Int32> outputIsDetected,
  Pointer<Utf8> outputImgPath,
  Pointer<Pointer<Int32>> outputRois,
  Pointer<Int32> outputRoisCount,
  Pointer<Int32> outputdetailsRoiIndex,
  Pointer<COCRStrings> outStrings,
  int side,
);

typedef _c_setOcrConfig = Void Function(Pointer<COCRConfig>);
typedef _dart_setOcrConfig = void Function(Pointer<COCRConfig>);

// Create dart functions that invoke the C funcion
final _processCameraImageFn =
    _nativeLib.lookupFunction<_c_processCameraImage, _dart_processCameraImage>(
        'process_camera_image');
final _processPickedImageFn =
    _nativeLib.lookupFunction<_c_processPickedImage, _dart_processPickedImage>(
        'process_picked_image');
final _setOcrConfigFn =
    _nativeLib.lookupFunction<_c_setOcrConfig, _dart_setOcrConfig>(
        'set_ocr_config');

void _callSetOcrConfig() {
  final p = calloc<COCRConfig>();
  p.ref.border = ocrBorder;
  p.ref.psmEng = ocrPsmEng;
  p.ref.psmEngJP = ocrPsmEngJP;
  p.ref.gaussianBlurSize = ocrGaussianBlurSize;
  p.ref.simplificationEpsilon = ocrSimplificationEpsilon;
  p.ref.areaMinFactor = ocrAreaMinFactor;
  p.ref.areaMaxFactor = ocrAreaMaxFactor;
  p.ref.resolutionScale = ocrResolutionScale;
  p.ref.tophatKernelSize = ocrTophatKernelSize;
  p.ref.morphWidth = ocrMorphWidth;
  p.ref.morphHeight = ocrMorphHeight;
  for (int r = 0; r < 12; r++) {
    final (rect, (ex, ey)) = ocrRoi[r];
    p.ref.roi[r][roiX1] = rect[roiX1];
    p.ref.roi[r][roiY1] = rect[roiY1];
    p.ref.roi[r][roiX2] = rect[roiX2];
    p.ref.roi[r][roiY2] = rect[roiY2];
    p.ref.roi[r][roiExpandX] = ex;
    p.ref.roi[r][roiExpandY] = ey;
  }
  _setOcrConfigFn(p);
  calloc.free(p);
}

Future<ProcessResult> _processPickedImage(
    ProcessPickedImageRequestParams params) async {
  Pointer<Int32> outputIsDetected = calloc.allocate<Int32>(4);
  Pointer<Int32> outputRoisCount = calloc.allocate<Int32>(4);
  Pointer<Pointer<Int32>> outputRoisPtr = calloc<Pointer<Int32>>();
  Pointer<Int32> outputdetailsRoiIndex = calloc.allocate<Int32>(4);
  Pointer<Char> scorePtr = calloc<Char>(256);
  Pointer<Char> marvelousPtr = calloc<Char>(256);
  Pointer<Char> perfectPtr = calloc<Char>(256);
  Pointer<Char> greatPtr = calloc<Char>(256);
  Pointer<Char> goodPtr = calloc<Char>(256);
  Pointer<Char> missPtr = calloc<Char>(256);
  Pointer<Char> flarePtr = calloc<Char>(256);
  Pointer<Char> usernamePtr = calloc<Char>(256);
  Pointer<Char> difficultyPtr = calloc<Char>(256);
  Pointer<Char> maxComboPtr = calloc<Char>(256);
  Pointer<COCRStrings> outStrings = calloc<COCRStrings>();

  outStrings.ref.score = scorePtr;
  outStrings.ref.marvelous = marvelousPtr;
  outStrings.ref.perfect = perfectPtr;
  outStrings.ref.great = greatPtr;
  outStrings.ref.good = goodPtr;
  outStrings.ref.miss = missPtr;
  outStrings.ref.flare = flarePtr;
  outStrings.ref.username = usernamePtr;
  outStrings.ref.difficulty = difficultyPtr;
  outStrings.ref.maxCombo = maxComboPtr;

  _processPickedImageFn(
    params.imagePath.toNativeUtf8(),
    outputIsDetected,
    params.outputPath.toNativeUtf8(),
    outputRoisPtr,
    outputRoisCount,
    outputdetailsRoiIndex,
    outStrings,
    kDetectionSide.index,
  );
  final Pointer<Int32> outputRois = outputRoisPtr.value; // dereference

  if (outputRois == nullptr) {
    calloc.free(outputRoisPtr);
    calloc.free(outputIsDetected);
    calloc.free(outputRoisCount);
    calloc.free(outputdetailsRoiIndex);

    calloc.free(scorePtr);
    calloc.free(marvelousPtr);
    calloc.free(perfectPtr);
    calloc.free(greatPtr);
    calloc.free(goodPtr);
    calloc.free(missPtr);
    calloc.free(flarePtr);
    calloc.free(usernamePtr);
    calloc.free(difficultyPtr);
    calloc.free(maxComboPtr);

    calloc.free(outStrings);
    return ProcessResult(DifficultyType.None, null, [], false,
        ReturnImageType.None, null, -1, {});
  }

  List<Rectangle<int>> detectedRois = [];
  for (int i = 0; i < outputRoisCount.value; i++) {
    // Each rect consists of 4 integers: x, y, width, height
    int baseIndex = i * 4;
    // Access the rectangle values using baseIndex
    int x = outputRois[baseIndex];
    int y = outputRois[baseIndex + 1];
    int width = outputRois[baseIndex + 2];
    int height = outputRois[baseIndex + 3];
    detectedRois.add(Rectangle<int>(x, y, width, height));
    print('Detected ROI $i: x=$x, y=$y, width=$width, height=$height');
  }

  ProcessResult result = ProcessResult(
    DifficultyType.FFXI, // Placeholder difficulty
    null, // No single ROI for picked images
    detectedRois, // List of detected ROIs
    outputIsDetected.value != 0,
    ReturnImageType.DirImage,
    null,
    outputdetailsRoiIndex.value,
    {
      'score': outStrings.ref.score.cast<Utf8>().toDartString(),
      'marvelous': outStrings.ref.marvelous.cast<Utf8>().toDartString(),
      'perfect': outStrings.ref.perfect.cast<Utf8>().toDartString(),
      'great': outStrings.ref.great.cast<Utf8>().toDartString(),
      'good': outStrings.ref.good.cast<Utf8>().toDartString(),
      'miss': outStrings.ref.miss.cast<Utf8>().toDartString(),
    },
  );

  calloc.free(outputRois);
  calloc.free(outputIsDetected);
  calloc.free(outputRoisPtr);
  calloc.free(outputRoisCount);
  calloc.free(outputdetailsRoiIndex);
  // score items
  calloc.free(scorePtr);
  calloc.free(marvelousPtr);
  calloc.free(perfectPtr);
  calloc.free(greatPtr);
  calloc.free(goodPtr);
  calloc.free(missPtr);
  calloc.free(outStrings);

  return result;
}

Future<ProcessResult> _processFrame(ProcessImageRequestParams params) async {
  final bytes = params.bytes.materialize().asUint8List();
  // final bytes = params.bytes;

  Pointer<Uint8> imgBuffer = calloc<Uint8>(bytes.length);
  var uintImgBuffer = imgBuffer.asTypedList(bytes.length);
  uintImgBuffer.setAll(0, bytes);

  Pointer<Int32> outputRoi =
      calloc.allocate<Int32>(4 * 4); // x, y, width, height
  Pointer<Int32> outputIsDetected = calloc.allocate<Int32>(4);

  Pointer<Int32> outputImgSize = calloc.allocate<Int32>(4 * 2); // width, height

  // return ProcessImageResult(
  //   100, // Placeholder score
  //   DifficultyType.FFXI, // Placeholder difficulty
  //   const Rectangle<int>(0, 0, 1100, 100),
  //   true,
  //   null,
  // );

  Pointer<Uint8> outputImgBuff =
      nullptr; // Placeholder for processed image buffer

  print(params.tempPath);

  _processCameraImageFn(
      params.width,
      params.height,
      params.bytesPerPixel,
      imgBuffer,
      outputRoi,
      outputIsDetected,
      outputImgSize,
      outputImgBuff,
      params.tempPath.toNativeUtf8());

  if (outputRoi == nullptr) {
    calloc.free(outputIsDetected);
    calloc.free(outputRoi);
    calloc.free(imgBuffer);
    calloc.free(outputImgSize);
    return ProcessResult(DifficultyType.None, null, [], false,
        ReturnImageType.None, null, -1, {});
  }

  final rectArray = outputRoi.cast<Int32>().asTypedList(4);

  // final imgArray = outputImgBuff.cast<Uint8>().asTypedList(
  //     params.width * params.height * params.bytesPerPixel); // Assuming RGBA

  ProcessResult result = ProcessResult(
    DifficultyType.FFXI, // Placeholder difficulty
    Rectangle<int>(
      rectArray[0],
      rectArray[1],
      rectArray[2],
      rectArray[3],
    ),
    null,
    outputIsDetected.value != 0,
    ReturnImageType.BytesImage,
    null,
    null, // Placeholder for details detected
    {},
  );

  calloc.free(outputRoi);
  calloc.free(imgBuffer);
  calloc.free(outputIsDetected);
  calloc.free(outputImgSize);
  calloc.free(outputImgBuff);

  return result;
}

void isolateEntryPoint(InitialRequest initReq) {
  // Save the port on which we will send messages to the main thread
  SendPort _toMainThread = initReq.toMainThread;

  // Create a port on which the main thread can send us messages and listen to it
  ReceivePort fromMainThread = ReceivePort();
  _callSetOcrConfig();
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
            tempPath: initReq.appPath,
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

  // TODO: two controllers cos dynamic is gay
  final streamResultController = StreamController<ProcessResult>.broadcast();

  bool _isProcessing = false;
  ReceivePort fromIsolate = ReceivePort();
  SendPort? toIsolate;
  Isolate? _isolate;

  Future<void> init() async {
    tempDir = await getTemporaryDirectory();
    appDir = await getApplicationDocumentsDirectory();
    await loadTessdata();
  }

  Future<void> loadTessdata() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // Tessdata copying is only needed for mobile platforms.
      print('Skipping tessdata copy on unsupported platform: ${Platform.operatingSystem}');
      return;
    }

    final tessdataDir = Directory(path.join(appDir!.path, 'tessdata'));
    if (!await tessdataDir.exists()) {
      await tessdataDir.create(recursive: true);
    }

    final tessdataAssets = [
      'assets/tessdata/eng.best.traineddata',
      'assets/tessdata/eng.fast.traineddata',
      'assets/tessdata/jpn.best.traineddata',
      'assets/tessdata/jpn.fast.traineddata',
    ];

    for (final assetPath in tessdataAssets) {
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      final targetFile = File(path.join(tessdataDir.path, path.basename(assetPath)));
      await targetFile.writeAsBytes(bytes, flush: true);
      print('Copied tessdata asset $assetPath -> ${targetFile.path}');
    }

    print('Tessdata loaded to ${tessdataDir.path}');
  }

  Future<void> initActor() {
    Completer<void> completer = Completer<void>();
    // Prepare temp directory
    String tempPath = tempDir!.path;
    String appPath = appDir!.path;

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
    print('Processing image from file: ${image.path}');
    final request = Request.fromFile(
      RequestType.ProcessPickedImage,
      image.path,
    );
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
  }
}
