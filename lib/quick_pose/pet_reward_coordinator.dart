import 'dart:async';

import 'exercise_type.dart';
import 'quick_pose_events.dart';
import 'quick_pose_service.dart';

/// Example Finch-style mapping: thresholds → cosmetic unlocks.
class PetRewardRule {
  const PetRewardRule({
    required this.exercise,
    required this.milestone,
    required this.rewardId,
    this.label = '',
  });

  final QuickPoseExerciseType exercise;

  /// Rep count for push-up/squat; **seconds of valid hold** for [QuickPoseExerciseType.plankHold].
  final int milestone;
  final String rewardId;
  final String label;
}

/// Listens to [QuickPoseService.events] and fires unlock callbacks once per rule.
class PetRewardCoordinator {
  PetRewardCoordinator({
    QuickPoseService? service,
    this.onUnlock,
    List<PetRewardRule> rules = const [
      PetRewardRule(
        exercise: QuickPoseExerciseType.pushUps,
        milestone: 10,
        rewardId: 'hat_pushup_10',
        label: 'Push-up cap',
      ),
      PetRewardRule(
        exercise: QuickPoseExerciseType.squats,
        milestone: 15,
        rewardId: 'glasses_squat_15',
        label: 'Sport shades',
      ),
      PetRewardRule(
        exercise: QuickPoseExerciseType.plankHold,
        milestone: 60,
        rewardId: 'bandana_plank_60s',
        label: 'Endurance bandana',
      ),
    ],
  })  : _service = service ?? QuickPoseService.instance,
        _rules = rules;

  final QuickPoseService _service;
  final List<PetRewardRule> _rules;
  StreamSubscription<QuickPoseEvent>? _sub;

  final Map<String, bool> _unlocked = {};
  final Map<QuickPoseExerciseType, int> _bestReps = {};
  final Map<QuickPoseExerciseType, double> _bestPlankSeconds = {};

  /// Called once per [PetRewardRule.rewardId] when the user crosses the threshold.
  final void Function(String rewardId, PetRewardRule rule)? onUnlock;

  void start() {
    _sub ??= _service.events.listen(_handle);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _handle(QuickPoseEvent event) {
    if (event is QuickPoseRepCompletedEvent) {
      _bestReps[event.exercise] = event.totalReps;
      for (final rule in _rules) {
        if (rule.exercise != event.exercise) continue;
        if (_unlocked[rule.rewardId] == true) continue;
        if (event.totalReps >= rule.milestone) {
          _unlocked[rule.rewardId] = true;
          onUnlock?.call(rule.rewardId, rule);
        }
      }
    } else if (event is QuickPosePlankHoldEvent && event.inHold) {
      final sec = event.seconds;
      final ex = QuickPoseExerciseType.plankHold;
      if (sec > (_bestPlankSeconds[ex] ?? 0)) {
        _bestPlankSeconds[ex] = sec;
      }
      for (final rule in _rules) {
        if (rule.exercise != ex) continue;
        if (_unlocked[rule.rewardId] == true) continue;
        if (sec >= rule.milestone) {
          _unlocked[rule.rewardId] = true;
          onUnlock?.call(rule.rewardId, rule);
        }
      }
    }
  }
}
