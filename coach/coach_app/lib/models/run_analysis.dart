import 'run_result.dart';
import 'replay_clip.dart';

class MotionBounds {
  const MotionBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

class RunAnalysis {
  const RunAnalysis({
    required this.id,
    required this.result,
    required this.replayClip,
    required this.feedbackLabel,
    required this.confidence,
    required this.movementDiffScore,
    required this.createdAt,
    this.motionBounds,
    this.greenLightAt,
    this.movementDetectedAt,
  });

  final String id;
  final RunResult result;
  final ReplayClip? replayClip;
  final String feedbackLabel;
  final double confidence;
  final double movementDiffScore;
  final DateTime createdAt;
  final MotionBounds? motionBounds;
  final DateTime? greenLightAt;
  final DateTime? movementDetectedAt;
}
