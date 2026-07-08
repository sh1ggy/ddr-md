// Objective-C++ implementation of the native camera + OCR pipeline for iOS.
//
// Replaces the Flutter `camera` plugin: an AVCaptureSession feeds full-res BGRA
// frames straight into the existing C++ DdrocrInstance::process_image with no
// Dart round-trip. Preview is served to Flutter through a FlutterTexture.
//
// Control + result delivery are FFI, not channels: the platform channel exists
// only to mint the texture and hand Dart an opaque session pointer (the texture
// registry is Obj-C-only). start/stop/setDebug are extern "C" entry points, and
// each processed frame is pushed to Dart via the registered CameraResultFn
// (an FFI NativeCallable) — see camera_result.h and ocr_processor.dart.

#import "CameraOcrSession.h"
#import <AVFoundation/AVFoundation.h>

// UIKit/Foundation define YES/NO macros that collide with OpenCV enum members.
#ifdef NO
#define APPLE_NO_DEFINED
#undef NO
#endif
#ifdef YES
#define APPLE_YES_DEFINED
#undef YES
#endif

#include <opencv2/opencv.hpp>
#include "ddrocr_instance.h"
#include "config_marshal.h"
#include "camera_result.h"

#ifdef APPLE_NO_DEFINED
#define NO (BOOL)0
#endif
#ifdef APPLE_YES_DEFINED
#define YES (BOOL)1
#endif

#include <atomic>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

extern void platform_log(const char *fmt, ...);

// Matches the Dart-side frame skip: process roughly one of every N frames.
static const int kFrameThreshold = 3;

// Depth of the detector->consumer LIFO stack. See _jobStack.
static const size_t kJobStackDepth = 5;

@interface CameraOcrSession () <AVCaptureVideoDataOutputSampleBufferDelegate,
                                FlutterTexture>
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
// FFI entry points (called from the extern "C" shims at file scope).
- (void)setResultFn:(CameraResultFn)fn;
- (BOOL)startCamera:(BOOL)debug;
- (void)stopCamera;
- (void)setDebugEnabled:(BOOL)enabled;
- (void)setSide:(int)side;
@end

@implementation CameraOcrSession {
  __weak NSObject<FlutterTextureRegistry> *_textures;
  int64_t _textureId;

  AVCaptureSession *_session;
  AVCaptureVideoDataOutput *_videoOutput;
  dispatch_queue_t _captureQueue; // delegate callback queue
  dispatch_queue_t _ocrQueue;     // serial detector worker (cheap Details detect)
  dispatch_queue_t _recQueue;     // serial consumer worker (expensive OCR)

  // FFI result sink (NativeCallable) the OCR worker invokes per frame.
  CameraResultFn _resultFn;

  // Latest preview frame handed to Flutter via copyPixelBuffer. Guarded by
  // _previewLock; retained while stored.
  CVPixelBufferRef _latestPreview;
  NSLock *_previewLock;

  // Resident OCR instance (created in `initialize`, destroyed in `dispose`).
  DdrocrInstance *_instance;
  std::string _dataPath;

  // Backpressure: only one frame in the detector at a time; skip the rest.
  std::atomic<bool> _ocrBusy;
  int _frameCounter;

  // Detector -> consumer hand-off: bounded LIFO stack (depth kJobStackDepth).
  // Detector pushes matched detections on the back; consumer pops the back
  // (newest first). Older frames are still recognised (they feed the Dart-side
  // aggregator) until the stack overflows, when the oldest (front) is evicted.
  // std::deque (not std::stack) so we can drop from the front. Guarded by
  // _jobMutex.
  std::deque<DetailsDetectResult> _jobStack;
  std::mutex _jobMutex;

  BOOL _debug;
  BOOL _running;
  // Selected DetectionSide ordinal; defaults to FIRST (0). Set from Dart.
  std::atomic<int> _side;

  int _previewWidth;
  int _previewHeight;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  CameraOcrSession *session = [[CameraOcrSession alloc] initWithRegistrar:registrar];
  // Retain for the lifetime of the engine by associating with the registrar's
  // messenger via the method-call delegate closure below.
  FlutterMethodChannel *methodChannel =
      [FlutterMethodChannel methodChannelWithName:@"native_opencv/camera_ocr"
                                  binaryMessenger:[registrar messenger]];
  [methodChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [session handleMethodCall:call result:result];
  }];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  self = [super init];
  if (self) {
    _textures = [registrar textures];
    _previewLock = [[NSLock alloc] init];
    _captureQueue = dispatch_queue_create("ddr.camera.capture", DISPATCH_QUEUE_SERIAL);
    _ocrQueue = dispatch_queue_create("ddr.camera.ocr", DISPATCH_QUEUE_SERIAL);
    _recQueue = dispatch_queue_create("ddr.camera.rec", DISPATCH_QUEUE_SERIAL);
    _ocrBusy = false;
    _frameCounter = 0;
    _debug = NO;
    _running = NO;
    _textureId = -1;
    _instance = nullptr;
    _latestPreview = NULL;
    _resultFn = nullptr;
  }
  return self;
}

