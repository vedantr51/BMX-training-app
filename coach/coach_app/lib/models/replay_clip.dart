class ReplayClip {
  const ReplayClip({
    required this.directoryPath,
    required this.framePaths,
    required this.frameInterval,
    required this.greenMarkerIndex,
    required this.movementMarkerIndex,
    required this.greenFramePath,
    required this.movementFramePath,
    required this.generatedAt,
  });

  final String directoryPath;
  final List<String> framePaths;
  final Duration frameInterval;
  final int greenMarkerIndex;
  final int movementMarkerIndex;
  final String? greenFramePath;
  final String? movementFramePath;
  final DateTime generatedAt;

  Duration get totalDuration =>
      Duration(milliseconds: frameInterval.inMilliseconds * framePaths.length);

  bool get hasFrames => framePaths.isNotEmpty;
}
