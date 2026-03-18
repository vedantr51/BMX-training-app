import 'dart:math';

import '../models/replay_clip.dart';
import '../models/run_analysis.dart';
import '../models/run_result.dart';

class AnalysisSummary {
  const AnalysisSummary({
    required this.bestReaction,
    required this.averageReaction,
    required this.consistency,
  });

  final double bestReaction;
  final double averageReaction;
  final double consistency;
}

class AnalysisService {
  AnalysisService({this.maxRuns = 5});

  final int maxRuns;
  final List<RunAnalysis> _recentRuns = <RunAnalysis>[];

  List<RunAnalysis> get recentRuns => List.unmodifiable(_recentRuns);

  AnalysisSummary get summary {
    if (_recentRuns.isEmpty) {
      return const AnalysisSummary(
        bestReaction: 0.0,
        averageReaction: 0.0,
        consistency: 0.0,
      );
    }

    final reactions = _recentRuns
        .map((item) => item.result.reactionTime)
        .toList(growable: false);

    final best = reactions.reduce(min);
    final avg = reactions.reduce((a, b) => a + b) / reactions.length;
    final variance = reactions
            .map((value) => pow(value - avg, 2).toDouble())
            .reduce((a, b) => a + b) /
        reactions.length;

    return AnalysisSummary(
      bestReaction: best,
      averageReaction: avg,
      consistency: sqrt(variance),
    );
  }

  RunAnalysis recordRun({
    required RunResult result,
    ReplayClip? replayClip,
    double confidence = 0.0,
    double movementDiffScore = 0.0,
    MotionBounds? motionBounds,
    DateTime? greenLightAt,
    DateTime? movementDetectedAt,
  }) {
    final analysis = RunAnalysis(
      id: '${result.timestamp.millisecondsSinceEpoch}_${result.rider}',
      result: result,
      replayClip: replayClip,
      feedbackLabel: reactionFeedback(result.reactionTime),
      confidence: confidence,
      movementDiffScore: movementDiffScore,
      createdAt: DateTime.now(),
      motionBounds: motionBounds,
      greenLightAt: greenLightAt,
      movementDetectedAt: movementDetectedAt,
    );

    _recentRuns.insert(0, analysis);
    if (_recentRuns.length > maxRuns) {
      _recentRuns.removeRange(maxRuns, _recentRuns.length);
    }

    return analysis;
  }

  String reactionFeedback(double reactionSeconds) {
    if (reactionSeconds >= 0.18 && reactionSeconds <= 0.25) {
      return 'Elite';
    }
    if (reactionSeconds > 0.25 && reactionSeconds <= 0.35) {
      return 'Good';
    }
    if (reactionSeconds > 0.35 && reactionSeconds <= 0.45) {
      return 'Average';
    }
    return 'Slow';
  }
}