#pragma mark - Method channel

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *method = call.method;
  // The channel only mints the texture + session pointer and tears it down.
  // start/stop/setDebug/results are all FFI (see the extern "C" shims below).
  if ([method isEqualToString:@"initialize"]) {
    NSDictionary *args = call.arguments;
    NSString *dataPath = args[@"dataPath"];
    [self initializeWithDataPath:dataPath
                         cfgInts:args[@"cfgInts"]
                      cfgDoubles:args[@"cfgDoubles"]
                          result:result];
  } else if ([method isEqualToString:@"dispose"]) {
    [self disposeSession];
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)initializeWithDataPath:(NSString *)dataPath
                       cfgInts:(FlutterStandardTypedData *)cfgInts
                    cfgDoubles:(FlutterStandardTypedData *)cfgDoubles
                        result:(FlutterResult)result {
  _dataPath = std::string(dataPath.UTF8String ?: "");

  // Resident OCR instance — created once, reused across start/stop. Built from
  // the calibration arrays Dart sends (lib/ocr_config.dart), not C++ defaults.
  if (_instance == nullptr) {
    const int32_t *ints =
        cfgInts ? (const int32_t *)cfgInts.data.bytes : nullptr;
    int ni = cfgInts ? (int)(cfgInts.data.length / sizeof(int32_t)) : 0;
    const double *doubles =
        cfgDoubles ? (const double *)cfgDoubles.data.bytes : nullptr;
    int nd = cfgDoubles ? (int)(cfgDoubles.data.length / sizeof(double)) : 0;
    COCRConfig cfg = BuildCOCRConfigFromArrays(ints, ni, doubles, nd);
    _instance = new DdrocrInstance(_dataPath, cfg);
  }

  // Prompt for camera permission now (the FFI camera_start is synchronous and
  // can't host an async prompt). The texture/session are still returned if
  // denied; camera_start just reports failure.
  void (^finishInit)(void) = ^{
    if (![self configureSession]) {
      result([FlutterError errorWithCode:@"camera_init_failed"
                                 message:@"Could not configure AVCaptureSession"
                                 details:nil]);
      return;
    }
    if (self->_textureId < 0) {
      self->_textureId = [self->_textures registerTexture:self];
    }
    result(@{
      @"textureId" : @(self->_textureId),
      @"previewWidth" : @(self->_previewWidth),
      @"previewHeight" : @(self->_previewHeight),
      // iOS forces the capture connection to portrait (see configureSession),
      // so frames arrive upright — Dart must not rotate them again.
      @"sensorOrientation" : @(0),
      // Opaque session pointer Dart uses for the FFI camera_* calls. The session
      // is retained by the method-channel handler block for the engine lifetime.
      @"sessionPtr" : @((int64_t)(intptr_t)self),
    });
  };

  AVAuthorizationStatus status =
      [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status == AVAuthorizationStatusNotDetermined) {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                             completionHandler:^(BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), finishInit);
    }];
  } else {
    finishInit();
  }
}

