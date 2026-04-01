import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Fallback: some launch paths never call `didInitializeImplicitFlutterEngine`, or call it before
    // the window/root VC exists — register on the live [FlutterEngine] when the view hierarchy is up.
    scheduleQuickPoseRegistrationFallback()
    return ok
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    QuickPoseFlutterBridge.register(engineBridge: engineBridge)
  }

  private func scheduleQuickPoseRegistrationFallback() {
    let tryRegister = { [weak self] in
      // Scene lifecycle: `AppDelegate.window` is often nil — walk connected scenes.
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for window in windowScene.windows {
          if let root = window.rootViewController as? FlutterViewController {
            QuickPoseFlutterBridge.register(engine: root.engine)
            return
          }
        }
      }
      if let self, let root = self.window?.rootViewController as? FlutterViewController {
        QuickPoseFlutterBridge.register(engine: root.engine)
      }
    }
    DispatchQueue.main.async(execute: tryRegister)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: tryRegister)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: tryRegister)
  }
}
