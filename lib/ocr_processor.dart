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

// Whether the native pipeline should capture debug images for on-device
// inspection. Ordinals must match the C++ DebugImageType enum.
enum DebugImageType { none, on }

class ProcessResult {
  final DifficultyType difficulty;
  // TODO reconsider to using a rect that can do Floats
  final Rectangle<int>? roi;
  final List<Rectangle<int>>? detectedRois;
  final bool isDetected;
  final ReturnImageType returnImageType;
  // Full-frame binarized mask (preprocessed_BW1) for every processed frame when
  // debug is on; null otherwise.
  final Uint8List? debugMaskBytes;
  // Crop Tesseract matched on, present only when this frame matched "Details".
  // The UI persists the last non-null one across failed frames.
  final Uint8List? debugDetailsCropBytes;
  // Full-color JPEG of the frame, present only when this frame matched
  // "Details" (independent of the debug toggle). The stopped view paints the
  // static ROIs over the last non-null one.
  final Uint8List? captureBytes;
  final int? detailsRoiIndex;
  final Map<String, String> ocrStrings;

  ProcessResult(
      this.difficulty,
      this.roi,
      this.detectedRois,
      this.isDetected,
      this.returnImageType,
      this.debugMaskBytes,
      this.debugDetailsCropBytes,
      this.captureBytes,
      this.detailsRoiIndex,
      this.ocrStrings);
}

// Camera frame bytes are extracted on the main thread and handed to the isolate
// via TransferableTypedData (zero-copy on receive).
class ProcessImageRequestParams {
  final TransferableTypedData bytes;
  final int width;
  final int height;
  // Row stride of the source buffer in bytes. iOS BGRA frames are often padded
  // (bytesPerRow > width*4); the native layer needs the real stride to read
  // rows at the right offset. 0 means "tightly packed" (the Android YUV path).
  final int bytesPerRow;
  // Camera sensor orientation (0/90/180/270), passed to the native layer for
  // potential per-device orientation handling. Currently unused there: the iOS
  // BGRA frame already arrives portrait (no rotation needed) and Android's YUV
  // frame is hard-coded to 90° CW. Kept plumbed for future use.
  final int sensorOrientation;
  final DebugImageType debugImageType;

  ProcessImageRequestParams({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.sensorOrientation,
    this.debugImageType = DebugImageType.none,
  });
}

class ProcessPickedImageRequestParams {
  final String imagePath;

  ProcessPickedImageRequestParams({required this.imagePath});
}

enum RequestType { ProcessVideoImage, ProcessPickedImage, Shutdown }

class Request {
  final RequestType type;
  final ProcessImageRequestParams? cameraParams;
  final String? pickedImagePath;

  Request._({
    required this.type,
    this.cameraParams,
    this.pickedImagePath,
  });

