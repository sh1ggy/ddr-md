// Pure Objective-C interface (no C++ leakage) so it can be imported from the
// Swift plugin shell without pulling OpenCV/Tesseract headers into the module
// map. The implementation lives in CameraOcrSession.mm and is Objective-C++.
#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

// Owns the AVCaptureSession, the resident DdrocrInstance, the preview
// FlutterTexture, and the method/event channels that replace the Dart `camera`
// plugin + per-frame FFI marshalling.
@interface CameraOcrSession : NSObject
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
@end

NS_ASSUME_NONNULL_END
