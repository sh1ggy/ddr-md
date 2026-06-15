// Objective-C++ implementation of the native camera + OCR pipeline for iOS.
//
// Replaces the Flutter `camera` plugin: an AVCaptureSession feeds full-res BGRA
// frames straight into the existing C++ DdrocrInstance::process_image with no
// Dart round-trip. Preview is served to Flutter through a FlutterTexture; OCR
// results are pushed over an EventChannel as a StandardMessageCodec map that
// ocr_processor.dart decodes (see ProcessResult.fromEvent).

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

#ifdef APPLE_NO_DEFINED
#define NO (BOOL)0
#endif
#ifdef APPLE_YES_DEFINED
#define YES (BOOL)1
#endif

#include <atomic>
#include <string>
#include <vector>

extern void platform_log(const char *fmt, ...);

// Matches the Dart-side frame skip: process roughly one of every N frames.
static const int kFrameThreshold = 3;

// Encodes a Mat (e.g. ".png"/".jpg") into NSData; nil when the Mat is empty.
static NSData *EncodeMat(const cv::Mat &img, const char *ext) {
  if (img.empty()) return nil;
  std::vector<uchar> buf;
  if (!cv::imencode(ext, img, buf) || buf.empty()) return nil;
  return [NSData dataWithBytes:buf.data() length:buf.size()];
}

@interface CameraOcrSession () <AVCaptureVideoDataOutputSampleBufferDelegate,
                                FlutterTexture,
                                FlutterStreamHandler>
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
@end

@implementation CameraOcrSession {
  __weak NSObject<FlutterTextureRegistry> *_textures;
  int64_t _textureId;

  AVCaptureSession *_session;
  AVCaptureVideoDataOutput *_videoOutput;
  dispatch_queue_t _captureQueue; // delegate callback queue
  dispatch_queue_t _ocrQueue;     // serial OCR worker

  FlutterEventSink _eventSink;

  // Latest preview frame handed to Flutter via copyPixelBuffer. Guarded by
  // _previewLock; retained while stored.
  CVPixelBufferRef _latestPreview;
  NSLock *_previewLock;

  // Resident OCR instance (created in `initialize`, destroyed in `dispose`).
  DdrocrInstance *_instance;
  std::string _dataPath;

  // Backpressure: only one frame in OCR at a time; skip the rest.
  std::atomic<bool> _ocrBusy;
  int _frameCounter;

  BOOL _debug;
  BOOL _running;

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

  FlutterEventChannel *eventChannel =
      [FlutterEventChannel eventChannelWithName:@"native_opencv/camera_ocr/events"
                                binaryMessenger:[registrar messenger]];
  [eventChannel setStreamHandler:session];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  self = [super init];
  if (self) {
    _textures = [registrar textures];
    _previewLock = [[NSLock alloc] init];
    _captureQueue = dispatch_queue_create("ddr.camera.capture", DISPATCH_QUEUE_SERIAL);
    _ocrQueue = dispatch_queue_create("ddr.camera.ocr", DISPATCH_QUEUE_SERIAL);
    _ocrBusy = false;
    _frameCounter = 0;
    _debug = NO;
    _running = NO;
    _textureId = -1;
    _instance = nullptr;
    _latestPreview = NULL;
  }
  return self;
}

#pragma mark - Method channel

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *method = call.method;
  if ([method isEqualToString:@"initialize"]) {
    NSDictionary *args = call.arguments;
    NSString *dataPath = args[@"dataPath"];
    [self initializeWithDataPath:dataPath
                         cfgInts:args[@"cfgInts"]
                      cfgDoubles:args[@"cfgDoubles"]
                          result:result];
  } else if ([method isEqualToString:@"start"]) {
    NSNumber *debug = call.arguments[@"debug"];
    _debug = [debug boolValue];
    [self start:result];
  } else if ([method isEqualToString:@"stop"]) {
    [self stop:result];
  } else if ([method isEqualToString:@"setDebug"]) {
    _debug = [call.arguments[@"enabled"] boolValue];
    result(nil);
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

  if (![self configureSession]) {
    result([FlutterError errorWithCode:@"camera_init_failed"
                               message:@"Could not configure AVCaptureSession"
                               details:nil]);
    return;
  }

  if (_textureId < 0) {
    _textureId = [_textures registerTexture:self];
  }

  result(@{
    @"textureId" : @(_textureId),
    @"previewWidth" : @(_previewWidth),
    @"previewHeight" : @(_previewHeight),
  });
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

- (void)start:(FlutterResult)result {
  if (_session == nil) {
    result([FlutterError errorWithCode:@"not_initialized"
                               message:@"initialize must be called first"
                               details:nil]);
    return;
  }
  // Request camera permission before the first run.
  AVAuthorizationStatus status =
      [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status == AVAuthorizationStatusNotDetermined) {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                             completionHandler:^(BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (granted) {
          [self beginRunning];
          result(nil);
        } else {
          result([FlutterError errorWithCode:@"permission_denied"
                                     message:@"Camera permission denied"
                                     details:nil]);
        }
      });
    }];
    return;
  }
  if (status != AVAuthorizationStatusAuthorized) {
    result([FlutterError errorWithCode:@"permission_denied"
                               message:@"Camera permission denied"
                               details:nil]);
    return;
  }
  [self beginRunning];
  result(nil);
}

