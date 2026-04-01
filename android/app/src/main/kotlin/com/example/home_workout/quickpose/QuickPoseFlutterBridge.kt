package com.example.home_workout.quickpose

import ai.quickpose.camera.QuickPoseCameraSwitchView
import ai.quickpose.core.Feature
import ai.quickpose.core.Fitness
import ai.quickpose.core.QuickPose
import ai.quickpose.core.Status
import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.FrameLayout
import com.example.home_workout.MainActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

private const val METHODS = "com.homeworkout.quickpose/methods"
private const val EVENTS = "com.homeworkout.quickpose/events"
const val QUICK_POSE_VIEW_TYPE = "quick_pose_camera_view"

/** Registers channels + [QUICK_POSE_VIEW_TYPE] factory. Call from [MainActivity.configureFlutterEngine]. */
object QuickPoseFlutterBridge {
  fun register(engine: FlutterEngine, activity: MainActivity) {
    val messenger = engine.dartExecutor.binaryMessenger
    QuickPoseAndroidHost.activity = activity
    MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
      QuickPoseAndroidHost.handleMethod(call.method, call.arguments, result)
    }
    EventChannel(messenger, EVENTS).setStreamHandler(QuickPoseEventStreamHandler)
    engine.platformViewsController.registry.registerViewFactory(
      QUICK_POSE_VIEW_TYPE,
      QuickPoseViewFactory(activity),
    )
  }
}

private object QuickPoseEventStreamHandler : EventChannel.StreamHandler {
  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    QuickPoseAndroidHost.eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    QuickPoseAndroidHost.eventSink = null
  }
}

private class QuickPoseViewFactory(private val activity: MainActivity) :
  PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: android.content.Context, viewId: Int, args: Any?): PlatformView {
    return QuickPosePlatformView(activity, context, viewId)
  }
}

@SuppressLint("ViewConstructor")
private class QuickPosePlatformView(
  private val activity: MainActivity,
  context: android.content.Context,
  @Suppress("unused") private val viewId: Int,
) : PlatformView {
  private val root = FrameLayout(context)

  init {
    root.layoutParams = FrameLayout.LayoutParams(
      ViewGroup.LayoutParams.MATCH_PARENT,
      ViewGroup.LayoutParams.MATCH_PARENT,
    )
    QuickPoseAndroidHost.attachPreviewRoot(root)
  }

  override fun getView(): android.view.View = root

  override fun dispose() {
    QuickPoseAndroidHost.detachPreviewRoot(root)
  }
}

/// Falls back to amplitude-based counting; swap for QuickPose’s threshold counter if available in your SDK.
private class SimpleRepCounter(
  private val riseAbove: Double = 0.82,
  private val fallBelow: Double = 0.38,
) {
  private var high = false
  var count: Int = 0
    private set

  fun reset() {
    high = false
    count = 0
  }

  fun update(value: Double?) {
    if (value == null) return
    if (!high && value > riseAbove) high = true
    if (high && value < fallBelow) {
      high = false
      count++
    }
  }
}

private class SimpleHoldTimer(private val threshold: Double = 0.55) {
  private var holdStart: Long? = null

  fun reset() {
    holdStart = null
  }

  fun sample(value: Double?, now: Long = android.os.SystemClock.elapsedRealtime()): Pair<Double, Boolean> {
    if (value == null || value < threshold) {
      holdStart = null
      return 0.0 to false
    }
    if (holdStart == null) holdStart = now
    val seconds = (now - (holdStart ?: now)) / 1000.0
    return seconds to true
  }
}

object QuickPoseAndroidHost {
  private val main = Handler(Looper.getMainLooper())
  private val job = SupervisorJob()
  private val scope = CoroutineScope(job + Dispatchers.Main.immediate)

  var activity: MainActivity? = null
  var eventSink: EventChannel.EventSink? = null

  private var quickPose: QuickPose? = null
  private var cameraView: QuickPoseCameraSwitchView? = null
  private var boundRoot: FrameLayout? = null
  private var sessionJob: Job? = null

  private val repCounter = SimpleRepCounter()
  private val holdTimer = SimpleHoldTimer()
  private var lastEmittedRep: Int = 0

  fun attachPreviewRoot(root: FrameLayout) {
    boundRoot = root
    rebuildCameraIfPossible()
  }

