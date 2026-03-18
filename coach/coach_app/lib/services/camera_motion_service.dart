import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/replay_clip.dart';
import '../models/replay_overlay_data.dart';
import '../models/run_analysis.dart';
import 'replay_buffer_service.dart';

enum CameraMotionStatus {
  idle,
  unavailable,
  ready,
  detecting,
  movementDetected,
  noMovement,
  error,
}

class CameraMotionInsight {
  const CameraMotionInsight({
    required this.greenLightAt,
    required this.movementDetectedAt,
    required this.diffScore,
    required this.confidence,
    this.motionBounds,
    this.replayClip,
  });

  final DateTime greenLightAt;
  final DateTime movementDetectedAt;
  final double diffScore;
  final double confidence;
  final MotionBounds? motionBounds;
  final ReplayClip? replayClip;
}

class CameraMotionService extends ChangeNotifier {
  CameraMotionService({ReplayBufferService? replayBufferService})
    : _replayBufferService = replayBufferService ?? ReplayBufferService();

  final ReplayBufferService _replayBufferService;

  CameraController? _controller;
  CameraMotionStatus _status = CameraMotionStatus.idle;
  String? _lastError;
  double _lastDiffScore = 0.0;

  Uint8List? _previousFrame;
  int _previousRowStride = 0;
  int _previousWidth = 0;
  int _previousHeight = 0;

  Timer? _detectionWindowTimer;
  Timer? _postCaptureTimer;
  bool _isProcessingFrame = false;
  bool _isEndingDetection = false;
  bool _detectionArmed = false;
  bool _movementLocked = false;
  int _consecutiveMotionFrames = 0;

  DateTime? _gateStartedAt;
  DateTime? _yellowLightAt;
  DateTime? _greenLightAt;
  DateTime? _movementDetectedAt;
  MotionBounds? _movementBounds;
  double _movementDiffScore = 0.0;
  double _movementConfidence = 0.0;
  ReplayClip? _latestReplayClip;

  CameraController? get controller => _controller;
  CameraMotionStatus get status => _status;
  String? get lastError => _lastError;
  double get lastDiffScore => _lastDiffScore;
  bool get hasPreview => _controller?.value.isInitialized ?? false;

  ReplayClip? get latestReplayClip => _latestReplayClip;
  String? get greenFramePath => _latestReplayClip?.greenFramePath;
  String? get movementFramePath => _latestReplayClip?.movementFramePath;
  DateTime? get greenLightAt => _greenLightAt;
  DateTime? get movementDetectedAt => _movementDetectedAt;
  MotionBounds? get movementBounds => _movementBounds;
  double get movementDiffScore => _movementDiffScore;
  double get movementConfidence => _movementConfidence;
  DateTime? get gateStartedAt => _gateStartedAt;
  DateTime? get yellowLightAt => _yellowLightAt;