- (BOOL)configureSession {
  if (_session != nil) return YES;

  AVCaptureDevice *device =
      [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  if (device == nil) {
    platform_log("[ios-cam] no video device\n");
    return NO;
  }

  NSError *error = nil;
  AVCaptureDeviceInput *input =
      [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
  if (input == nil) {
    platform_log("[ios-cam] device input error: %s\n",
                 error.localizedDescription.UTF8String);
    return NO;
  }

  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  // Full-resolution frames — the OCR ROI calibration assumes the high-res
  // sensor image the old `camera` plugin's ResolutionPreset.max produced.
  if ([session canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
    session.sessionPreset = AVCaptureSessionPresetPhoto;
  }

  if ([session canAddInput:input]) {
    [session addInput:input];
  } else {
    return NO;
  }

  AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
  output.videoSettings = @{
    (NSString *)kCVPixelBufferPixelFormatTypeKey :
        @(kCVPixelFormatType_32BGRA)
  };
  output.alwaysDiscardsLateVideoFrames = YES;
  [output setSampleBufferDelegate:self queue:_captureQueue];

  if ([session canAddOutput:output]) {
    [session addOutput:output];
  } else {
    return NO;
  }

  // Force portrait so both the preview texture and the OCR buffer arrive
  // upright (taller than wide), matching what the existing C++ pipeline and
  // ROI coordinates expect on iOS (no in-pipeline rotation).
  AVCaptureConnection *connection =
      [output connectionWithMediaType:AVMediaTypeVideo];
  if (connection.isVideoOrientationSupported) {
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
  }

  _session = session;
  _videoOutput = output;

  // Estimate preview dimensions from the active format (native landscape),
  // swapped to portrait to match the forced orientation above.
  CMVideoDimensions dims =
      CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription);
  _previewWidth = dims.height;  // portrait swap
  _previewHeight = dims.width;
  return YES;
}

#pragma mark - FFI-facing control

- (void)setResultFn:(CameraResultFn)fn {
  _resultFn = fn;
}

- (void)setDebugEnabled:(BOOL)enabled {
  _debug = enabled;
}

- (void)setSide:(int)side {
  _side = side;
}

// Synchronous (FFI). Returns NO if the session isn't configured or camera
// permission isn't granted (permission is requested during initialize).
- (BOOL)startCamera:(BOOL)debug {
  if (_session == nil) return NO;
  if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] !=
      AVAuthorizationStatusAuthorized) {
    return NO;
  }
  _debug = debug;
  if (_running) return YES;
  // Pick up a details template written/updated after session creation (the
  // Dart side re-copies assets on every init, incl. hot restart, but this
  // session object outlives that).
  _instance->reloadDetailsTemplate();
  _frameCounter = 0;
  _ocrBusy = false;
  _running = YES;
  // startRunning blocks; run it off the calling thread.
  dispatch_async(_captureQueue, ^{
    [self->_session startRunning];
  });
  return YES;
}

// Synchronous (FFI). Blocks until the capture session has stopped and any
// in-flight OCR frame has drained, so the result is settled on return.
- (void)stopCamera {
  if (!_running && (_session == nil || !_session.isRunning)) return;
  _running = NO;
  dispatch_sync(_captureQueue, ^{
    if (self->_session.isRunning) {
      [self->_session stopRunning];
    }
  });
  // Drain the detector queue (serial) so any in-flight frame completes and any
  // matched job has been pushed onto the stack.
  dispatch_sync(_ocrQueue, ^{
  });
  // Abandon all queued OCR work: clear the stack BEFORE draining _recQueue so
  // the consumer's drain loop sees it empty and bails out instead of grinding
  // through the whole backlog of stale frames. At most the one OCR already
  // in-flight finishes (OpenCV can't be interrupted mid-call).
  {
    std::lock_guard<std::mutex> lk(_jobMutex);
    _jobStack.clear();
  }
  // Wait for that at-most-one in-flight OCR to settle.
  dispatch_sync(_recQueue, ^{
  });
}

- (void)disposeSession {
  _running = NO;
  if (_session.isRunning) {
    [_session stopRunning];
  }
  _session = nil;
  _videoOutput = nil;

  [_previewLock lock];
  if (_latestPreview) {
    CVPixelBufferRelease(_latestPreview);
    _latestPreview = NULL;
  }
  [_previewLock unlock];

  if (_textureId >= 0) {
    [_textures unregisterTexture:_textureId];
    _textureId = -1;
  }
  if (_instance) {
    delete _instance;
    _instance = nullptr;
  }
}

#pragma mark - FlutterTexture

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  [_previewLock lock];
  CVPixelBufferRef buffer = _latestPreview;
  if (buffer) {
    CVPixelBufferRetain(buffer);
  }
  [_previewLock unlock];
  return buffer;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (pixelBuffer == NULL) return;

  // Update preview (every frame) — retain the new buffer, release the old.
  CVPixelBufferRetain(pixelBuffer);
  [_previewLock lock];
  CVPixelBufferRef old = _latestPreview;
  _latestPreview = pixelBuffer;
  [_previewLock unlock];
  if (old) CVPixelBufferRelease(old);
  if (_textureId >= 0) {
    [_textures textureFrameAvailable:_textureId];
  }

  if (!_running) return;

  // Frame-skip + drop-when-busy backpressure.
  _frameCounter++;
  if (_frameCounter % kFrameThreshold != 0) return;
  bool expected = false;
  if (!_ocrBusy.compare_exchange_strong(expected, true)) {
    return; // OCR worker still busy; drop this frame.
  }

  // Retain for the async OCR hop; released when processing completes.
  CVPixelBufferRetain(pixelBuffer);
  BOOL debug = _debug;
  dispatch_async(_ocrQueue, ^{
    [self runOcrOnBuffer:pixelBuffer debug:debug];
    CVPixelBufferRelease(pixelBuffer);
    self->_ocrBusy = false;
  });
}