  fun detachPreviewRoot(root: FrameLayout) {
    if (boundRoot === root) {
      stopSessionInternal()
      boundRoot?.removeAllViews()
      boundRoot = null
      cameraView = null
    }
  }

  private fun rebuildCameraIfPossible() {
    val root = boundRoot ?: return
    val qp = quickPose ?: return
    root.removeAllViews()
    cameraView?.stop()
    val cam = QuickPoseCameraSwitchView(root.context, qp)
    cameraView = cam
    root.addView(
      cam,
      FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT,
      ),
    )
  }

  fun handleMethod(method: String, arguments: Any?, result: MethodChannel.Result) {
    val ctx = activity ?: run {
      result.error("no_activity", "MainActivity gone", null)
      return
    }
    when (method) {
      "initialize" -> {
        val map = arguments as? Map<*, *>
        val key = map?.get("sdkKey") as? String
        if (key.isNullOrEmpty()) {
          result.error("bad_args", "sdkKey required", null)
          return
        }
        stopSessionInternal()
        quickPose = QuickPose(ctx, sdkKey = key)
        rebuildCameraIfPossible()
        result.success(null)
      }

      "startSession" -> {
        val map = arguments as? Map<*, *> ?: run {
          result.error("bad_args", "expected map", null)
          return
        }
        startSession(map)
        result.success(null)
      }

      "stopSession" -> {
        stopSessionInternal()
        result.success(null)
      }

      "dispose" -> {
        stopSessionInternal()
        quickPose = null
        boundRoot?.removeAllViews()
        cameraView = null
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  private fun featuresFor(exercise: String): Array<Feature> =
    when (exercise) {
      "squats" -> arrayOf(Feature.Fitness(Fitness.Squats))
      "plank" -> arrayOf(Feature.Fitness(Fitness.Plank))
      else -> arrayOf(Feature.Fitness(Fitness.PushUps))
    }

  private fun startSession(map: Map<*, *>) {
    val qp = quickPose ?: run {
      emit(mapOf("type" to "error", "message" to "not_initialized", "detail" to "Call initialize first"))
      return
    }
    if (boundRoot == null) {
      emit(mapOf("type" to "error", "message" to "no_preview", "detail" to "Show QuickPoseCameraView first"))
      return
    }

    val exercise = map["exercise"] as? String ?: "pushUps"
    val useFront = map["useFrontCamera"] as? Boolean ?: true

    stopSessionInternal()
    repCounter.reset()
    holdTimer.reset()
    lastEmittedRep = 0

    sessionJob =
      scope.launch {
        val cam = cameraView ?: return@launch
        cam.start(useFront)
        val feats = featuresFor(exercise)
        qp.start(
          feats,
          onFrame = { status, _, features, feedback, _ ->
            when (status) {
              is Status.Success -> {
                val required = feedback?.values?.firstOrNull { it.isRequired }
                if (required != null) {
                  emit(
                    mapOf(
                      "type" to "formFeedback",
                      "message" to required.displayString,
                      "isRequired" to true,
                    ),
                  )
                } else {
                  val value = features?.values?.firstOrNull()?.value?.toDouble()
                  when (exercise) {
                    "plank" -> {
                      val (sec, inHold) = holdTimer.sample(value)
                      emit(
                        mapOf(
                          "type" to "plankHold",
                          "seconds" to sec,
                          "inHold" to inHold,
                          "exercise" to "plank",
                        ),
                      )
                    }
                    else -> {
                      repCounter.update(value)
                      if (repCounter.count > lastEmittedRep) {
                        for (n in (lastEmittedRep + 1)..repCounter.count) {
                          emit(
                            mapOf(
                              "type" to "repCompleted",
                              "exercise" to exercise,
                              "repIndex" to n,
                              "totalReps" to n,
                              "progress01" to (value ?: 0.0),
                            ),
                          )
                        }
                        lastEmittedRep = repCounter.count
                      }
                    }
                  }
                }
              }
              is Status.NoPersonFound ->
                emit(mapOf("type" to "status", "code" to "noPerson"))
              else -> {}
            }
          },
        )
      }
  }

  private fun stopSessionInternal() {
    sessionJob?.cancel()
    sessionJob = null
    try {
      quickPose?.stop()
    } catch (_: Exception) {
    }
    try {
      cameraView?.stop()
    } catch (_: Exception) {
    }
  }

  private fun emit(payload: Map<String, Any?>) {
    main.post { eventSink?.success(payload) }
  }
}
