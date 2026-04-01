/// Maps to native QuickPose fitness features. Add new values here and extend
/// native `exerciseType` switching in iOS/Android.
enum QuickPoseExerciseType {
  pushUps,
  squats,
  plankHold,
}

extension QuickPoseExerciseTypeCodec on QuickPoseExerciseType {
  /// Wire string used in MethodChannel / creation params.
  String get wireName => switch (this) {
        QuickPoseExerciseType.pushUps => 'pushUps',
        QuickPoseExerciseType.squats => 'squats',
        QuickPoseExerciseType.plankHold => 'plank',
      };
}
