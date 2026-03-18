import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/replay_clip.dart';
import '../models/run_analysis.dart';
import '../models/run_result.dart';
import 'analysis_service.dart';
import 'camera_motion_service.dart';
import 'websocket_service.dart';

class SessionManager extends ChangeNotifier {
  SessionManager(
    this._webSocketService, {
    CameraMotionService? cameraMotionService,
    AnalysisService? analysisService,
  }) : _cameraMotionService = cameraMotionService ?? CameraMotionService(),
       _analysisService = analysisService ?? AnalysisService() {
    _messageSubscription = _webSocketService.messages.listen(_handleMessage);
    _statusSubscription =
        _webSocketService.statusUpdates.listen(_handleStatusUpdate);
    _cameraMotionService.addListener(_handleCameraStatusChanged);
    unawaited(_cameraMotionService.initialize());
  }

  final WebSocketService _webSocketService;
  final CameraMotionService _cameraMotionService;
  final AnalysisService _analysisService;

  final List<RunResult> _rawRuns = <RunResult>[];
  RunResult? _latestRun;
  RunAnalysis? _selectedRun;

  String _liveStateLabel = 'Waiting for gate';
  bool _detectionWindowActive = false;
  DateTime? _lastEventAt;

  SocketConnectionStatus _connectionStatus = SocketConnectionStatus.disconnected;
  String? _lastError;
  String? _currentEndpoint;

  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<ConnectionStateUpdate>? _statusSubscription;

  List<RunResult> get runs => List.unmodifiable(_rawRuns);
  RunResult? get latestRun => _latestRun;
  List<RunAnalysis> get analyzedRuns => _analysisService.recentRuns;
  RunAnalysis? get selectedRun => _selectedRun ?? (_analysisService.recentRuns.isEmpty
      ? null
      : _analysisService.recentRuns.first);

  String get liveStateLabel => _liveStateLabel;
  bool get detectionWindowActive => _detectionWindowActive;
  DateTime? get lastEventAt => _lastEventAt;
  SocketConnectionStatus get connectionStatus => _connectionStatus;
  String? get currentEndpoint => _currentEndpoint;
  String? get lastError => _lastError;

  CameraController? get cameraController => _cameraMotionService.controller;
  bool get hasCameraPreview => _cameraMotionService.hasPreview;
  double get cameraDiffScore => _cameraMotionService.lastDiffScore;
  ReplayClip? get latestReplayClip => _cameraMotionService.latestReplayClip;
  String? get greenFramePath => _cameraMotionService.greenFramePath;
  String? get movementFramePath => _cameraMotionService.movementFramePath;

  String get cameraStatusLabel {
    switch (_cameraMotionService.status) {
      case CameraMotionStatus.detecting:
        return _cameraMotionService.greenLightAt == null
            ? 'Buffering from red/yellow'
            : 'Detecting after green';
      case CameraMotionStatus.movementDetected:
        return 'Movement captured';
      case CameraMotionStatus.noMovement:
        return 'No movement in window';
      case CameraMotionStatus.error:
        return _cameraMotionService.lastError ?? 'Camera error';
      case CameraMotionStatus.unavailable:
        return 'Camera unavailable';
      case CameraMotionStatus.ready:
      case CameraMotionStatus.idle:
        return 'Idle';
    }
  }

  int get totalRuns => _analysisService.recentRuns.length;

  double get bestTime => _analysisService.summary.bestReaction;
  double get averageTime => _analysisService.summary.averageReaction;
  double get consistency => _analysisService.summary.consistency;

  void selectAnalyzedRun(String id) {
    final run = _analysisService.recentRuns.where((item) => item.id == id);
    if (run.isEmpty) {
      return;
    }
    _selectedRun = run.first;
    notifyListeners();
  }

  Future<void> connectToHost(String hostInput) async {
    final endpoint = _normalizeEndpoint(hostInput);
    if (endpoint == null) {
      _lastError = 'Please enter a valid IP or ws:// endpoint.';
      notifyListeners();
      return;
    }

    _lastError = null;
    _currentEndpoint = endpoint;
    notifyListeners();

    await _webSocketService.connect(endpoint);
  }

  Future<void> disconnect() async {
    await _cameraMotionService.stopDetection();
    await _webSocketService.disconnect();
  }

  Future<void> prepareForQrScanner() async {
    await _cameraMotionService.releaseCamera();
  }

  Future<void> restoreCameraAfterQrScanner() async {
    await _cameraMotionService.initialize();
  }

