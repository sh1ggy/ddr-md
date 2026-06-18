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
  // Crop the Details template matched on, present only when this frame matched.
  // The UI persists the last non-null one across failed frames.
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

  // Reads a CCameraResult the native OCR worker handed back over the FFI
  // NativeCallable. Copies everything out (the native buffer is freed by the
  // caller right after). Mirrors camera_result.h.
  factory ProcessResult.fromNative(Pointer<CCameraResult> p) {
    final r = p.ref;

    final detectedRois = <Rectangle<int>>[];
    if (r.rois != nullptr) {
      for (int i = 0; i < r.roisCount; i++) {
        final b = i * 4;
        detectedRois.add(Rectangle<int>(
            r.rois[b], r.rois[b + 1], r.rois[b + 2], r.rois[b + 3]));
      }
    }

    String rd(Pointer<Char> s) =>
        s == nullptr ? '' : s.cast<Utf8>().toDartString();
    final ocr = {
      'score': rd(r.score),
      'marvelous': rd(r.marvelous),
      'perfect': rd(r.perfect),
      'great': rd(r.great),
      'good': rd(r.good),
      'miss': rd(r.miss),
    };

    Uint8List? img(Pointer<Uint8> buf, int len) =>
        (buf != nullptr && len > 0) ? Uint8List.fromList(buf.asTypedList(len)) : null;
    final mask = img(r.mask, r.maskLen);
    final crop = img(r.crop, r.cropLen);
    final capture = img(r.capture, r.captureLen);
    final imageType = (mask != null || crop != null)
        ? ReturnImageType.BytesImage
        : ReturnImageType.None;

    final isDetected = r.isDetected != 0;
    return ProcessResult(
      isDetected ? DifficultyType.FFXI : DifficultyType.None,
      null,
      detectedRois,
      isDetected,
      imageType,
      mask,
      crop,
      capture,
      r.detailsRoiIndex,
      ocr,
      frameWidth: r.width,
      frameHeight: r.height,
    );
  }
}

// ---------------------------------------------------------------------------
// FFI bindings. The live camera path is driven entirely native-side; Dart only
// (1) gets a texture id + an opaque native session pointer over a thin platform
// channel (the Flutter texture registry is platform-only), then (2) talks to
// the C++ session directly over FFI — start/stop and per-frame result delivery
// (via a NativeCallable) never touch a method/event channel or JNI.
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
  @Array(4)
  external Array<Int32> combinedRoi;
  @Double()
  external double detailsTemplateMinScore;
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

// Layout must match camera_result.h::CCameraResult exactly.
final class CCameraResult extends Struct {
  @Int32()
  external int isDetected;
  @Int32()
  external int detailsRoiIndex;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int roisCount;
  external Pointer<Int32> rois;
  external Pointer<Char> score;
  external Pointer<Char> marvelous;
  external Pointer<Char> perfect;
  external Pointer<Char> great;
  external Pointer<Char> good;
  external Pointer<Char> miss;
  external Pointer<Uint8> mask;
  @Int32()
  external int maskLen;
  external Pointer<Uint8> crop;
  @Int32()
  external int cropLen;
  external Pointer<Uint8> capture;
  @Int32()
  external int captureLen;
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

// Camera session FFI (operates on the opaque session pointer from the channel).
typedef _ResultCallbackNative = Void Function(Pointer<CCameraResult>);

typedef _c_cameraRegister = Void Function(
    Pointer<Void>, Pointer<NativeFunction<_ResultCallbackNative>>);
typedef _dart_cameraRegister = void Function(
    Pointer<Void>, Pointer<NativeFunction<_ResultCallbackNative>>);

typedef _c_cameraStart = Int32 Function(Pointer<Void>, Int32);
typedef _dart_cameraStart = int Function(Pointer<Void>, int);

typedef _c_cameraVoid = Void Function(Pointer<Void>);
typedef _dart_cameraVoid = void Function(Pointer<Void>);

typedef _c_cameraSetDebug = Void Function(Pointer<Void>, Int32);
typedef _dart_cameraSetDebug = void Function(Pointer<Void>, int);

final _cameraRegisterFn =
    _nativeLib.lookupFunction<_c_cameraRegister, _dart_cameraRegister>(
        'camera_register_callback');
final _cameraStartFn =
    _nativeLib.lookupFunction<_c_cameraStart, _dart_cameraStart>('camera_start');
final _cameraStopFn =
    _nativeLib.lookupFunction<_c_cameraVoid, _dart_cameraVoid>('camera_stop');
final _cameraSetDebugFn =
    _nativeLib.lookupFunction<_c_cameraSetDebug, _dart_cameraSetDebug>(
        'camera_set_debug');
final _cameraFreeResultFn =
    _nativeLib.lookupFunction<_c_cameraVoid, _dart_cameraVoid>(
        'camera_free_result');

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
  for (int c = 0; c < 4; c++) {
    p.ref.combinedRoi[c] = ocrCombinedRoi[c];
  }
  p.ref.detailsTemplateMinScore = ocrDetailsTemplateMinScore;
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
// OCRProcessor — owns the native camera+OCR session. A thin platform channel
// hands back the preview texture id + an opaque session pointer; everything
// after that is FFI: results arrive via a NativeCallable the C++ worker invokes,
// and start/stop/setDebug are direct C calls. The picked-image path also stays
// on FFI (run in a one-shot isolate).
// ---------------------------------------------------------------------------

class OCRProcessor {
  // The channel exists ONLY to mint the Flutter texture (registry is
  // platform-only) and hand back the native session pointer; no results flow
  // through it.
  static const MethodChannel _method =
      MethodChannel('native_opencv/camera_ocr');

