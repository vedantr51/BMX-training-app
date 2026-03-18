enum StartType { valid, falseStart, lateStart }

class SessionResult {
  final double reactionTimeSeconds;
  final int score;
  final StartType startType;

  SessionResult({
    required this.reactionTimeSeconds,
    required this.score,
    required this.startType,
  });
}
