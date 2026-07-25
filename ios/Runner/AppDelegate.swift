import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The chart-preview assist tick plays through SoLoud (miniaudio), whose iOS
    // default session category is PlayAndRecord — that routes to the quiet
    // earpiece and is silenced by the ring/silent switch, so on a real device
    // the tick was inaudible. Force a Playback session (ignores the mute switch,
    // routes to the speaker) and activate it before any audio engine inits.
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default)
    try? session.setActive(true)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