  Directory? tempDir;
  Directory? appDir;

  // Opaque pointer to the native CameraOcrSession, supplied by the channel.
  Pointer<Void> _session = nullptr;

  int? textureId;
  // Preview output size in sensor (landscape) orientation, as the camera
  // renders it. Dart rotates it for display via [previewQuarterTurns].
  int previewWidth = 0;
  int previewHeight = 0;
  int sensorOrientation = 90;

  // Quarter-turns to rotate the preview Texture so it displays upright (the
  // camera delivers sensor-landscape frames; this matches the camera package's
  // RotatedBox approach).
  int get previewQuarterTurns => (sensorOrientation ~/ 90) % 4;

  // Aspect ratio of the preview AS DISPLAYED (after rotation).
  double get previewAspectRatio {
    if (previewWidth <= 0 || previewHeight <= 0) return 0;
    final odd = previewQuarterTurns.isOdd;
    return odd ? previewHeight / previewWidth : previewWidth / previewHeight;
  }

  final streamResultController = StreamController<ProcessResult>.broadcast();

  final ValueNotifier<bool> isProcessing = ValueNotifier(false);
  final ValueNotifier<bool> isDraining = ValueNotifier(false);

  // NativeCallable the C++ OCR worker invokes per processed frame.
  NativeCallable<_ResultCallbackNative>? _resultCallable;

  DebugImageType _debugImageType = DebugImageType.none;

  DebugImageType get debugImageType => _debugImageType;
  set debugImageType(DebugImageType v) {
    _debugImageType = v;
    if (_session != nullptr) {
      _cameraSetDebugFn(_session, v == DebugImageType.on ? 1 : 0);
    }
  }

  // Invoked on the main isolate by the NativeCallable.listener. Copies the
  // result out and frees the native buffer.
  void _onNativeResult(Pointer<CCameraResult> p) {
    if (p == nullptr) return;
    try {
      final result = ProcessResult.fromNative(p);
      streamResultController.add(result);
    } finally {
      _cameraFreeResultFn(p.cast());
    }
  }

  Future<void> init() async {
    tempDir = await getTemporaryDirectory();
    appDir = await getApplicationDocumentsDirectory();
    await _loadNativeAssets();

    // The native camera session only exists on mobile. The picked-image (FFI)
    // path doesn't need it, so a failure here is non-fatal.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      // The channel mints the preview texture and the native session, built
      // with the SAME calibration as the FFI path (lib/ocr_config.dart).
      final (cfgInts, cfgDoubles) = _buildCameraConfigArrays();
      final res = await _method.invokeMapMethod<String, dynamic>('initialize', {
        'dataPath': appDir!.path,
        'cfgInts': cfgInts,
        'cfgDoubles': cfgDoubles,
      });
      if (res == null) return;
      textureId = res['textureId'] as int?;
      previewWidth = (res['previewWidth'] as int?) ?? 0;
      previewHeight = (res['previewHeight'] as int?) ?? 0;
      sensorOrientation = (res['sensorOrientation'] as int?) ?? 90;
      final sessionAddr = (res['sessionPtr'] as int?) ?? 0;
      _session = Pointer<Void>.fromAddress(sessionAddr);

      if (_session != nullptr) {
        // Register the FFI result callback up-front; the native worker calls it
        // per processed frame between start() and stop().
        _resultCallable =
            NativeCallable<_ResultCallbackNative>.listener(_onNativeResult);
        _cameraRegisterFn(_session, _resultCallable!.nativeFunction);
      }
    } catch (e) {
      print('Native camera session init failed (picked-image still works): $e');
    }
  }

  Future<void> _loadNativeAssets() async {
    const assets = [
      'assets/templates/details.png',
      'assets/models/ppocr_mobile_det.onnx',
      'assets/models/ppocr_mobile_rec.onnx',
      'assets/models/ppocrv5_dict.txt',
      'assets/models/ppocr_tiny_det.onnx',
      'assets/models/ppocr_tiny_rec.onnx',
      'assets/models/ppocrv6_dict.txt',
    ];
    for (final assetPath in assets) {
      final segments = assetPath.split('/');
      final subdir = Directory(path.join(appDir!.path, segments[1]));
      if (!await subdir.exists()) {
        await subdir.create(recursive: true);
      }
      final target = File(path.join(subdir.path, segments.last));
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      await target.writeAsBytes(bytes, flush: true);
      print('Copied $assetPath -> ${target.path}');
    }
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

  // Starts the live camera stream + OCR loop (direct FFI). Results flow on the
  // NativeCallable registered in init().
  Future<void> start() async {
    if (_session == nullptr) return;
    isDraining.value = false;
    final ok = _cameraStartFn(_session, _debugImageType == DebugImageType.on ? 1 : 0);
    if (ok == 0) {
      throw PlatformException(
          code: 'camera_start_failed', message: 'Could not start camera');
    }
    isProcessing.value = true;
  }

  // Stops the camera stream + OCR worker (direct FFI). camera_stop blocks until
  // any in-flight frame is flushed, so the result is settled when it returns.
  Future<void> stop() async {
    isProcessing.value = false;
    if (_session == nullptr) return;
    isDraining.value = true;
    try {
      _cameraStopFn(_session);
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
    isProcessing.dispose();
    isDraining.dispose();
    // Tear down the native session (channel releases the platform texture and
    // destroys the C++ session) before closing the callback it could invoke.
    if (_session != nullptr) {
      _method.invokeMethod('dispose', {'sessionPtr': _session.address});
      _session = nullptr;
    }
    _resultCallable?.close();
    _resultCallable = null;
    streamResultController.close();
  }
}
