import AVFoundation
import Flutter
import UIKit

#if canImport(QuickPoseCore)
import QuickPoseCore
#endif

#if canImport(QuickPoseCamera)
import QuickPoseCamera
#endif

/// Registers MethodChannel, EventChannel, and the `quick_pose_camera_view` platform view factory.
enum QuickPoseFlutterBridge {
  private static let methodChannelName = "com.homeworkout.quickpose/methods"
  private static let eventChannelName = "com.homeworkout.quickpose/events"
  private static let viewTypeId = "quick_pose_camera_view"

  /// True after channels + platform view factory are wired (only once).
  private static var didRegister = false

  /// Called from [FlutterImplicitEngineDelegate] when the implicit engine starts.
  static func register(engineBridge: FlutterImplicitEngineBridge) {
    register(
      messenger: engineBridge.applicationRegistrar.messenger(),
      pluginRegistry: engineBridge.pluginRegistry
    )
  }

  /// Fallback when implicit-engine callback does not run or runs too early — use the same engine as [FlutterViewController].
  static func register(engine: FlutterEngine) {
    register(messenger: engine.binaryMessenger, pluginRegistry: engine.pluginRegistry)
  }

  private static func register(
    messenger: FlutterBinaryMessenger,
    pluginRegistry: FlutterPluginRegistry
  ) {
    guard !didRegister else { return }
    didRegister = true

    let registrar = pluginRegistry.registrar(forPlugin: "QuickPoseFlutterBridge")

    let methods = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      QuickPoseSessionHost.shared.handle(call: call, flutterResult: result)
    }

    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    events.setStreamHandler(QuickPoseEventStreamHandler.shared)

    registrar?.register(
      QuickPoseViewFactory(messenger: messenger),
      withId: viewTypeId
    )
  }
}

// MARK: - Event stream

final class QuickPoseEventStreamHandler: NSObject, FlutterStreamHandler {
  static let shared = QuickPoseEventStreamHandler()

  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    QuickPoseSessionHost.shared.attachEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    QuickPoseSessionHost.shared.attachEventSink(nil)
    return nil
  }
}

// MARK: - Platform view

final class QuickPoseViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    QuickPosePlatformView(frame: frame, viewId: viewId, args: args)
  }
}

final class QuickPosePlatformView: NSObject, FlutterPlatformView {
  private let viewId: Int64
  private let container: UIView

  init(frame: CGRect, viewId: Int64, args: Any?) {
    self.viewId = viewId
    self.container = UIView(frame: frame)
    super.init()
    container.backgroundColor = .black
    container.clipsToBounds = true
    QuickPoseSessionHost.shared.attachPreviewContainer(container, viewId: viewId)
  }

  func view() -> UIView {
    container
  }

  deinit {
    QuickPoseSessionHost.shared.detachPreview(viewId: viewId)
  }
}

// MARK: - Session + QuickPose (UIKit camera stack)

final class QuickPoseSessionHost: NSObject {
  static let shared = QuickPoseSessionHost()

  private var eventSink: FlutterEventSink?
  private weak var previewContainer: UIView?
  private var activeViewId: Int64?

  private var sdkKey: String?

  #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
  private var quickPose: QuickPose?
  private var camera: QuickPoseCamera?
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var overlayView: UIImageView?
  private var repCounter = QuickPoseThresholdCounter()
  private var plankTimer = QuickPoseThresholdTimer(threshold: 0.2)
  private var lastRepTotal = 0
  private var currentExercise: String = "pushUps"
  private var isRunning = false
  #endif

  func attachEventSink(_ sink: FlutterEventSink?) {
    eventSink = sink
  }

  func attachPreviewContainer(_ view: UIView, viewId: Int64) {
    previewContainer = view
    activeViewId = viewId
    rebuildPreviewHierarchyIfNeeded()
  }

  func detachPreview(viewId: Int64) {
    if activeViewId == viewId {
      activeViewId = nil
      previewContainer = nil
      #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
      stopQuickPoseInternal(notifyFlutter: false)
      #endif
    }
  }

