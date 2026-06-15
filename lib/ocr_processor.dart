import 'dart:async';
import 'dart:ffi';
import 'ocr_config.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:image_picker/image_picker.dart';
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
  // Crop the recogniser matched on, present only when this frame matched
  // "Details". The UI persists the last non-null one across failed frames.
  final Uint8List? debugDetailsCropBytes;
  // Full-color JPEG of the frame, present only when this frame matched
  // "Details" (independent of the debug toggle). The stopped view paints the
  // static ROIs over the last non-null one.
  final Uint8List? captureBytes;
  final int? detailsRoiIndex;
  final Map<String, String> ocrStrings;
  // Dimensions of the processed frame (the pixel space the ROIs are expressed
  // in). The camera path reports these so the UI can scale the ROI overlay to
  // the on-screen preview; the picked-image path leaves them at 0.
  final int frameWidth;
  final int frameHeight;

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
    this.ocrStrings, {
    this.frameWidth = 0,
    this.frameHeight = 0,
  });

  // Decodes a map an EventChannel frame from the native camera/OCR session
  // delivers. Keys are produced by the iOS/Android shims (see
  // CameraOcrSession / CameraOcrPlugin). Image fields are absent (null) when
  // not emitted for that frame.
  factory ProcessResult.fromEvent(Map<dynamic, dynamic> e) {
    final roisFlat = (e['rois'] as Int32List?) ?? Int32List(0);
    final detectedRois = <Rectangle<int>>[];
    for (int i = 0; i + 3 < roisFlat.length; i += 4) {
      detectedRois.add(Rectangle<int>(
          roisFlat[i], roisFlat[i + 1], roisFlat[i + 2], roisFlat[i + 3]));
    }

    final ocr = <String, String>{};
    final rawOcr = e['ocr'] as Map<dynamic, dynamic>?;
    if (rawOcr != null) {
      rawOcr.forEach((k, v) => ocr['$k'] = '$v');
    }

    final maskBytes = e['mask'] as Uint8List?;
    final cropBytes = e['crop'] as Uint8List?;
    final captureBytes = e['capture'] as Uint8List?;
    final imageType = (maskBytes != null || cropBytes != null)
        ? ReturnImageType.BytesImage
        : ReturnImageType.None;

    final isDetected = (e['isDetected'] as bool?) ?? false;

    return ProcessResult(
      isDetected ? DifficultyType.FFXI : DifficultyType.None,
      null,
      detectedRois,
      isDetected,
      imageType,
      maskBytes,
      cropBytes,
      captureBytes,
      (e['detailsRoiIndex'] as int?) ?? -1,
      ocr,
      frameWidth: (e['width'] as int?) ?? 0,
      frameHeight: (e['height'] as int?) ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// FFI: retained ONLY for the picked-image (gallery import) path. The live
// camera path now runs entirely native-side and surfaces results over an
// EventChannel — no per-frame FFI / isolate marshalling.
// ---------------------------------------------------------------------------

final DynamicLibrary _nativeLib = _openDynamicLibrary();

DynamicLibrary _openDynamicLibrary() {
  return Platform.isAndroid
      ? DynamicLibrary.open("libnative_opencv.so")
      : DynamicLibrary.process();
}

// Layout must match the C COCRConfig struct exactly.
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

typedef _c_createOcrInstance = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<COCRConfig>);
typedef _dart_createOcrInstance = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<COCRConfig>);

typedef _c_destroyOcrInstance = Void Function(Pointer<Void>);
typedef _dart_destroyOcrInstance = void Function(Pointer<Void>);

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

// C allocates each field with malloc; _freeOcrStrings releases them.
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

