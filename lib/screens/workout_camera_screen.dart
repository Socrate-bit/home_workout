import 'dart:async';

import 'package:flutter/material.dart';

import '../quick_pose/quick_pose.dart';

/// Example screen: native camera (pose overlay) + Flutter pet / rep UI.
///
/// Set [sdkKey] from `dev.quickpose.ai` (or `--dart-define=QUICKPOSE_KEY=...`).
class WorkoutCameraScreen extends StatefulWidget {
  const WorkoutCameraScreen({
    super.key,
    required this.sdkKey,
    this.exercise = QuickPoseExerciseType.pushUps,
  });

  final String sdkKey;
  final QuickPoseExerciseType exercise;

  @override
  State<WorkoutCameraScreen> createState() => _WorkoutCameraScreenState();
}

class _WorkoutCameraScreenState extends State<WorkoutCameraScreen> {
  final _quickPose = QuickPoseService.instance;
  late final PetRewardCoordinator _rewards;
  StreamSubscription<QuickPoseEvent>? _sub;

  var _repTotal = 0;
  String? _feedback;
  String? _petLine = '🐣 Ready!';
  double? _plankSeconds;

  @override
  void initState() {
    super.initState();
    _rewards = PetRewardCoordinator(
      service: _quickPose,
      onUnlock: (id, rule) {
        if (!mounted) return;
        setState(() => _petLine = 'Unlocked: ${rule.label} ($id)');
      },
    )..start();

    _sub = _quickPose.events.listen(_onEvent);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _quickPose.initialize(sdkKey: widget.sdkKey);
    await _quickPose.startSession(
      widget.exercise,
      targetReps: 10,
      useFrontCamera: true,
    );
  }

  void _onEvent(QuickPoseEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case QuickPoseRepCompletedEvent(:final totalReps, :final exercise):
          _repTotal = totalReps;
          _petLine = switch (exercise) {
            QuickPoseExerciseType.pushUps => 'Great push-up #$_repTotal!',
            QuickPoseExerciseType.squats => 'Squat beast #$_repTotal!',
            _ => 'Keep going!',
          };
        case QuickPoseFormFeedbackEvent(:final message):
          _feedback = message;
        case QuickPosePlankHoldEvent(:final seconds, :final inHold):
          _plankSeconds = seconds;
          _feedback = inHold ? 'Hold ${seconds.toStringAsFixed(1)}s' : null;
        case QuickPoseStatusEvent(:final code):
          _feedback = code;
        case QuickPoseErrorEvent(:final message):
          _feedback = 'Error: $message';
        case QuickPoseLandmarksEvent():
          break;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_rewards.stop());
    unawaited(_quickPose.stopSession());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const QuickPoseCameraView(),
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _HudCard(
                exercise: widget.exercise,
                repTotal: _repTotal,
                plankSeconds: _plankSeconds,
                feedback: _feedback,
                petLine: _petLine ?? '',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudCard extends StatelessWidget {
  const _HudCard({
    required this.exercise,
    required this.repTotal,
    required this.plankSeconds,
    required this.feedback,
    required this.petLine,
  });

  final QuickPoseExerciseType exercise;
  final int repTotal;
  final double? plankSeconds;
  final String? feedback;
  final String petLine;

  @override
  Widget build(BuildContext context) {
    final title = switch (exercise) {
      QuickPoseExerciseType.pushUps => 'Push-ups',
      QuickPoseExerciseType.squats => 'Squats',
      QuickPoseExerciseType.plankHold => 'Plank hold',
    };
    final stat = exercise == QuickPoseExerciseType.plankHold
        ? '${plankSeconds?.toStringAsFixed(1) ?? '0.0'} s'
        : '$repTotal reps';

    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(stat, style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(petLine, style: const TextStyle(color: Colors.amberAccent)),
            if (feedback != null && feedback!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(feedback!, style: const TextStyle(color: Colors.white)),
            ],
          ],
        ),
      ),
    );
  }
}