  void _handleMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _setError('Received invalid data format.');
        return;
      }

      final messageType = (decoded['type'] ?? decoded['event'])?.toString();
      if (messageType == null || messageType.isEmpty) {
        _setError('Received invalid data: missing event type.');
        return;
      }

      _lastEventAt = _extractTimestamp(decoded);

      switch (messageType) {
        case 'gate_started':
          _detectionWindowActive = true;
          _liveStateLabel = 'Gate started: buffering replay from red phase';
          _lastError = null;
          unawaited(() async {
            await _cameraMotionService.startPreStartBuffering(
              window: const Duration(seconds: 10),
            );
            _cameraMotionService.markGateStarted(timestamp: _lastEventAt);
          }());
          notifyListeners();
          return;
        case 'yellow_light':
          _liveStateLabel = 'Yellow light: buffering active';
          _lastError = null;
          _cameraMotionService.markYellowLight(timestamp: _lastEventAt);
          notifyListeners();
          return;
        case 'green_light':
          _onGreenLight();
          return;
        case 'run_result':
          unawaited(_handleRunResult(decoded));
          return;
        default:
          _setError('Unhandled event type: $messageType');
          return;
      }
    } catch (_) {
      _setError('Received invalid JSON payload.');
    }
  }

  Future<void> _handleRunResult(Map<String, dynamic> decoded) async {
    final result = _tryParseRunResult(decoded);
    if (result == null) {
      return;
    }

    _detectionWindowActive = false;
    _liveStateLabel = 'Run result received, finalizing replay';
    _lastError = null;

    _latestRun = result;
    _rawRuns.insert(0, result);
    if (_rawRuns.length > 20) {
      _rawRuns.removeRange(20, _rawRuns.length);
    }

    final insight = await _waitForReplayInsight(
      reactionTimeSeconds: result.reactionTime,
      rider: result.rider,
      score: result.score,
      startType: result.startType,
    );
    final analyzed = _analysisService.recordRun(
      result: result,
      replayClip: insight?.replayClip,
      confidence: insight?.confidence ?? 0.0,
      movementDiffScore: insight?.diffScore ?? 0.0,
      motionBounds: insight?.motionBounds,
      greenLightAt: insight?.greenLightAt,
      movementDetectedAt: insight?.movementDetectedAt,
    );

    _selectedRun = analyzed;
    _liveStateLabel = analyzed.replayClip == null
        ? 'Run saved (camera replay unavailable)'
        : 'Run saved with replay';
    notifyListeners();
  }

  Future<CameraMotionInsight?> _waitForReplayInsight({
    required double reactionTimeSeconds,
    required String rider,
    required int score,
    required String startType,
  }) async {
    final initialInsight = _cameraMotionService.latestInsight;
    if (initialInsight?.replayClip != null) {
      return initialInsight;
    }

    final deadline = DateTime.now().add(const Duration(milliseconds: 2200));
    CameraMotionInsight? latestInsight = initialInsight;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      latestInsight = _cameraMotionService.latestInsight;
      if (latestInsight == null) {
        break;
      }

      if (latestInsight.replayClip != null) {
        return latestInsight;
      }
    }

    final sensorFinalized = await _cameraMotionService
        .finalizeReplayFromSensorReaction(
          reactionTimeSeconds: reactionTimeSeconds,
          rider: rider,
          score: score,
          startType: startType,
        );
    if (sensorFinalized?.replayClip != null) {
      return sensorFinalized;
    }

    return latestInsight;
  }

  void _onGreenLight() {
    _detectionWindowActive = true;
    _liveStateLabel = 'Green light: motion window active';
    _lastError = null;

    if (_cameraMotionService.status == CameraMotionStatus.detecting) {
      _cameraMotionService.markGreenLight(timestamp: _lastEventAt);
    } else {
      unawaited(_cameraMotionService.startDetectionWindow());
    }
    notifyListeners();
  }

  RunResult? _tryParseRunResult(Map<String, dynamic> json) {
    final rider = (json['rider'] ?? '').toString().trim();
    final reactionTime = _toDouble(json['reaction_time']);
    final score = _toInt(json['score']);
    if (rider.isEmpty || reactionTime == null || reactionTime < 0 || score == null) {
      _setError('Received invalid run_result data.');
      return null;
    }

    try {
      return RunResult.fromJson(json);
    } catch (_) {
      _setError('Failed to parse run_result payload.');
      return null;
    }
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  int? _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime _extractTimestamp(Map<String, dynamic> json) {
    final raw = json['timestamp'];
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    if (raw is num) {
      final value = raw.toInt();
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return DateTime.now();
  }

  void _setError(String message) {
    _lastError = message;
    _liveStateLabel = message;
    notifyListeners();
  }

  void _handleStatusUpdate(ConnectionStateUpdate update) {
    _connectionStatus = update.status;

    if (update.status == SocketConnectionStatus.reconnecting) {
      _liveStateLabel = 'Reconnecting...';
    }
    if (update.status == SocketConnectionStatus.disconnected) {
      _liveStateLabel = 'Disconnected';
      _detectionWindowActive = false;
      unawaited(_cameraMotionService.stopDetection());
    }

    if (update.errorMessage != null && update.errorMessage!.isNotEmpty) {
      _lastError = update.errorMessage;
    }
    notifyListeners();
  }

  void _handleCameraStatusChanged() {
    final status = _cameraMotionService.status;
    if (status == CameraMotionStatus.noMovement ||
        status == CameraMotionStatus.movementDetected) {
      _detectionWindowActive = false;
    }
    notifyListeners();
  }

  String? _normalizeEndpoint(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      return null;
    }

    if (value.startsWith('http://')) {
      return 'ws://${value.substring(7)}';
    }
    if (value.startsWith('https://')) {
      return 'wss://${value.substring(8)}';
    }

    if (value.startsWith('ws://') || value.startsWith('wss://')) {
      return value;
    }

    final slashIndex = value.indexOf('/');
    final hostPort = slashIndex == -1 ? value : value.substring(0, slashIndex);
    final path = slashIndex == -1 ? '' : value.substring(slashIndex);

    if (hostPort.isEmpty) {
      return null;
    }

    final hasPort = hostPort.contains(':');
    final normalizedHost = hasPort ? hostPort : '$hostPort:8080';
    return 'ws://$normalizedHost$path';
  }

  @override
  void dispose() {
    _cameraMotionService.removeListener(_handleCameraStatusChanged);
    _cameraMotionService.dispose();
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _webSocketService.dispose();
    super.dispose();
  }
}
