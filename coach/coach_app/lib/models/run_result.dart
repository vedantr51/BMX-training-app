class RunResult {
  const RunResult({
    required this.rider,
    required this.reactionTime,
    required this.score,
    required this.startType,
    required this.timestamp,
  });

  final String rider;
  final double reactionTime;
  final int score;
  final String startType;
  final DateTime timestamp;

  factory RunResult.fromJson(Map<String, dynamic> json) {
    return RunResult(
      rider: (json['rider'] ?? 'Unknown').toString(),
      reactionTime: _toDouble(json['reaction_time']),
      score: _toInt(json['score']),
      startType: (json['start_type'] ?? 'unknown').toString(),
      timestamp: _toDateTime(json['timestamp']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      final raw = value.toInt();
      final isMilliseconds = raw > 1000000000000;
      return DateTime.fromMillisecondsSinceEpoch(
        isMilliseconds ? raw : raw * 1000,
      );
    }

    if (value is String) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        final isMilliseconds = parsedInt > 1000000000000;
        return DateTime.fromMillisecondsSinceEpoch(
          isMilliseconds ? parsedInt : parsedInt * 1000,
        );
      }

      final parsedDate = DateTime.tryParse(value);
      if (parsedDate != null) {
        return parsedDate;
      }
    }

    return DateTime.now();
  }
}