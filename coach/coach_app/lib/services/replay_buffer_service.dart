import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/replay_clip.dart';
import '../models/replay_overlay_data.dart';
import '../models/run_analysis.dart';

class ReplayBufferService {
  ReplayBufferService({
    this.preBufferDuration = const Duration(milliseconds: 4200),
    this.postBufferDuration = const Duration(milliseconds: 1200),
    this.maxBufferDuration = const Duration(seconds: 9),
    this.maxExportWidth = 480,
    this.jpegQuality = 80,
  });

  final Duration preBufferDuration;
  final Duration postBufferDuration;
  final Duration maxBufferDuration;
  final int maxExportWidth;
  final int jpegQuality;

  final List<_BufferedFrame> _frameBuffer = <_BufferedFrame>[];
  DateTime? _greenLightAt;
  _PendingCapture? _pendingCapture;
  int _captureSequence = 0;

  void reset() {
    _frameBuffer.clear();
    _pendingCapture?.completer.complete(null);
    _pendingCapture = null;
    _greenLightAt = null;
  }

  void markGreenLight({DateTime? timestamp}) {
    _greenLightAt = timestamp ?? DateTime.now();
  }

  void addFrame(
    CameraImage image, {
    DateTime? timestamp,
    double diffScore = 0.0,
    MotionBounds? motionBounds,
  }) {
    if (image.planes.isEmpty) {
      return;
    }

    final frame = _BufferedFrame.fromCameraImage(
      image,
      timestamp: timestamp ?? DateTime.now(),
      diffScore: diffScore,
      motionBounds: motionBounds,
    );

    _frameBuffer.add(frame);
    _pruneOldFrames();

    final pending = _pendingCapture;
    if (pending == null) {
      return;
    }

    pending.frames.add(frame);
    if (!frame.timestamp.isBefore(pending.captureEndAt)) {
      _pendingCapture = null;
      unawaited(_finalizePendingCapture(pending));
    }
  }

  Future<ReplayClip?> beginMovementCapture({
    required DateTime movementAt,
    MotionBounds? motionBounds,
    required double diffScore,
    ReplayOverlayData? overlayData,
  }) {
    final existing = _pendingCapture;
    if (existing != null) {
      return existing.completer.future;
    }

    final captureStartAt = movementAt.subtract(preBufferDuration);
    final preFrames = _frameBuffer
        .where((frame) => !frame.timestamp.isBefore(captureStartAt))
        .toList(growable: true);

    if (preFrames.isEmpty && _frameBuffer.isNotEmpty) {
      final fallbackStart = max(0, _frameBuffer.length - 8);
      preFrames.addAll(_frameBuffer.sublist(fallbackStart));
    }

    if (preFrames.isEmpty) {
      return Future<ReplayClip?>.value(null);
    }

    final pending = _PendingCapture(
      frames: preFrames,
      movementAt: movementAt,
      captureEndAt: movementAt.add(postBufferDuration),
      motionBounds: motionBounds,
      diffScore: diffScore,
      overlayData: overlayData,
      completer: Completer<ReplayClip?>(),
    );

    _pendingCapture = pending;

    final latest = _frameBuffer.isEmpty ? null : _frameBuffer.last;
    if ((latest != null && !latest.timestamp.isBefore(pending.captureEndAt)) ||
        DateTime.now().isAfter(pending.captureEndAt)) {
      _pendingCapture = null;
      unawaited(_finalizePendingCapture(pending));
    }

    return pending.completer.future;
  }

  Future<ReplayClip?> exportBufferedReplay({
    required DateTime movementAt,
    MotionBounds? motionBounds,
    required double diffScore,
    ReplayOverlayData? overlayData,
  }) async {
    if (_frameBuffer.isEmpty) {
      return null;
    }

    final startAt = movementAt.subtract(preBufferDuration);
    final endAt = movementAt.add(postBufferDuration);
    final frames = _frameBuffer
        .where(
          (frame) =>
              !frame.timestamp.isBefore(startAt) &&
              !frame.timestamp.isAfter(endAt),
        )
        .toList(growable: true);

    if (frames.isEmpty) {
      final fallbackStart = max(0, _frameBuffer.length - 30);
      frames.addAll(_frameBuffer.sublist(fallbackStart));
    }

    if (frames.isEmpty) {
      return null;
    }

    final pending = _PendingCapture(
      frames: frames,
      movementAt: movementAt,
      captureEndAt: movementAt,
      motionBounds: motionBounds,
      diffScore: diffScore,
      overlayData: overlayData,
      completer: Completer<ReplayClip?>(),
    );

    return _exportReplay(pending);
  }

  void stopPendingCapture() {
    final pending = _pendingCapture;
    if (pending == null) {
      return;
    }

    _pendingCapture = null;
    unawaited(_finalizePendingCapture(pending));
  }

