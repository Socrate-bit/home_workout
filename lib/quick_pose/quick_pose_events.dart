import 'exercise_type.dart';

/// All events emitted on [QuickPoseService.events].
sealed class QuickPoseEvent {
  const QuickPoseEvent();
}

/// Fire when [QuickPoseThresholdCounter] detects a new rep (push-up / squat).
class QuickPoseRepCompletedEvent extends QuickPoseEvent {
  const QuickPoseRepCompletedEvent({
    required this.exercise,
    required this.repIndex,
    required this.totalReps,
    this.progress01,
  });

  final QuickPoseExerciseType exercise;
  final int repIndex;

  /// Running total after this rep.
  final int totalReps;

  /// Exercise fill / ROM 0..1 when available.
  final double? progress01;

  factory QuickPoseRepCompletedEvent.fromMap(Map<Object?, Object?> map) {
    return QuickPoseRepCompletedEvent(
      exercise: _parseExercise(map['exercise'] as String?),
      repIndex: map['repIndex'] as int,
      totalReps: map['totalReps'] as int,
      progress01: (map['progress01'] as num?)?.toDouble(),
    );
  }
}

/// Form guidance from QuickPose (e.g. "Get on floor", joint visibility).
class QuickPoseFormFeedbackEvent extends QuickPoseEvent {
  const QuickPoseFormFeedbackEvent({
    required this.message,
    required this.isRequired,
  });

  final String message;
  final bool isRequired;

  factory QuickPoseFormFeedbackEvent.fromMap(Map<Object?, Object?> map) {
    return QuickPoseFormFeedbackEvent(
      message: map['message'] as String,
      isRequired: map['isRequired'] as bool,
    );
  }
}

/// Plank valid-hold time in seconds (from [QuickPoseThresholdTimer]).
class QuickPosePlankHoldEvent extends QuickPoseEvent {
  const QuickPosePlankHoldEvent({
    required this.seconds,
    required this.inHold,
  });

  final double seconds;
  final bool inHold;

  factory QuickPosePlankHoldEvent.fromMap(Map<Object?, Object?> map) {
    return QuickPosePlankHoldEvent(
      seconds: (map['seconds'] as num).toDouble(),
      inHold: map['inHold'] as bool,
    );
  }
}

/// Person lost, SDK validation, etc.
class QuickPoseStatusEvent extends QuickPoseEvent {
  const QuickPoseStatusEvent({required this.code, this.message});

  final String code;
  final String? message;

  factory QuickPoseStatusEvent.fromMap(Map<Object?, Object?> map) {
    return QuickPoseStatusEvent(
      code: map['code'] as String,
      message: map['message'] as String?,
    );
  }
}

class QuickPoseErrorEvent extends QuickPoseEvent {
  const QuickPoseErrorEvent({required this.message, this.detail});

  final String message;
  final String? detail;

  factory QuickPoseErrorEvent.fromMap(Map<Object?, Object?> map) {
    return QuickPoseErrorEvent(
      message: map['message'] as String,
      detail: map['detail'] as String?,
    );
  }
}

/// Optional: normalized landmarks (reduce FPS from native before enabling).
class QuickPoseLandmarksEvent extends QuickPoseEvent {
  const QuickPoseLandmarksEvent({required this.points});

  /// Flat list [x0, y0, z0, x1, y1, z1, ...] in normalized image space.
  final List<double> points;

  factory QuickPoseLandmarksEvent.fromMap(Map<Object?, Object?> map) {
    final list = map['points'] as List<Object?>;
    return QuickPoseLandmarksEvent(
      points: list.map((e) => (e as num).toDouble()).toList(),
    );
  }
}

QuickPoseExerciseType _parseExercise(String? raw) {
  return switch (raw) {
    'pushUps' => QuickPoseExerciseType.pushUps,
    'squats' => QuickPoseExerciseType.squats,
    'plank' => QuickPoseExerciseType.plankHold,
    _ => QuickPoseExerciseType.pushUps,
  };
}

QuickPoseEvent? quickPoseEventFromMap(Map<Object?, Object?> map) {
  final type = map['type'] as String?;
  return switch (type) {
    'repCompleted' => QuickPoseRepCompletedEvent.fromMap(map),
    'formFeedback' => QuickPoseFormFeedbackEvent.fromMap(map),
    'plankHold' => QuickPosePlankHoldEvent.fromMap(map),
    'status' => QuickPoseStatusEvent.fromMap(map),
    'error' => QuickPoseErrorEvent.fromMap(map),
    'landmarks' => QuickPoseLandmarksEvent.fromMap(map),
    _ => null,
  };
}