- (void)beginRunning {
  if (_running) return;
  _frameCounter = 0;
  _ocrBusy = false;
  _running = YES;
  // startRunning blocks; run it off the main thread.
  dispatch_async(_captureQueue, ^{
    [self->_session startRunning];
  });
}

- (void)stop:(FlutterResult)result {
  _running = NO;
  dispatch_async(_captureQueue, ^{
    if (self->_session.isRunning) {
      [self->_session stopRunning];
    }
    // Drain: wait for any in-flight OCR to finish so the Dart side's
    // "Finalising…" indicator reflects reality.
    dispatch_async(self->_ocrQueue, ^{
      dispatch_async(dispatch_get_main_queue(), ^{
        result(nil);
      });
    });
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

#pragma mark - FlutterStreamHandler

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  _eventSink = events;
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  _eventSink = nil;
  return nil;
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
  ProcessImgResult res;
  try {
    res = _instance->process_image(bgr, DetectionSide::FIRST, debugType);
  } catch (cv::Exception &e) {
    platform_log("[ios-cam] OCR exception: %s\n", e.what());
    return;
  }

  [self emitResult:res frameWidth:bgr.cols frameHeight:bgr.rows];
}

#pragma mark - Result marshalling

- (void)emitResult:(const ProcessImgResult &)res
        frameWidth:(int)frameWidth
       frameHeight:(int)frameHeight {
  // Flatten ROIs into an Int32 typed array {x,y,w,h} * N.
  NSMutableData *rois =
      [NSMutableData dataWithLength:res.rois.size() * 4 * sizeof(int32_t)];
  int32_t *roiPtr = (int32_t *)rois.mutableBytes;
  for (size_t i = 0; i < res.rois.size(); i++) {
    roiPtr[i * 4 + 0] = res.rois[i].x;
    roiPtr[i * 4 + 1] = res.rois[i].y;
    roiPtr[i * 4 + 2] = res.rois[i].width;
    roiPtr[i * 4 + 3] = res.rois[i].height;
  }

  const auto &ocr = res.ocrResults;
  NSDictionary *ocrMap = @{
    @"score" : [NSString stringWithUTF8String:ocr.score.text.c_str()],
    @"marvelous" : [NSString stringWithUTF8String:ocr.marvelous.text.c_str()],
    @"perfect" : [NSString stringWithUTF8String:ocr.perfect.text.c_str()],
    @"great" : [NSString stringWithUTF8String:ocr.great.text.c_str()],
    @"good" : [NSString stringWithUTF8String:ocr.good.text.c_str()],
    @"miss" : [NSString stringWithUTF8String:ocr.miss.text.c_str()],
  };

  NSMutableDictionary *payload = [@{
    @"isDetected" : @(res.isDetected != 0),
    @"detailsRoiIndex" : @(res.detailsRoiIndex),
    @"width" : @(frameWidth),
    @"height" : @(frameHeight),
    @"rois" : [FlutterStandardTypedData typedDataWithInt32:rois],
    @"ocr" : ocrMap,
  } mutableCopy];

  NSData *mask = EncodeMat(res.debugMask, ".png");
  if (mask) payload[@"mask"] = [FlutterStandardTypedData typedDataWithBytes:mask];
  NSData *crop = EncodeMat(res.debugDetailsCrop, ".png");
  if (crop) payload[@"crop"] = [FlutterStandardTypedData typedDataWithBytes:crop];
  NSData *capture = EncodeMat(res.colorCapture, ".jpg");
  if (capture)
    payload[@"capture"] = [FlutterStandardTypedData typedDataWithBytes:capture];

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_eventSink) {
      self->_eventSink(payload);
    }
  });
}

@end