  func handle(call: FlutterMethodCall, flutterResult: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      guard let args = call.arguments as? [String: Any],
            let key = args["sdkKey"] as? String
      else {
        flutterResult(FlutterError(code: "bad_args", message: "sdkKey required", details: nil))
        return
      }
      sdkKey = key
      #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
      quickPose = QuickPose(sdkKey: key)
      #endif
      flutterResult(nil)

    case "startSession":
      guard let args = call.arguments as? [String: Any] else {
        flutterResult(FlutterError(code: "bad_args", message: "expected map", details: nil))
        return
      }
      #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
      startQuickPose(args: args)
      flutterResult(nil)
      #else
      flutterResult(
        FlutterError(
          code: "no_sdk",
          message: "Add QuickPose via SPM (QuickPoseCore + QuickPoseCamera + QuickPoseMP*)",
          details: nil
        )
      )
      #endif

    case "stopSession":
      #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
      stopQuickPoseInternal(notifyFlutter: false)
      #endif
      flutterResult(nil)

    case "dispose":
      #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
      stopQuickPoseInternal(notifyFlutter: false)
      quickPose = nil
      #endif
      sdkKey = nil
      flutterResult(nil)

    default:
      flutterResult(FlutterMethodNotImplemented)
    }
  }

  private func rebuildPreviewHierarchyIfNeeded() {
    guard let container = previewContainer else { return }
    container.subviews.forEach { $0.removeFromSuperview() }

    let cameraHost = UIView(frame: container.bounds)
    cameraHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cameraHost.backgroundColor = .black
    container.addSubview(cameraHost)

    let overlay = UIImageView(frame: container.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.contentMode = .scaleAspectFill
    container.addSubview(overlay)
    #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
    overlayView = overlay
    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    #endif
  }

  #if canImport(QuickPoseCore) && canImport(QuickPoseCamera)
  private func qpFeatures(for exercise: String) -> [QuickPose.Feature] {
    switch exercise {
    case "squats":
      return [.fitness(.squats)]
    case "plank":
      return [.fitness(.plank)]
    default:
      return [.fitness(.pushUps)]
    }
  }

  private func startQuickPose(args: [String: Any]) {
    guard let qp = quickPose else {
      emit([
        "type": "error",
        "message": "not_initialized",
        "detail": "Call initialize(sdkKey) first",
      ])
      return
    }

    stopQuickPoseInternal(notifyFlutter: false)
    rebuildPreviewHierarchyIfNeeded()

    guard let container = previewContainer else {
      emit(["type": "error", "message": "no_preview", "detail": "Platform view not in tree"])
      return
    }

    let exercise = args["exercise"] as? String ?? "pushUps"
    currentExercise = exercise
    let useFront = args["useFrontCamera"] as? Bool ?? true

    repCounter = QuickPoseThresholdCounter()
    plankTimer = QuickPoseThresholdTimer(threshold: 0.2)
    lastRepTotal = 0

    let cameraHost = container.subviews.first ?? container

    camera = QuickPoseCamera(useFrontCamera: useFront)
    do {
      try camera?.start(delegate: qp)
    } catch {
      emit(["type": "error", "message": "camera_start", "detail": "\(error)"])
      return
    }

    if let session = camera?.session {
      let layer = AVCaptureVideoPreviewLayer(session: session)
      layer.videoGravity = .resizeAspectFill
      layer.frame = cameraHost.bounds
      cameraHost.layer.addSublayer(layer)
      previewLayer = layer
    }

    let features = qpFeatures(for: exercise)
    isRunning = true

    qp.start(features: features, onFrame: { [weak self] status, image, featureResults, feedback, _ in
      guard let self = self else { return }
      switch status {
      case .success:
        if let img = image {
          DispatchQueue.main.async {
            self.overlayView?.image = img
          }
        }
        if let fb = feedback?.values.first(where: { $0.isRequired }) {
          self.emit([
            "type": "formFeedback",
            "message": fb.displayString,
            "isRequired": true,
          ])
        } else if exercise == "plank", let result = featureResults?.values.first {
          let timerState = self.plankTimer.time(result.value)
          self.emit([
            "type": "plankHold",
            "seconds": timerState.time,
            "inHold": result.value >= 0.45,
            "exercise": "plank",
          ])
        } else if let result = featureResults?.values.first {
          let state = self.repCounter.count(result.value)
          if state.count > self.lastRepTotal {
            for newTotal in (self.lastRepTotal + 1)...state.count {
              self.emit([
                "type": "repCompleted",
                "exercise": exercise,
                "repIndex": newTotal,
                "totalReps": newTotal,
                "progress01": result.value,
              ])
            }
            self.lastRepTotal = state.count
          }
        }
      case .noPersonFound:
        self.emit(["type": "status", "code": "noPerson", "message": NSNull()])
      case .sdkValidationError:
        self.emit(["type": "status", "code": "sdkValidationError", "message": NSNull()])
      @unknown default:
        break
      }
    })
  }

  private func stopQuickPoseInternal(notifyFlutter: Bool) {
    isRunning = false
    quickPose?.stop()
    camera?.stop()
    camera = nil
    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    overlayView?.image = nil
    overlayView = nil
    if notifyFlutter {
      emit(["type": "status", "code": "stopped", "message": NSNull()])
    }
  }
  #endif

  private func emit(_ payload: [String: Any]) {
    guard let sink = eventSink else { return }
    DispatchQueue.main.async {
      sink(payload)
    }
  }
}
