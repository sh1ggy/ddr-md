#import <Flutter/Flutter.h>
// Exposed through the public umbrella header so the Swift plugin shell can see
// the Objective-C++ camera session. CameraOcrSession.h is pure Objective-C
// (no C++), so importing it here doesn't pull C++ into the module map.
#import "CameraOcrSession.h"

@interface NativeOpencvPlugin : NSObject<FlutterPlugin>
@end
