import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exercise_type.dart';
import 'quick_pose_events.dart';

/// Native method channel for lifecycle + config.
const String _methodChannelName = 'com.homeworkout.quickpose/methods';

/// Stream of pose / rep / feedback events.
const String _eventChannelName = 'com.homeworkout.quickpose/events';

/// Platform view type id (must match iOS + Android factory registration).
const String kQuickPosePlatformViewType = 'quick_pose_camera_view';

/// Flutter facade over QuickPose (iOS/Android). Pair with [QuickPoseCameraView].
///
/// Use [instance] (or the default [QuickPoseService.factory]) so the event stream
/// is only listened to once.
class QuickPoseService {
  QuickPoseService._() {
    _eventChannel.receiveBroadcastStream().listen(
          _onNativeEvent,
          onError: _onStreamError,
        );
  }

  /// Shared instance — avoids duplicate [EventChannel] subscriptions.
  static final QuickPoseService instance = QuickPoseService._();

  factory QuickPoseService() => instance;

  final MethodChannel _method = const MethodChannel(_methodChannelName);
  final EventChannel _eventChannel = const EventChannel(_eventChannelName);

  final _eventController = StreamController<QuickPoseEvent>.broadcast();

  /// Initialize SDK with your key from https://dev.quickpose.ai
  Future<void> initialize({required String sdkKey}) async {
    await _method.invokeMethod<void>('initialize', {'sdkKey': sdkKey});
  }

  /// Start processing [exercise] with optional targets (native may use for UX).
  Future<void> startSession(
    QuickPoseExerciseType exercise, {
    int? targetReps,
    double? plankTargetSeconds,
    bool useFrontCamera = true,
    bool sendLandmarks = false,
    int? counterThresholdPercent,
    int? timerThresholdPercent,
  }) async {
    await _method.invokeMethod<void>('startSession', {
      'exercise': exercise.wireName,
      'targetReps': targetReps,
      'plankTargetSeconds': plankTargetSeconds,
      'useFrontCamera': useFrontCamera,
      'sendLandmarks': sendLandmarks,
      'counterThresholdPercent': counterThresholdPercent,
      'timerThresholdPercent': timerThresholdPercent,
    });
  }

  Future<void> stopSession() async {
    await _method.invokeMethod<void>('stopSession');
  }

  Future<void> dispose() async {
    await _method.invokeMethod<void>('dispose');
  }

  Stream<QuickPoseEvent> get events => _eventController.stream;

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final parsed = quickPoseEventFromMap(event.cast<Object?, Object?>());
    if (parsed != null) {
      if (!_eventController.isClosed) {
        _eventController.add(parsed);
      }
    }
  }

  void _onStreamError(Object error, StackTrace st) {
    debugPrint('QuickPose event stream error: $error\n$st');
    if (!_eventController.isClosed) {
      _eventController.add(QuickPoseErrorEvent(message: 'event_stream', detail: '$error'));
    }
  }
}