// Runs the picked-image FFI path inside a one-shot isolate so the (slow)
// instance creation + OCR doesn't jank the UI thread. Creates and destroys a
// transient DdrocrInstance for the single call.
ProcessResult _runPickedImage(String appPath, String imagePath) {
  final createFn =
      _nativeLib.lookupFunction<_c_createOcrInstance, _dart_createOcrInstance>(
          'create_ocr_instance');
  final destroyFn = _nativeLib
      .lookupFunction<_c_destroyOcrInstance, _dart_destroyOcrInstance>(
          'destroy_ocr_instance');
  final processFn = _nativeLib
      .lookupFunction<_c_processPickedImage, _dart_processPickedImage>(
          'process_picked_image');

  final dataPathPtr = appPath.toNativeUtf8();
  final cfg = _buildOCRConfig();
  final handle = createFn(dataPathPtr, cfg);
  calloc.free(dataPathPtr);
  calloc.free(cfg);

  final outputIsDetected = calloc<Int32>();
  final outputRoisCount = calloc<Int32>();
  final outputRoisPtr = calloc<Pointer<Int32>>();
  final outputDetailsRoiIndex = calloc<Int32>();
  final outStrings = calloc<COCRStrings>();

  final imagePathPtr = imagePath.toNativeUtf8();
  processFn(
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

  final outputRois = outputRoisPtr.value;
  final detectedRois = <Rectangle<int>>[];
  if (outputRois != nullptr) {
    for (int i = 0; i < outputRoisCount.value; i++) {
      final base = i * 4;
      detectedRois.add(Rectangle<int>(outputRois[base], outputRois[base + 1],
          outputRois[base + 2], outputRois[base + 3]));
    }
  }

  final result = ProcessResult(
    outputRois == nullptr ? DifficultyType.None : DifficultyType.FFXI,
    null,
    detectedRois,
    outputIsDetected.value != 0,
    ReturnImageType.None,
    null,
    null,
    null,
    outputDetailsRoiIndex.value,
    outputRois == nullptr ? {} : _readOcrStrings(outStrings),
  );

  if (outputRois != nullptr) calloc.free(outputRois);
  calloc.free(outputRoisPtr);
  calloc.free(outputIsDetected);
  calloc.free(outputRoisCount);
  calloc.free(outputDetailsRoiIndex);
  _freeOcrStrings(outStrings);
  destroyFn(handle);
  return result;
}

// ---------------------------------------------------------------------------
// OCRProcessor — drives the native camera+OCR session over platform channels.
// The actor now only does start/stop/dispose; per-frame results arrive on an
// EventChannel and are republished on [streamResultController] exactly as
// before. The picked-image path stays on FFI (run in a one-shot isolate).
// ---------------------------------------------------------------------------

class OCRProcessor {
  static const MethodChannel _method =
      MethodChannel('native_opencv/camera_ocr');
  static const EventChannel _events =
      EventChannel('native_opencv/camera_ocr/events');

  Directory? tempDir;
  Directory? appDir;

  // Texture backing the live preview (allocated by the native session in init).
  int? textureId;
  // Preview surface dimensions, used to size the preview's AspectRatio.
  int previewWidth = 0;
  int previewHeight = 0;
  double get previewAspectRatio =>
      (previewWidth > 0 && previewHeight > 0) ? previewWidth / previewHeight : 0;

  final streamResultController = StreamController<ProcessResult>.broadcast();

  final ValueNotifier<bool> isProcessing = ValueNotifier(false);
  final ValueNotifier<bool> isDraining = ValueNotifier(false);

  StreamSubscription? _eventSub;
  DebugImageType _debugImageType = DebugImageType.none;

  DebugImageType get debugImageType => _debugImageType;
  set debugImageType(DebugImageType v) {
    _debugImageType = v;
    _method.invokeMethod('setDebug', {'enabled': v == DebugImageType.on});
  }

  Future<void> init() async {
    tempDir = await getTemporaryDirectory();
    appDir = await getApplicationDocumentsDirectory();
    await loadTessdata();

    // The native camera session only exists on mobile. The picked-image (FFI)
    // path doesn't need it, so a failure here is non-fatal.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      // Native session allocates the preview texture and a resident OCR
      // instance, configured with the SAME calibration as the FFI path
      // (lib/ocr_config.dart) rather than the C++ struct defaults.
      final (cfgInts, cfgDoubles) = _buildCameraConfigArrays();
      final res = await _method.invokeMapMethod<String, dynamic>('initialize', {
        'dataPath': appDir!.path,
        'cfgInts': cfgInts,
        'cfgDoubles': cfgDoubles,
      });
      if (res != null) {
        textureId = res['textureId'] as int?;
        previewWidth = (res['previewWidth'] as int?) ?? 0;
        previewHeight = (res['previewHeight'] as int?) ?? 0;
      }
    } catch (e) {
      print('Native camera session init failed (picked-image still works): $e');
    }
  }

  Future<void> loadTessdata() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // Tessdata copying is only needed for mobile platforms.
      print(
          'Skipping tessdata copy on unsupported platform: ${Platform.operatingSystem}');
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
      final targetFile =
          File(path.join(tessdataDir.path, path.basename(assetPath)));
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

  // Serialises lib/ocr_config.dart into the flat (ints, doubles) arrays the
  // native camera session reconstructs into a COCRConfig. Field order MUST match
  // config_marshal.h::BuildCOCRConfigFromArrays.
  (Int32List, Float64List) _buildCameraConfigArrays() {
    final ints = Int32List(83);
    ints[0] = ocrBorder;
    ints[1] = ocrPsmEng;
    ints[2] = ocrPsmEngJP;
    ints[3] = ocrGaussianBlurSize;
    ints[4] = ocrTophatKernelSize;
    ints[5] = ocrMorphWidth;
    ints[6] = ocrMorphHeight;
    int k = 7;
    for (int r = 0; r < 12; r++) {
      final (rect, (ex, ey)) = ocrRoi[r];
      ints[k++] = rect[roiX1];
      ints[k++] = rect[roiY1];
      ints[k++] = rect[roiX2];
      ints[k++] = rect[roiY2];
      ints[k++] = ex;
      ints[k++] = ey;
    }
    for (int c = 0; c < 4; c++) {
      ints[k++] = ocrCombinedRoi[c];
    }

    final doubles = Float64List(5);
    doubles[0] = ocrSimplificationEpsilon;
    doubles[1] = ocrAreaMinFactor;
    doubles[2] = ocrAreaMaxFactor;
    doubles[3] = ocrResolutionScale;
    doubles[4] = ocrDetailsTemplateMinScore;
    return (ints, doubles);
  }

  bool get isReady => textureId != null;

  // Starts the live camera stream + OCR loop. Subscribes to the result event
  // channel and republishes each frame's result on streamResultController.
  Future<void> start() async {
    _eventSub ??= _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          streamResultController.add(ProcessResult.fromEvent(event));
        }
      },
      onError: (e) => print('camera_ocr event error: $e'),
    );
    isDraining.value = false;
    await _method.invokeMethod('start', {
      'debug': _debugImageType == DebugImageType.on,
    });
    isProcessing.value = true;
  }

  // Stops the camera stream and tears down the native capture session's
  // outputs. Awaitable; isDraining is held until the native side confirms the
  // in-flight frame (if any) has been flushed.
  Future<void> stop() async {
    isProcessing.value = false;
    isDraining.value = true;
    try {
      await _method.invokeMethod('stop');
    } finally {
      isDraining.value = false;
    }
  }

  void processPickedImage(XFile image) async {
    print('Processing image from file: ${image.path}');
    isProcessing.value = true;
    try {
      final appPath = appDir!.path;
      final imagePath = image.path;
      final result =
          await Isolate.run(() => _runPickedImage(appPath, imagePath));
      streamResultController.add(result);
    } catch (e) {
      print('Picked image processing failed: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    isProcessing.dispose();
    isDraining.dispose();
    _method.invokeMethod('dispose');
    streamResultController.close();
  }
}
