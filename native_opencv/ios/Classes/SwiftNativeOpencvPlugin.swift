import Flutter
import UIKit

public class SwiftNativeOpencvPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // The live camera + OCR pipeline is implemented natively in
    // CameraOcrSession (Objective-C++). It wires up the
    // `native_opencv/camera_ocr` method channel, the `.../events` event
    // channel, and the preview FlutterTexture.
    CameraOcrSession.register(with: registrar)
  }
}