  Request.fromCamera(
    RequestType type,
    ProcessImageRequestParams params,
  ) : this._(
          type: type,
          cameraParams: params,
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
typedef _c_createOcrInstance = Pointer<Void> Function(Pointer<Utf8>, Pointer<COCRConfig>);
typedef _dart_createOcrInstance = Pointer<Void> Function(Pointer<Utf8>, Pointer<COCRConfig>);

typedef _c_destroyOcrInstance = Void Function(Pointer<Void>);
typedef _dart_destroyOcrInstance = void Function(Pointer<Void>);

typedef _c_processCameraImage = Void Function(
    Pointer<Void> handle,
    Int32 imgWidth,
    Int32 imgHeight,
    Int32 bytesPerRow,
    Int32 sensorOrientation,
    Pointer<Uint8> imgBuffer,
    Pointer<Int32> outputIsDetected,
    Pointer<Pointer<Int32>> outputRois,
    Pointer<Int32> outputRoisCount,
    Pointer<Int32> outputdetailsRoiIndex,
    Pointer<COCRStrings> outStrings,
    Int32 debugImageType,
    Pointer<Pointer<Uint8>> outputDebugMask,
    Pointer<Int32> outputDebugMaskLen,
    Pointer<Pointer<Uint8>> outputDebugCrop,
    Pointer<Int32> outputDebugCropLen,
    Pointer<Pointer<Uint8>> outputCapture,
    Pointer<Int32> outputCaptureLen);

typedef _c_processPickedImage = Void Function(
  Pointer<Void> handle,
  Pointer<Utf8> inputImagePath,
  Pointer<Int32> outputIsDetected,
  Pointer<Pointer<Int32>> outputRois,
  Pointer<Int32> outputRoisCount,
  Pointer<Int32> outputdetailsRoiIndex,
  Pointer<COCRStrings> outStrings,
  Int32 side,
);

// Dart functions signatures
typedef _dart_processCameraImage = void Function(
    Pointer<Void> handle,
    int imgWidth,
    int imgHeight,
    int bytesPerRow,
    int sensorOrientation,
    Pointer<Uint8> imgBuffer,
    Pointer<Int32> outputIsDetected,
    Pointer<Pointer<Int32>> outputRois,
    Pointer<Int32> outputRoisCount,
    Pointer<Int32> outputdetailsRoiIndex,
    Pointer<COCRStrings> outStrings,
    int debugImageType,
    Pointer<Pointer<Uint8>> outputDebugMask,
    Pointer<Int32> outputDebugMaskLen,
    Pointer<Pointer<Uint8>> outputDebugCrop,
    Pointer<Int32> outputDebugCropLen,
    Pointer<Pointer<Uint8>> outputCapture,
    Pointer<Int32> outputCaptureLen);

typedef _dart_processPickedImage = void Function(
  Pointer<Void> handle,
  Pointer<Utf8> inputImagePath,
  Pointer<Int32> outputIsDetected,
  Pointer<Pointer<Int32>> outputRois,
  Pointer<Int32> outputRoisCount,
  Pointer<Int32> outputdetailsRoiIndex,
  Pointer<COCRStrings> outStrings,
  int side,
);

// Create dart functions that invoke the C funcion
final _createOcrInstanceFn =
    _nativeLib.lookupFunction<_c_createOcrInstance, _dart_createOcrInstance>(
        'create_ocr_instance');
final _destroyOcrInstanceFn =
    _nativeLib.lookupFunction<_c_destroyOcrInstance, _dart_destroyOcrInstance>(
        'destroy_ocr_instance');
final _processCameraImageFn =
    _nativeLib.lookupFunction<_c_processCameraImage, _dart_processCameraImage>(
        'process_camera_image');
final _processPickedImageFn =
    _nativeLib.lookupFunction<_c_processPickedImage, _dart_processPickedImage>(
        'process_picked_image');

// Builds a COCRConfig struct from ocr_config.dart constants.
// Caller must calloc.free() the returned pointer.
Pointer<COCRConfig> _buildOCRConfig() {
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
  return p;
}

// Reads the 6 score/judgement strings the UI displays. C allocates each field
// with malloc; the corresponding _freeOcrStrings releases them.
Map<String, String> _readOcrStrings(Pointer<COCRStrings> p) {
  String read(Pointer<Char> s) =>
      s == nullptr ? '' : s.cast<Utf8>().toDartString();
  final r = p.ref;
  return {
    'score': read(r.score),
    'marvelous': read(r.marvelous),
    'perfect': read(r.perfect),
    'great': read(r.great),
    'good': read(r.good),
    'miss': read(r.miss),
  };
}

void _freeOcrStrings(Pointer<COCRStrings> p) {
  final r = p.ref;
  for (final s in [
    r.score,
    r.marvelous,
    r.perfect,
    r.great,
    r.good,
    r.miss,
    r.flare,
    r.title,
    r.username,
    r.difficulty,
    r.maxCombo
  ]) {
    if (s != nullptr) calloc.free(s);
  }
  calloc.free(p);
}

// Builds a ProcessResult from the FFI output pointers and frees all of them
// (including the C-allocated rois array and strings). Shared by the picked-image
// and camera paths, which produce identical output.
// Copies the encoded image bytes the native layer allocated (if any) into a
// Dart-owned Uint8List, then frees the native buffer and the length/pointer
// cells. Safe to call when no image was requested — the pointers are null/0.
Uint8List? _readAndFreeImage(
  Pointer<Pointer<Uint8>>? outputImagePtr,
  Pointer<Int32>? outputImageLen,
) {
  if (outputImagePtr == null || outputImageLen == null) return null;
  final buf = outputImagePtr.value;
  final len = outputImageLen.value;
  Uint8List? bytes;
  if (buf != nullptr && len > 0) {
    bytes = Uint8List.fromList(buf.asTypedList(len));
    calloc.free(buf);
  }
  calloc.free(outputImagePtr);
  calloc.free(outputImageLen);
  return bytes;
}

ProcessResult _buildAndFreeResult({
  required Pointer<Int32> outputIsDetected,
  required Pointer<Pointer<Int32>> outputRoisPtr,
  required Pointer<Int32> outputRoisCount,
  required Pointer<Int32> outputDetailsRoiIndex,
  required Pointer<COCRStrings> outStrings,
  Pointer<Pointer<Uint8>>? outputDebugMaskPtr,
  Pointer<Int32>? outputDebugMaskLen,
  Pointer<Pointer<Uint8>>? outputDebugCropPtr,
  Pointer<Int32>? outputDebugCropLen,
  Pointer<Pointer<Uint8>>? outputCapturePtr,
  Pointer<Int32>? outputCaptureLen,
}) {
  final Uint8List? maskBytes =
      _readAndFreeImage(outputDebugMaskPtr, outputDebugMaskLen);
  final Uint8List? cropBytes =
      _readAndFreeImage(outputDebugCropPtr, outputDebugCropLen);
  final Uint8List? captureBytes =
      _readAndFreeImage(outputCapturePtr, outputCaptureLen);
  final ReturnImageType imageType = (maskBytes != null || cropBytes != null)
      ? ReturnImageType.BytesImage
      : ReturnImageType.None;

  final Pointer<Int32> outputRois = outputRoisPtr.value;

  if (outputRois == nullptr) {
    calloc.free(outputRoisPtr);
    calloc.free(outputIsDetected);
    calloc.free(outputRoisCount);
    calloc.free(outputDetailsRoiIndex);
    _freeOcrStrings(outStrings);
    return ProcessResult(DifficultyType.None, null, [], false,
        imageType, maskBytes, cropBytes, captureBytes, -1, {});
  }

  final detectedRois = <Rectangle<int>>[];
  for (int i = 0; i < outputRoisCount.value; i++) {
    final base = i * 4;
    detectedRois.add(Rectangle<int>(outputRois[base], outputRois[base + 1],
        outputRois[base + 2], outputRois[base + 3]));
  }

  final result = ProcessResult(
    DifficultyType.FFXI,
    null,
    detectedRois,
    outputIsDetected.value != 0,
    imageType,
    maskBytes,
    cropBytes,
    captureBytes,
    outputDetailsRoiIndex.value,
    _readOcrStrings(outStrings),
  );

  calloc.free(outputRois);
  calloc.free(outputRoisPtr);
  calloc.free(outputIsDetected);
  calloc.free(outputRoisCount);
  calloc.free(outputDetailsRoiIndex);
  _freeOcrStrings(outStrings);
  return result;
}

Future<ProcessResult> _processPickedImage(
    Pointer<Void> handle, ProcessPickedImageRequestParams params) async {
  final outputIsDetected = calloc<Int32>();
  final outputRoisCount = calloc<Int32>();
  final outputRoisPtr = calloc<Pointer<Int32>>();
  final outputDetailsRoiIndex = calloc<Int32>();
  final outStrings = calloc<COCRStrings>();

  final imagePathPtr = params.imagePath.toNativeUtf8();
  _processPickedImageFn(
    handle,
    imagePathPtr,
    outputIsDetected,
    outputRoisPtr,
    outputRoisCount,
    outputDetailsRoiIndex,
    outStrings,
    kDetectionSide.index,
  );
  calloc.free(imagePathPtr);

  return _buildAndFreeResult(
    outputIsDetected: outputIsDetected,
    outputRoisPtr: outputRoisPtr,
    outputRoisCount: outputRoisCount,
    outputDetailsRoiIndex: outputDetailsRoiIndex,
    outStrings: outStrings,
  );
}

Future<ProcessResult> _processFrame(
    Pointer<Void> handle, ProcessImageRequestParams params) async {
  final bytes = params.bytes.materialize().asUint8List();

  final imgBuffer = calloc<Uint8>(bytes.length);
  imgBuffer.asTypedList(bytes.length).setAll(0, bytes);

  final outputIsDetected = calloc<Int32>();
  final outputRoisCount = calloc<Int32>();
  final outputRoisPtr = calloc<Pointer<Int32>>();
  final outputDetailsRoiIndex = calloc<Int32>();
  final outStrings = calloc<COCRStrings>();
  final outputDebugMaskPtr = calloc<Pointer<Uint8>>();
  final outputDebugMaskLen = calloc<Int32>();
  final outputDebugCropPtr = calloc<Pointer<Uint8>>();
  final outputDebugCropLen = calloc<Int32>();
  final outputCapturePtr = calloc<Pointer<Uint8>>();
  final outputCaptureLen = calloc<Int32>();

  _processCameraImageFn(
    handle,
    params.width,
    params.height,
    params.bytesPerRow,
    params.sensorOrientation,
    imgBuffer,
    outputIsDetected,
    outputRoisPtr,
    outputRoisCount,
    outputDetailsRoiIndex,
    outStrings,
    params.debugImageType.index,
    outputDebugMaskPtr,
    outputDebugMaskLen,
    outputDebugCropPtr,
    outputDebugCropLen,
    outputCapturePtr,
    outputCaptureLen,
  );
  calloc.free(imgBuffer);

  return _buildAndFreeResult(
    outputIsDetected: outputIsDetected,
    outputRoisPtr: outputRoisPtr,
    outputRoisCount: outputRoisCount,
    outputDetailsRoiIndex: outputDetailsRoiIndex,
    outStrings: outStrings,
    outputDebugMaskPtr: outputDebugMaskPtr,
    outputDebugMaskLen: outputDebugMaskLen,
    outputDebugCropPtr: outputDebugCropPtr,
    outputDebugCropLen: outputDebugCropLen,
    outputCapturePtr: outputCapturePtr,
    outputCaptureLen: outputCaptureLen,
  );
}

void isolateEntryPoint(InitialRequest initReq) {
  // Save the port on which we will send messages to the main thread
  SendPort _toMainThread = initReq.toMainThread;

  // This isolate owns its own native DdrocrInstance for its whole lifetime, so
  // it is the sole thread ever touching that instance (and its Tesseract APIs).
  final dataPathPtr = initReq.appPath.toNativeUtf8();
  final cfg = _buildOCRConfig();
  final handle = _createOcrInstanceFn(dataPathPtr, cfg);
  calloc.free(dataPathPtr);
  calloc.free(cfg);

  // Create a port on which the main thread can send us messages and listen to it
  ReceivePort fromMainThread = ReceivePort();
  fromMainThread.listen((data) {
    if (data is Request) {
      switch (data.type) {
        case RequestType.ProcessPickedImage:
          final params =
              ProcessPickedImageRequestParams(imagePath: data.pickedImagePath!);
          _processPickedImage(handle, params).then(_toMainThread.send);
          break;
        case RequestType.ProcessVideoImage:
          _processFrame(handle, data.cameraParams!).then(_toMainThread.send);
          break;
        case RequestType.Shutdown:
          _destroyOcrInstanceFn(handle);
          fromMainThread.close();
          Isolate.exit();
      }
    }
  });

  // Send the main thread the port on which it can send us messages
  _toMainThread.send(fromMainThread.sendPort);
}

class OCRProcessor {
  Directory? tempDir;
  Directory? appDir; // for iOS

  // TODO: two controllers cos dynamic is gay
  final streamResultController = StreamController<ProcessResult>.broadcast();

  /// Publicly observable processing state. True while the isolate is crunching
  /// a frame or picked image; false once a result (or panic reset) arrives.
  final ValueNotifier<bool> isProcessing = ValueNotifier(false);

  /// True from the moment Stop is pressed until the post-stop frame queue has
  /// genuinely drained. The camera plugin keeps delivering already-queued frames
  /// after stopImageStream() resolves, and [isProcessing] only reflects the
  /// single in-flight frame — so it flickers off in the gaps between queued
  /// frames. This stays true across those gaps (debounced on frame activity) so
  /// the UI can show one continuous "Finalising…" state until the queue is empty.
  final ValueNotifier<bool> isDraining = ValueNotifier(false);

  // Quiet window with no submitted frame (and nothing in flight) after which the
  // post-stop queue is considered drained.
  static const Duration _drainQuietWindow = Duration(milliseconds: 600);
  Timer? _drainTimer;

  bool get _isProcessing => isProcessing.value;
  set _isProcessing(bool v) => isProcessing.value = v;
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
      final targetFile = File(path.join(tessdataDir.path, path.basename(assetPath)));
      if (await targetFile.exists()) {
        print('Tessdata already exists, skipping: ${targetFile.path}');
        continue;
      }
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
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

  // Which debug image (if any) the native pipeline should return per frame. Set
  // by the UI; none in the hot path by default so there is zero encode cost.
  DebugImageType debugImageType = DebugImageType.none;

  int MAX_SKIPPED_FRAMES = 20;

  int _cameraFrames = 0;
  int skippedFrames = 0;
  int FRAME_THRESHOLD = 3;

  void panicFromNotProcessing() {
    _isProcessing = false;
    skippedFrames = 0;
    print('Panic reset of OCR processing state invoked. Continuing without dispose.');
  }

  // Called by the UI when Stop is pressed. Enters the draining state and arms the
  // quiet-window timer; each post-stop frame that arrives re-arms it, so draining
  // only ends once frames have genuinely stopped flowing and nothing is in flight.
  void beginDraining() {
    isDraining.value = true;
    _armDrainTimer();
  }

  // Cancel any in-progress draining — e.g. the user restarted OCR before the
  // previous run's queue finished emptying.
  void cancelDraining() {
    _drainTimer?.cancel();
    isDraining.value = false;
  }

  void _armDrainTimer() {
    _drainTimer?.cancel();
    _drainTimer = Timer(_drainQuietWindow, () {
      // If a frame is still being crunched, wait another window — the result
      // (or its panic reset) will re-evaluate. Otherwise the queue has drained.
      if (_isProcessing) {
        _armDrainTimer();
      } else {
        isDraining.value = false;
      }
    });
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

  void processVideostreamFrame(CameraImage image, int sensorOrientation) {
    // Frames the camera plugin delivers after stopImageStream() are still
    // processed — they may contain a late detection — so the stream drains
    // naturally. The UI surfaces this background work via [isProcessing].
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

    // Extract the frame bytes here (main thread) and hand them to the isolate
    // via TransferableTypedData so the cross-isolate transfer is zero-copy.
    Uint8List bytes;
    // iOS BGRA frames may be row-padded; hand the native layer the real stride
    // so it reads each row at the correct offset (0 => tightly packed, used by
    // the Android YUV path, which is rebuilt contiguously below).
    int bytesPerRow = 0;
    if (image.format.group == ImageFormatGroup.yuv420) {
      // Android: a buffer per YUV channel. iOS: a single BGRA buffer.
      final planes = image.planes;
      final yBuffer = planes[0].bytes;
      final uBuffer = planes[1].bytes;
      final vBuffer = planes[2].bytes;
      final totalSize =
          yBuffer.lengthInBytes + uBuffer.lengthInBytes + vBuffer.lengthInBytes;
      bytes = Uint8List(totalSize);
      bytes.setAll(0, yBuffer);
      // Swap u and v buffers since that's what OpenCV's NV21 conversion expects.
      bytes.setAll(yBuffer.lengthInBytes, vBuffer);
      bytes.setAll(yBuffer.lengthInBytes + vBuffer.lengthInBytes, uBuffer);
    } else {
      bytes = image.planes.first.bytes;
      bytesPerRow = image.planes.first.bytesPerRow;
    }

    final params = ProcessImageRequestParams(
      bytes: TransferableTypedData.fromList([bytes]),
      width: image.width,
      height: image.height,
      bytesPerRow: bytesPerRow,
      sensorOrientation: sensorOrientation,
      debugImageType: debugImageType,
    );

    final request = Request.fromCamera(RequestType.ProcessVideoImage, params);
    _isProcessing = true;
    // A post-stop queued frame just got submitted — push the drain quiet window
    // out so isDraining stays true while frames keep flowing.
    if (isDraining.value) _armDrainTimer();
    toIsolate?.send(request);
  }

  void dispose() {
    _drainTimer?.cancel();
    isProcessing.dispose();
    isDraining.dispose();
    final request = Request.death();
    fromIsolate.sendPort.send(request);
    fromIsolate.close();

    _isolate?.kill(priority: Isolate.immediate);

    streamResultController.close();
  }
}