  Future<void> _finalizePendingCapture(_PendingCapture pending) async {
    try {
      final clip = await _exportReplay(pending);
      if (!pending.completer.isCompleted) {
        pending.completer.complete(clip);
      }
    } catch (_) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(null);
      }
    }
  }

  Future<ReplayClip?> _exportReplay(_PendingCapture pending) async {
    final orderedFrames = _uniqueAndSortedFrames(pending.frames);
    if (orderedFrames.isEmpty) {
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    _captureSequence += 1;
    final replayDir = Directory(
      '${tempDir.path}/coach_replays/replay_${now.millisecondsSinceEpoch}_$_captureSequence',
    );
    await replayDir.create(recursive: true);

    final framePaths = <String>[];
    final frameInterval = _estimateFrameInterval(orderedFrames);
    final greenRef = _greenLightAt ?? pending.movementAt;
    final greenIndex = _nearestFrameIndex(orderedFrames, greenRef);
    final movementIndex = _nearestFrameIndex(orderedFrames, pending.movementAt);

    final clipStart = orderedFrames.first.timestamp;
    final clipEnd = orderedFrames.last.timestamp;
    final overlay = pending.overlayData;

    for (var i = 0; i < orderedFrames.length; i++) {
      final frame = orderedFrames[i];
      final image = frame.toJpegImage(maxExportWidth: maxExportWidth);

      _drawPersistentOverlay(
        image,
        frameTimestamp: frame.timestamp,
        clipStart: clipStart,
        clipEnd: clipEnd,
        overlayData: overlay,
        movementAt: pending.movementAt,
      );

      _drawEventMarkers(
        image,
        frameIndex: i,
        greenIndex: greenIndex,
        movementIndex: movementIndex,
        movementBounds: pending.motionBounds,
      );

      final bytes = img.encodeJpg(image, quality: jpegQuality);
      final outputPath = '${replayDir.path}/frame_${i.toString().padLeft(4, '0')}.jpg';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(bytes, flush: true);
      framePaths.add(outputPath);
    }

    return ReplayClip(
      directoryPath: replayDir.path,
      framePaths: framePaths,
      frameInterval: frameInterval,
      greenMarkerIndex: greenIndex,
      movementMarkerIndex: movementIndex,
      greenFramePath: framePaths[greenIndex],
      movementFramePath: framePaths[movementIndex],
      generatedAt: now,
    );
  }

  void _drawPersistentOverlay(
    img.Image image, {
    required DateTime frameTimestamp,
    required DateTime clipStart,
    required DateTime clipEnd,
    required DateTime movementAt,
    ReplayOverlayData? overlayData,
  }) {
    final topBarHeight = 34;
    final secondBarHeight = 24;

    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: image.width,
      y2: topBarHeight,
      color: img.ColorRgba8(0, 0, 0, 190),
    );
    img.fillRect(
      image,
      x1: 0,
      y1: topBarHeight,
      x2: image.width,
      y2: topBarHeight + secondBarHeight,
      color: img.ColorRgba8(10, 10, 10, 170),
    );

    final phase = _phaseLabel(frameTimestamp, overlayData, movementAt);
    img.drawString(
      image,
      phase,
      font: img.arial14,
      x: 8,
      y: 8,
      color: img.ColorRgb8(255, 255, 255),
    );

    final stats = _statsLabel(overlayData);
    img.drawString(
      image,
      stats,
      font: img.arial14,
      x: 8,
      y: topBarHeight + 4,
      color: img.ColorRgb8(220, 220, 220),
    );

    final timelineY = image.height - 18;
    img.fillRect(
      image,
      x1: 12,
      y1: timelineY,
      x2: image.width - 12,
      y2: timelineY + 6,
      color: img.ColorRgba8(30, 30, 30, 190),
    );

    _drawTimelineTick(
      image,
      timestamp: overlayData?.gateStartedAt,
      clipStart: clipStart,
      clipEnd: clipEnd,
      y: timelineY - 6,
      color: img.ColorRgb8(214, 72, 72),
      label: 'G',
    );
    _drawTimelineTick(
      image,
      timestamp: overlayData?.yellowLightAt,
      clipStart: clipStart,
      clipEnd: clipEnd,
      y: timelineY - 6,
      color: img.ColorRgb8(246, 201, 54),
      label: 'Y',
    );
    _drawTimelineTick(
      image,
      timestamp: overlayData?.greenLightAt,
      clipStart: clipStart,
      clipEnd: clipEnd,
      y: timelineY - 6,
      color: img.ColorRgb8(37, 183, 97),
      label: 'GR',
    );
    _drawTimelineTick(
      image,
      timestamp: overlayData?.movementAt ?? movementAt,
      clipStart: clipStart,
      clipEnd: clipEnd,
      y: timelineY - 6,
      color: img.ColorRgb8(230, 94, 67),
      label: 'M',
    );

    final frameX = _timelineX(frameTimestamp, clipStart, clipEnd, image.width);
    img.drawLine(
      image,
      x1: frameX,
      y1: timelineY - 8,
      x2: frameX,
      y2: timelineY + 8,
      color: img.ColorRgb8(255, 255, 255),
      thickness: 2,
    );
  }

  void _drawTimelineTick(
    img.Image image, {
    required DateTime? timestamp,
    required DateTime clipStart,
    required DateTime clipEnd,
    required int y,
    required img.ColorRgb8 color,
    required String label,
  }) {
    if (timestamp == null) {
      return;
    }

    final x = _timelineX(timestamp, clipStart, clipEnd, image.width);
    img.drawLine(
      image,
      x1: x,
      y1: y,
      x2: x,
      y2: y + 12,
      color: color,
      thickness: 2,
    );
    img.drawString(
      image,
      label,
      font: img.arial14,
      x: max(0, x - 10),
      y: max(0, y - 14),
      color: color,
    );
  }

  int _timelineX(
    DateTime timestamp,
    DateTime clipStart,
    DateTime clipEnd,
    int width,
  ) {
    final total = max(1, clipEnd.difference(clipStart).inMilliseconds);
    final elapsed = timestamp.difference(clipStart).inMilliseconds.clamp(0, total);
    final ratio = elapsed / total;
    return (12 + ratio * (width - 24)).round();
  }

  String _phaseLabel(
    DateTime frameTimestamp,
    ReplayOverlayData? overlayData,
    DateTime movementAt,
  ) {
    final gate = overlayData?.gateStartedAt;
    final yellow = overlayData?.yellowLightAt;
    final green = overlayData?.greenLightAt;
    final movement = overlayData?.movementAt ?? movementAt;

    if (gate != null && frameTimestamp.isBefore(gate)) {
      return 'PRE-START BUFFER';
    }
    if (yellow != null && frameTimestamp.isBefore(yellow)) {
      return 'GATE STARTED / RED';
    }
    if (green != null && frameTimestamp.isBefore(green)) {
      return 'YELLOW LIGHT';
    }
    if (frameTimestamp.isBefore(movement)) {
      return 'GREEN LIGHT -> WAITING FOR MOVE';
    }
    return 'MOVEMENT DETECTED';
  }

  String _statsLabel(ReplayOverlayData? overlayData) {
    if (overlayData == null) {
      return 'Analyzing...';
    }

    final rider = overlayData.rider ?? 'Unknown';
    final reaction = overlayData.reactionTimeSeconds == null
        ? '--'
        : '${overlayData.reactionTimeSeconds!.toStringAsFixed(3)}s';
    final score = overlayData.score?.toString() ?? '--';
    final start = overlayData.startType ?? '--';

    return 'Rider: $rider   RT: $reaction   Score: $score   Start: $start';
  }

  void _drawEventMarkers(
    img.Image image, {
    required int frameIndex,
    required int greenIndex,
    required int movementIndex,
    MotionBounds? movementBounds,
  }) {
    if (frameIndex == greenIndex) {
      _drawTag(
        image,
        text: 'GREEN',
        y: 64,
        background: img.ColorRgb8(24, 160, 88),
      );
    }

    if (frameIndex == movementIndex) {
      _drawTag(
        image,
        text: 'MOVE',
        y: 90,
        background: img.ColorRgb8(220, 70, 50),
      );

      if (movementBounds != null) {
        final left = (movementBounds.left * image.width)
            .clamp(0.0, image.width.toDouble() - 1)
            .round();
        final top = (movementBounds.top * image.height)
            .clamp(0.0, image.height.toDouble() - 1)
            .round();
        final width = (movementBounds.width * image.width)
            .clamp(1.0, image.width.toDouble())
            .round();
        final height = (movementBounds.height * image.height)
            .clamp(1.0, image.height.toDouble())
            .round();

        img.drawRect(
          image,
          x1: left,
          y1: top,
          x2: min(image.width - 1, left + width),
          y2: min(image.height - 1, top + height),
          color: img.ColorRgb8(255, 214, 68),
          thickness: 3,
        );
      }
    }
  }

  void _drawTag(
    img.Image image, {
    required String text,
    required int y,
    required img.ColorRgb8 background,
  }) {
    img.fillRect(
      image,
      x1: 8,
      y1: y,
      x2: 110,
      y2: y + 20,
      color: background,
    );
    img.drawString(
      image,
      text,
      font: img.arial14,
      x: 14,
      y: y + 3,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  List<_BufferedFrame> _uniqueAndSortedFrames(List<_BufferedFrame> frames) {
    frames.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final deduped = <_BufferedFrame>[];
    DateTime? last;
    for (final frame in frames) {
      if (last != null && frame.timestamp == last) {
        continue;
      }
      deduped.add(frame);
      last = frame.timestamp;
    }
    return deduped;
  }

  Duration _estimateFrameInterval(List<_BufferedFrame> frames) {
    if (frames.length < 2) {
      return const Duration(milliseconds: 50);
    }

    var totalMs = 0;
    var deltas = 0;
    for (var i = 1; i < frames.length; i++) {
      final delta = frames[i].timestamp.difference(frames[i - 1].timestamp);
      final ms = delta.inMilliseconds;
      if (ms <= 0) {
        continue;
      }
      totalMs += ms;
      deltas += 1;
    }

    if (deltas == 0) {
      return const Duration(milliseconds: 50);
    }

    return Duration(milliseconds: max(20, totalMs ~/ deltas));
  }

  int _nearestFrameIndex(List<_BufferedFrame> frames, DateTime reference) {
    var bestIndex = 0;
    var bestDiff = frames.first.timestamp.difference(reference).abs();

    for (var i = 1; i < frames.length; i++) {
      final diff = frames[i].timestamp.difference(reference).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  void _pruneOldFrames() {
    if (_frameBuffer.isEmpty) {
      return;
    }

    final cutoff = DateTime.now().subtract(maxBufferDuration);
    _frameBuffer.removeWhere((frame) => frame.timestamp.isBefore(cutoff));
  }
}

class _PendingCapture {
  _PendingCapture({
    required this.frames,
    required this.movementAt,
    required this.captureEndAt,
    required this.motionBounds,
    required this.diffScore,
    required this.overlayData,
    required this.completer,
  });

  final List<_BufferedFrame> frames;
  final DateTime movementAt;
  final DateTime captureEndAt;
  final MotionBounds? motionBounds;
  final double diffScore;
  final ReplayOverlayData? overlayData;
  final Completer<ReplayClip?> completer;
}

class _BufferedFrame {
  _BufferedFrame({
    required this.timestamp,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.yLuma,
    required this.diffScore,
    required this.motionBounds,
    this.uPlane,
    this.vPlane,
    this.uvRowStride,
    this.uvPixelStride,
  });

  final DateTime timestamp;
  final int width;
  final int height;
  final int yRowStride;
  final Uint8List yLuma;
  final Uint8List? uPlane;
  final Uint8List? vPlane;
  final int? uvRowStride;
  final int? uvPixelStride;
  final double diffScore;
  final MotionBounds? motionBounds;

  factory _BufferedFrame.fromCameraImage(
    CameraImage image, {
    required DateTime timestamp,
    required double diffScore,
    MotionBounds? motionBounds,
  }) {
    final y = image.planes.first;
    final hasColor = image.planes.length >= 3;
    final u = hasColor ? image.planes[1] : null;
    final v = hasColor ? image.planes[2] : null;

    return _BufferedFrame(
      timestamp: timestamp,
      width: image.width,
      height: image.height,
      yRowStride: y.bytesPerRow,
      yLuma: Uint8List.fromList(y.bytes),
      uPlane: u == null ? null : Uint8List.fromList(u.bytes),
      vPlane: v == null ? null : Uint8List.fromList(v.bytes),
      uvRowStride: u?.bytesPerRow,
      uvPixelStride: u?.bytesPerPixel,
      diffScore: diffScore,
      motionBounds: motionBounds,
    );
  }

  img.Image toJpegImage({required int maxExportWidth}) {
    final frame = img.Image(width: width, height: height);

    final u = uPlane;
    final v = vPlane;
    final uvRow = uvRowStride;
    final uvPixel = uvPixelStride ?? 1;

    for (var y = 0; y < height; y++) {
      final yOffset = y * yRowStride;
      final uvY = y ~/ 2;
      for (var x = 0; x < width; x++) {
        final yIndex = yOffset + x;
        if (yIndex >= yLuma.length) {
          continue;
        }

        final yy = yLuma[yIndex];

        if (u == null || v == null || uvRow == null) {
          frame.setPixelRgb(x, y, yy, yy, yy);
          continue;
        }

        final uvX = x ~/ 2;
        final uvIndex = uvY * uvRow + uvX * uvPixel;
        if (uvIndex >= u.length || uvIndex >= v.length) {
          frame.setPixelRgb(x, y, yy, yy, yy);
          continue;
        }

        final uu = u[uvIndex];
        final vv = v[uvIndex];

        final c = yy - 16;
        final d = uu - 128;
        final e = vv - 128;

        final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
        final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
        final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
        frame.setPixelRgb(x, y, r, g, b);
      }
    }

    if (frame.width <= maxExportWidth) {
      return frame;
    }

    final resizedHeight = max(1, (frame.height * maxExportWidth) ~/ frame.width);
    return img.copyResize(frame, width: maxExportWidth, height: resizedHeight);
  }
}
