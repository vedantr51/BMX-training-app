class ReplayOverlayData {
  const ReplayOverlayData({
    this.gateStartedAt,
    this.yellowLightAt,
    this.greenLightAt,
    this.movementAt,
    this.rider,
    this.reactionTimeSeconds,
    this.score,
    this.startType,
  });

  final DateTime? gateStartedAt;
  final DateTime? yellowLightAt;
  final DateTime? greenLightAt;
  final DateTime? movementAt;

  final String? rider;
  final double? reactionTimeSeconds;
  final int? score;
  final String? startType;
}
