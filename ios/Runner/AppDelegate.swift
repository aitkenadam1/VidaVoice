import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPersonalVoiceChannel(with: engineBridge.applicationRegistrar.messenger())
  }

  /// Lets the Dart side ask iOS for Personal Voice access.
  ///
  /// Apple hides a user's Personal Voice from third-party apps until the
  /// app calls `requestPersonalVoiceAuthorization` (iOS 17+). Without this
  /// channel, flutter_tts would never list it. Channel contract:
  /// method "requestAuthorization" -> one of "authorized", "denied",
  /// "notDetermined", "unsupported", "unknown". Never throws.
  private func registerPersonalVoiceChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "vidavoice/personal_voice",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "requestAuthorization" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 17.0, *) {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
          // FlutterResult must be invoked on the platform thread; Apple does
          // not document which queue this callback runs on.
          DispatchQueue.main.async {
            switch status {
            case .authorized: result("authorized")
            case .denied: result("denied")
            case .notDetermined: result("notDetermined")
            case .unsupported: result("unsupported")
            @unknown default: result("unknown")
            }
          }
        }
      } else {
        result("unsupported")
      }
    }
  }
}
