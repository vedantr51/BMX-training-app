import 'package:hive/hive.dart';

part 'rider.g.dart';

/// Rider profile stored in Hive.
@HiveType(typeId: 0)
class Rider extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  /// Best (lowest) reaction time in seconds.
  @HiveField(2)
  final double personalBestReactionTime;

  /// Highest score achieved.
  @HiveField(3)
  final int bestScore;

  Rider({
    required this.id,
    required this.name,
    required this.personalBestReactionTime,
    required this.bestScore,
  });

  Rider copyWith({
    String? id,
    String? name,
    double? personalBestReactionTime,
    int? bestScore,
  }) {
    return Rider(
      id: id ?? this.id,
      name: name ?? this.name,
      personalBestReactionTime: personalBestReactionTime ?? this.personalBestReactionTime,
      bestScore: bestScore ?? this.bestScore,
    );
  }
}
