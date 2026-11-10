import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let manager = FileManager.default
    BackupExclusions.apply(
      documents: manager.urls(for: .documentDirectory, in: .userDomainMask)[0],
      applicationSupport: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    )

    // The chart-preview assist tick plays through SoLoud (miniaudio), whose iOS
    // default session category is PlayAndRecord — that routes to the quiet
    // earpiece and is silenced by the ring/silent switch, so on a real device
    // the tick was inaudible. Force a Playback session (ignores the mute switch,
    // routes to the speaker) and activate it before any audio engine inits. Mix
    // with others so opening the app doesn't stop the user's music.
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try? session.setActive(true)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SongIdSession") {
      SongIdSession.register(messenger: registrar.messenger())
    }
  }
}

/// Song ID's audio session. In its default mode iOS processes the built-in
/// mic for voice, suppressing sustained tones as noise, which left only a
/// song's drums to match. Measurement mode turns that off; the built-in mic
/// is pinned so a headset's can't take over. Afterwards the Playback session
/// above comes back, so the assist tick keeps the speaker and the mute
/// switch's behaviour.
enum SongIdSession {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ddr_md/song_id_session", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let session = AVAudioSession.sharedInstance()
      do {
        switch call.method {
        case "listen":
          try session.setCategory(
            .playAndRecord, mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
          try session.setPreferredSampleRate(48000)
          try session.setActive(true)
          if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(mic)
          }
          result(nil)
        case "done":
          try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
          try session.setActive(true)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "session", message: error.localizedDescription, details: nil))
      }
    }
  }
}

/// Keep reproducible assets available offline without copying them into device backups.
enum BackupExclusions {
  static func apply(documents: URL, applicationSupport: URL) {
    let directories = [
      applicationSupport.appendingPathComponent("content", isDirectory: true),
      documents.appendingPathComponent("models", isDirectory: true),
      documents.appendingPathComponent("templates", isDirectory: true),
      documents.appendingPathComponent("music", isDirectory: true),
    ]
    for var directory in directories {
      do {
        // Create and mark the parent before Flutter writes any children. Reapplying
        // at launch also covers existing downloads after an app update or restore.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
      } catch {
        // A backup-policy failure must not prevent the app from opening.
        NSLog("Could not exclude %@ from backup: %@", directory.path, error.localizedDescription)
      }
    }
  }
}
