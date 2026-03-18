import 'package:hive/hive.dart';

import 'session_result.dart';

part 'session_record.g.dart';

@HiveType(typeId: 1)
class SessionRecord {
  @HiveField(0)
  final DateTime timestamp;

  @HiveField(1)
  final double reactionTimeSeconds;

  @HiveField(2)
  final int score;

  @HiveField(3)
  final StartType startType;

  SessionRecord({
    required this.timestamp,
    required this.reactionTimeSeconds,
    required this.score,
    required this.startType,
  });
}