- (void)runOcrOnBuffer:(CVPixelBufferRef)pixelBuffer debug:(BOOL)debug {
  if (_instance == nullptr) return;

  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
  size_t width = CVPixelBufferGetWidth(pixelBuffer);
  size_t height = CVPixelBufferGetHeight(pixelBuffer);
  size_t stride = CVPixelBufferGetBytesPerRow(pixelBuffer);
  void *base = CVPixelBufferGetBaseAddress(pixelBuffer);

  cv::Mat bgr;
  {
    // Wrap the locked BGRA buffer (honouring row padding) and convert to BGR.
    cv::Mat bgra((int)height, (int)width, CV_8UC4, base, stride);
    cv::cvtColor(bgra, bgr, cv::COLOR_BGRA2BGR);
  }
  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  if (bgr.empty()) return;

  DebugImageType debugType = debug ? DebugImageType::ON : DebugImageType::NONE;

  // Phase 1 only: cheap Details detection. Keeps this (detector) queue fast so
  // the overlay tracks at the throttled frame rate.
  DetailsDetectResult det;
  try {
    det = _instance->detect_details(
        bgr, static_cast<DetectionSide>(_side.load()), debugType);
  } catch (cv::Exception &e) {
    platform_log("[ios-cam] detect_details exception: %s\n", e.what());
    return;
  }

  // Overlay result every frame (ROIs + detailsRoiIndex, no OCR strings). Dart's
  // listener updates the overlay and only feeds the aggregator on full results.
  if (_resultFn) {
    CCameraResult *out = BuildCCameraResult(det.result, bgr.cols, bgr.rows);
    _resultFn(out);
  }

  // On a match, push onto the LIFO stack and kick the consumer queue. The
  // serial _recQueue means at most one OCR runs at a time; the stack absorbs
  // the rest (newest-first, oldest evicted past kJobStackDepth).
  if (det.matched) {
    {
      std::lock_guard<std::mutex> lk(_jobMutex);
      _jobStack.push_back(std::move(det));
      while (_jobStack.size() > kJobStackDepth)
        _jobStack.pop_front(); // evict oldest on overflow
    }
    dispatch_async(_recQueue, ^{
      [self drainRecQueue];
    });
  }
}

// Consumer: pop the newest queued job (LIFO) and run the expensive OCR, then
// drain the rest newest-to-oldest. Runs on the serial _recQueue.
- (void)drainRecQueue {
  while (true) {
    DetailsDetectResult job;
    {
      std::lock_guard<std::mutex> lk(_jobMutex);
      if (_jobStack.empty()) return;
      job = std::move(_jobStack.back()); // newest first
      _jobStack.pop_back();
    }

    const int w = job.inputImg.cols;
    const int h = job.inputImg.rows;
    ProcessImgResult res;
    try {
      res = _instance->recognise_details(job);
    } catch (cv::Exception &e) {
      platform_log("[ios-cam] recognise_details exception: %s\n", e.what());
      continue;
    }

    if (_resultFn) {
      CCameraResult *out = BuildCCameraResult(res, w, h);
      _resultFn(out);
    }
  }
}

@end

#pragma mark - FFI entry points

// extern "C" so Dart (DynamicLibrary.process) can dlsym these. The used +
// default-visibility attributes keep the linker from dead-stripping them (they
// have no compile-time callers). Each takes the opaque session pointer Dart
// received from the `initialize` channel call.
#define FFI_EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))

FFI_EXPORT void camera_register_callback(void *session, CameraResultFn cb) {
  if (session) [(__bridge CameraOcrSession *)session setResultFn:cb];
}

FFI_EXPORT int32_t camera_start(void *session, int32_t debug) {
  if (!session) return 0;
  return [(__bridge CameraOcrSession *)session startCamera:(debug != 0)] ? 1 : 0;
}

FFI_EXPORT void camera_stop(void *session) {
  if (session) [(__bridge CameraOcrSession *)session stopCamera];
}

FFI_EXPORT void camera_set_side(void *session, int32_t side) {
  if (session) [(__bridge CameraOcrSession *)session setSide:side];
}

FFI_EXPORT void camera_set_debug(void *session, int32_t enabled) {
  if (session) [(__bridge CameraOcrSession *)session setDebugEnabled:(enabled != 0)];
}

FFI_EXPORT void camera_free_result(void *result) {
  FreeCCameraResult((CCameraResult *)result);
}