  CameraMotionInsight? get latestInsight {
    final green = _greenLightAt;
    final movement = _movementDetectedAt;
    if (green == null || movement == null) {
      return null;
    }

    return CameraMotionInsight(
      greenLightAt: green,
      movementDetectedAt: movement,
      diffScore: _movementDiffScore,
      confidence: _movementConfidence,
      motionBounds: _movementBounds,
      replayClip: _latestReplayClip,
    );
  }

  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setStatus(CameraMotionStatus.unavailable);
        return;
      }

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      await _controller?.dispose();
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      _setStatus(CameraMotionStatus.ready);
    } catch (error) {
      _lastError = 'Camera unavailable: $error';
      _setStatus(CameraMotionStatus.error);
    }
  }

  Future<void> startDetectionWindow({
    Duration window = const Duration(seconds: 3),
  }) async {
    await startPreStartBuffering(window: window);
    markGreenLight();
  }

  Future<void> startPreStartBuffering({
    Duration window = const Duration(seconds: 10),
  }) async {
    if (_controller == null || !(_controller!.value.isInitialized)) {
      await initialize();
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await stopDetection(setIdle: false);

    _resetDetectionState();
    _greenLightAt = null;
    _replayBufferService.reset();

    _setStatus(CameraMotionStatus.detecting);

    _detectionWindowTimer?.cancel();
    _detectionWindowTimer = Timer(window, () {
      if (_status == CameraMotionStatus.detecting) {
        _endDetection(CameraMotionStatus.noMovement);
      }
    });

    try {
      if (controller.value.isPreviewPaused) {
        await controller.resumePreview();
      }
      await controller.startImageStream(_processFrame);
    } catch (error) {
      _lastError = 'Failed to start camera stream: $error';
      _setStatus(CameraMotionStatus.error);
    }
  }

  void markGateStarted({DateTime? timestamp}) {
    _gateStartedAt = timestamp ?? DateTime.now();
    notifyListeners();
  }

  void markYellowLight({DateTime? timestamp}) {
    _yellowLightAt = timestamp ?? DateTime.now();
    notifyListeners();
  }

  void markGreenLight({DateTime? timestamp}) {
    _greenLightAt = timestamp ?? DateTime.now();
    _detectionArmed = true;
    _replayBufferService.markGreenLight(timestamp: _greenLightAt);
    notifyListeners();
  }

  Future<CameraMotionInsight?> finalizeReplayFromSensorReaction({
    required double reactionTimeSeconds,
    String? rider,
    int? score,
    String? startType,
  }) async {
    final green = _greenLightAt;
    if (green == null) {
      return latestInsight;
    }

    final reactionMs = max(0, (reactionTimeSeconds * 1000).round());
    final movementAt = green.add(Duration(milliseconds: reactionMs));
    final overlayData = ReplayOverlayData(
      gateStartedAt: _gateStartedAt,
      yellowLightAt: _yellowLightAt,
      greenLightAt: _greenLightAt,
      movementAt: movementAt,
      rider: rider,
      reactionTimeSeconds: reactionTimeSeconds,
      score: score,
      startType: startType,
    );

    final replay = await _replayBufferService.beginMovementCapture(
      movementAt: movementAt,
      motionBounds: _movementBounds,
      diffScore: _movementDiffScore,
      overlayData: overlayData,
    );

    final resolvedReplay = replay ??
        await _replayBufferService.exportBufferedReplay(
          movementAt: movementAt,
          motionBounds: _movementBounds,
          diffScore: _movementDiffScore,
          overlayData: overlayData,
        );

    _movementDetectedAt ??= movementAt;
    _movementConfidence = max(_movementConfidence, 0.35);
    if (resolvedReplay != null) {
      _latestReplayClip = resolvedReplay;
    }

    notifyListeners();
    return latestInsight;
  }

  Future<void> stopDetection({bool setIdle = true}) async {
    _detectionWindowTimer?.cancel();
    _detectionWindowTimer = null;
    _postCaptureTimer?.cancel();
    _postCaptureTimer = null;
    _replayBufferService.stopPendingCapture();
    _detectionArmed = false;
    _isEndingDetection = false;

    await _stopImageStream();
    _resetFrameHistory();

    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      try {
        if (controller.value.isPreviewPaused) {
          await controller.resumePreview();
        }
      } catch (_) {
        // Keep preview operations best-effort.
      }
    }

    if (setIdle && _status != CameraMotionStatus.unavailable) {
      _setStatus(CameraMotionStatus.idle);
    }
  }

  Future<void> releaseCamera() async {
    _detectionWindowTimer?.cancel();
    _detectionWindowTimer = null;
    _postCaptureTimer?.cancel();
    _postCaptureTimer = null;
    _isEndingDetection = false;

    _replayBufferService.reset();
    await _stopImageStream();
    await _controller?.dispose();
    _controller = null;

    _resetDetectionState();

    if (_status != CameraMotionStatus.unavailable) {
      _setStatus(CameraMotionStatus.idle);
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  void _processFrame(CameraImage image) {
    if ((_status != CameraMotionStatus.detecting &&
            _status != CameraMotionStatus.movementDetected) ||
        _isProcessingFrame) {
      return;
    }

    _isProcessingFrame = true;

    try {
      if (image.planes.isEmpty) {
        return;
      }

      final yPlane = image.planes.first;
      final current = yPlane.bytes;
      final now = DateTime.now();

      final previous = _previousFrame;
      if (previous == null ||
          _previousWidth != image.width ||
          _previousHeight != image.height ||
          _previousRowStride != yPlane.bytesPerRow) {
        _previousFrame = Uint8List.fromList(current);
        _previousWidth = image.width;
        _previousHeight = image.height;
        _previousRowStride = yPlane.bytesPerRow;

        _replayBufferService.addFrame(
          image,
          timestamp: now,
          diffScore: 0.0,
        );
        return;
      }

      final stats = _calculateDiffStats(
        previous,
        current,
        width: image.width,
        height: image.height,
        rowStride: yPlane.bytesPerRow,
      );

      _lastDiffScore = stats.score;
      _previousFrame = Uint8List.fromList(current);
      _previousWidth = image.width;
      _previousHeight = image.height;
      _previousRowStride = yPlane.bytesPerRow;

      _replayBufferService.addFrame(
        image,
        timestamp: now,
        diffScore: stats.score,
        motionBounds: stats.bounds,
      );

      if (!_detectionArmed || _movementLocked) {
        return;
      }

      if (stats.score > 0.085) {
        _consecutiveMotionFrames += 1;
      } else {
        _consecutiveMotionFrames = 0;
      }

      if (_consecutiveMotionFrames >= 2) {
        _onMovementDetected(now, stats);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  _FrameDiffStats _calculateDiffStats(
    Uint8List previous,
    Uint8List current, {
    required int width,
    required int height,
    required int rowStride,
  }) {
    final maxSamples = min(previous.length, current.length);
    if (maxSamples == 0 || width <= 0 || height <= 0) {
      return const _FrameDiffStats(score: 0.0, bounds: null, confidence: 0.0);
    }

    const stride = 4;
    const pixelThreshold = 26;

    var totalDelta = 0.0;
    var sampleCount = 0;
    var activePixels = 0;

    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;

    for (var y = 0; y < height; y += stride) {
      final rowOffset = y * rowStride;
      for (var x = 0; x < width; x += stride) {
        final index = rowOffset + x;
        if (index >= maxSamples) {
          continue;
        }

        final delta = (current[index] - previous[index]).abs();
        totalDelta += delta;
        sampleCount += 1;

        if (delta < pixelThreshold) {
          continue;
        }

        activePixels += 1;
        if (x < minX) {
          minX = x;
        }
        if (x > maxX) {
          maxX = x;
        }
        if (y < minY) {
          minY = y;
        }
        if (y > maxY) {
          maxY = y;
        }
      }
    }

    if (sampleCount == 0) {
      return const _FrameDiffStats(score: 0.0, bounds: null, confidence: 0.0);
    }

    final score = (totalDelta / sampleCount) / 255.0;
    if (activePixels < 12 || minX >= maxX || minY >= maxY) {
      return _FrameDiffStats(score: score, bounds: null, confidence: 0.0);
    }

    final coverage = activePixels / sampleCount;
    final confidence = (coverage * 2.2).clamp(0.0, 1.0);

    final bounds = MotionBounds(
      left: (minX / width).clamp(0.0, 1.0),
      top: (minY / height).clamp(0.0, 1.0),
      width: ((maxX - minX) / width).clamp(0.02, 1.0),
      height: ((maxY - minY) / height).clamp(0.02, 1.0),
    );

    return _FrameDiffStats(score: score, bounds: bounds, confidence: confidence);
  }

  void _onMovementDetected(DateTime detectedAt, _FrameDiffStats stats) {
    _movementLocked = true;
    _movementDetectedAt = detectedAt;
    _movementBounds = stats.bounds;
    _movementDiffScore = stats.score;
    _movementConfidence = stats.confidence;
    _setStatus(CameraMotionStatus.movementDetected);

    final replayFuture = _replayBufferService.beginMovementCapture(
      movementAt: detectedAt,
      motionBounds: stats.bounds,
      diffScore: stats.score,
      overlayData: ReplayOverlayData(
        gateStartedAt: _gateStartedAt,
        yellowLightAt: _yellowLightAt,
        greenLightAt: _greenLightAt,
        movementAt: detectedAt,
      ),
    );

    _postCaptureTimer?.cancel();
    _postCaptureTimer = Timer(
      _replayBufferService.postBufferDuration +
          const Duration(milliseconds: 120),
      () async {
        final clip = await replayFuture;
        _latestReplayClip = clip;
        notifyListeners();
        _endDetection(CameraMotionStatus.movementDetected);
      },
    );
  }

  void _endDetection(CameraMotionStatus finalStatus) {
    if (_isEndingDetection) {
      return;
    }
    _isEndingDetection = true;

    _detectionWindowTimer?.cancel();
    _detectionWindowTimer = null;
    _postCaptureTimer?.cancel();
    _postCaptureTimer = null;

    _setStatus(finalStatus);

    scheduleMicrotask(() async {
      await _stopImageStream();
      _resetFrameHistory();

      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        try {
          if (controller.value.isPreviewPaused) {
            await controller.resumePreview();
          }
        } catch (_) {
          // Keep preview best-effort only.
        }
      }

      _isEndingDetection = false;
    });
  }

  void _resetFrameHistory() {
    _previousFrame = null;
    _previousRowStride = 0;
    _previousWidth = 0;
    _previousHeight = 0;
    _consecutiveMotionFrames = 0;
  }

  void _resetDetectionState() {
    _lastDiffScore = 0.0;
    _lastError = null;
    _detectionArmed = false;
    _movementLocked = false;
    _gateStartedAt = null;
    _yellowLightAt = null;
    _greenLightAt = null;
    _movementDetectedAt = null;
    _movementBounds = null;
    _movementDiffScore = 0.0;
    _movementConfidence = 0.0;
    _latestReplayClip = null;
    _resetFrameHistory();
  }

  void _setStatus(CameraMotionStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _detectionWindowTimer?.cancel();
    _postCaptureTimer?.cancel();
    _replayBufferService.reset();
    unawaited(_stopImageStream());
    unawaited(_controller?.dispose());
    super.dispose();
  }
}

class _FrameDiffStats {
  const _FrameDiffStats({
    required this.score,
    required this.bounds,
    required this.confidence,
  });

  final double score;
  final MotionBounds? bounds;
  final double confidence;
}
