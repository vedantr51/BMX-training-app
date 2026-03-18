import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rider.dart';
import '../models/session_result.dart';
import '../models/sensitivity.dart';
import '../services/audio_service.dart';
import '../services/profile_service.dart';
import '../services/sensor_service.dart';
import '../services/timing_service.dart';
import '../services/websocket_server_service.dart';
import 'result_screen.dart';

class GateScreen extends StatefulWidget {
  final Rider rider;
  final List<SessionResult> sessionRuns;

  const GateScreen({
    super.key,
    required this.rider,
    this.sessionRuns = const [],
  });

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  final TimingService _timingService = TimingService();
  final SensorService _sensorService = SensorService();
  final AudioService _audioService = AudioService();

  GateLight _activeLight = GateLight.off;
  String _statusText = 'Get ready';
  DateTime? _sessionStart;
  DateTime? _firstYellowTime;
  DateTime? _greenTime;
  bool _allowMovement = false;
  bool _movementDetected = false;
  bool _showDebugOverlay = false;
  bool _isCheckingStability = false;
  bool _isGateRunning = false;

  double _lastMagnitude = 0.0;
  double _lastForwardY = 0.0;
  double _lastRawMagnitude = 0.0;
  double _lastRawForwardY = 0.0;
  double _threshold = 0.0;
  double _directionThreshold = 0.25;
  double _confidence = 0.0;
  double _confidenceMin = 1.0;
  bool _usingCalibratedThreshold = false;
  DateTime? _candidateStartTime;
  DateTime? _movementTime;
  double? _reactionMs;
  String? _errorMessage;

  int _countdownValue = 3;
  Timer? _countdownTimer;
  bool _isCountingDown = false;

  StreamSubscription<MotionSample>? _accelSub;
  Timer? _noMovementTimer;
  Timer? _adaptiveRelaxTimer;

  static const _lateThresholdSeconds = 0.35; // seconds
  static const _noMovementTimeout = Duration(seconds: 3);
  static const _minimumTriggerDuration = Duration(milliseconds: 35);
  static const _stabilityDuration = Duration(seconds: 1);
  static const _stabilityMagnitudeThreshold = 0.35;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _accelSub?.cancel();
    _adaptiveRelaxTimer?.cancel();
    _timingService.stopSequence();
    _sensorService.stopListening();
    _audioService.stop();
    super.dispose();
  }

  void _startCountdown() {
    _isCountingDown = true;
    _countdownValue = 3;
    _statusText = 'Get ready';
    _activeLight = GateLight.off;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownValue -= 1;
      });

      if (_countdownValue <= 0) {
        timer.cancel();
        _isCountingDown = false;
        _prepareAndStartSequence();
      }
    });
  }

  Future<void> _prepareAndStartSequence() async {
    setState(() {
      _isCheckingStability = true;
      _statusText = 'Hold phone steady';
      _errorMessage = null;
    });

    final isStable = await _checkDeviceStability();
    if (!mounted) return;

    setState(() {
      _isCheckingStability = false;
    });

    if (!isStable) {
      setState(() {
        _statusText = 'Hold phone steady';
        _errorMessage = 'Hold phone steady';
      });
      return;
    }

    final hasCalibration = Provider.of<ProfileService>(
      context,
      listen: false,
    ).hasCalibration;
    if (!hasCalibration) {
      setState(() {
        _errorMessage = 'Calibration missing. Using default sensitivity.';
      });
    }

    _startSequence();
  }

  Future<bool> _checkDeviceStability() async {
    final completer = Completer<bool>();
    var moved = false;

    _sensorService.stopListening();
    final sub = _sensorService.startListening().listen(
      (sample) {
        if (sample.magnitude > _stabilityMagnitudeThreshold ||
            sample.forwardY.abs() > _stabilityMagnitudeThreshold) {
          moved = true;
        }
      },
      onError: (_) {
        moved = true;
      },
    );

    Timer(_stabilityDuration, () async {
      await sub.cancel();
      _sensorService.stopListening();
      if (!completer.isCompleted) {
        completer.complete(!moved);
      }
    });

    return completer.future;
  }

  void _startSequence() {
    // Reset state so new sessions don't inherit previous values.
    _sessionStart = DateTime.now();
    _firstYellowTime = null;
    _greenTime = null;
    _allowMovement = false;
    _movementDetected = false;
    _movementTime = null;
    _reactionMs = null;
    _candidateStartTime = null;
    _confidence = 0.0;
    _errorMessage = null;
    _isGateRunning = true;

    _audioService.speak('Riders ready');
    Provider.of<WebSocketServerService>(
      context,
      listen: false,
    ).sendGateStarted();

    setState(() {
      _statusText = 'Stay still until green';
      _activeLight = GateLight.red;
      _countdownValue = 0;
    });

    _startMotionMonitoring();

    _timingService.startSequence(
      onUpdate: (light, time) {
        setState(() {
          _activeLight = light;

          switch (light) {
            case GateLight.red:
              _statusText = 'Riders ready';
              break;
            case GateLight.yellow:
              if (_firstYellowTime == null) {
                _firstYellowTime = time;
                _audioService.speak('Watch the gate');
              }
              Provider.of<WebSocketServerService>(
                context,
                listen: false,
              ).sendYellowLight();
              _statusText = 'Watch the gate';
              break;
            case GateLight.green:
              _greenTime = time;
              _allowMovement = true;
              Provider.of<WebSocketServerService>(
                context,
                listen: false,
              ).sendGreenLight();
              _statusText = 'Go!';
              // Start a timeout so we don't wait forever.
              _startNoMovementTimeout();
              break;
            default:
              _statusText = 'Get ready';
          }
        });
      },
      onComplete: () {
        // Sequence complete but rider may have not moved yet.
        // Keep listening until movement or user leaves.
      },
    );
  }

  void _startMotionMonitoring() {
    final profileService = Provider.of<ProfileService>(
      context,
      listen: false,
    );
    final sensitivity = profileService.sensitivity;

    _usingCalibratedThreshold =
        profileService.hasCalibration && profileService.calibratedThreshold != null;
    _threshold = _usingCalibratedThreshold
        ? profileService.calibratedThreshold!
        : sensitivity.accelerationThreshold;
    _directionThreshold = _threshold * (
      _usingCalibratedThreshold ? profileService.forwardRatio : 0.30
    );
    _confidenceMin = _usingCalibratedThreshold
        ? profileService.confidenceMin
        : 1.0;

    // Keep thresholds in a practical range so regular forward pushes register.
    _threshold = _threshold.clamp(0.45, 1.25).toDouble();
    _directionThreshold = _directionThreshold.clamp(0.10, 0.40).toDouble();
    _confidenceMin = min(_confidenceMin, 0.90);

    _accelSub?.cancel();
    _sensorService.stopListening();

    _accelSub = _sensorService.startListening().listen(
      (sample) {
        if (_movementDetected || !_isGateRunning) return;

        _lastMagnitude = sample.magnitude;
        _lastForwardY = sample.forwardY;
        _lastRawMagnitude = sample.rawMagnitude;
        _lastRawForwardY = sample.rawForwardY;

        final safeThreshold = _threshold <= 0 ? 1.0 : _threshold;
        _confidence = sample.rawMagnitude / safeThreshold;
        final forwardAbs = sample.rawForwardY.abs();
        final smoothedForwardAbs = sample.forwardY.abs();

        // Fast path: trigger on raw signal so we don't add noticeable latency.
        final rawForwardTrigger =
          sample.rawMagnitude >= _threshold &&
          forwardAbs >= _directionThreshold;

        // Smoothed path: protects against noisy spikes.
        final smoothedForwardTrigger =
            sample.magnitude >= (_threshold * 0.85) &&
          smoothedForwardAbs >= (_directionThreshold * 0.85);

        // Fallback for opposite phone orientation while still requiring strong Y-axis intent.
        final orientationFallbackTrigger =
            sample.rawMagnitude >= (_threshold * 1.2) &&
          forwardAbs >= (_directionThreshold * 1.2);

        // Extra fallback for realistic, quick forward pushes that may not spike total magnitude.
        final forwardKickTrigger =
          forwardAbs >= (_directionThreshold * 1.15) &&
          sample.rawMagnitude >= (_threshold * 0.65);

        // Keep direction filtering on Y-axis while allowing either phone orientation.
        final directionValid = forwardAbs >= _directionThreshold;
        final passesConfidence = _confidence >= _confidenceMin;
        final triggerCandidate =
          (rawForwardTrigger ||
            smoothedForwardTrigger ||
            orientationFallbackTrigger ||
            forwardKickTrigger) &&
            directionValid &&
            passesConfidence;

        if (!triggerCandidate) {
          _candidateStartTime = null;
          return;
        }

        final now = DateTime.now();

        _candidateStartTime ??= now;
        if (now.difference(_candidateStartTime!) < _minimumTriggerDuration) {
          return;
        }

        _movementTime = now;

        if (!_allowMovement) {
          // Ignore movement before green to keep detection window strict.
          return;
        }

        // Cancel timeout only for valid post-green detections.
        _noMovementTimer?.cancel();
        _adaptiveRelaxTimer?.cancel();

        // Valid movement after green
        final referenceTime = (_greenTime != null && now.isAfter(_greenTime!))
            ? _greenTime!
            : (_firstYellowTime ?? now);
        final reaction = now.difference(referenceTime).inMilliseconds / 1000.0;
        _reactionMs = reaction * 1000.0;

        final startType = reaction > _lateThresholdSeconds
            ? StartType.lateStart
            : StartType.valid;
        final score = _calculateScore(reaction);

        _movementDetected = true;
        _finishSession(
          SessionResult(
            reactionTimeSeconds: reaction,
            score: score,
            startType: startType,
          ),
        );
      },
      onError: (err) {
        setState(() {
          _errorMessage = 'Sensor error: $err';
        });
      },
    );
  }

  void _startNoMovementTimeout() {
    _noMovementTimer?.cancel();
    _adaptiveRelaxTimer?.cancel();

    // If no strong movement is seen shortly after green, relax thresholds slightly.
    _adaptiveRelaxTimer = Timer(const Duration(milliseconds: 1200), () {
      if (_movementDetected || !_allowMovement || !_isGateRunning) {
        return;
      }

      _threshold *= 0.85;
      _directionThreshold *= 0.85;
      if (_confidenceMin > 0.75) {
        _confidenceMin = 0.75;
      }
    });

    _noMovementTimer = Timer(_noMovementTimeout, () {
      if (_movementDetected) return;

      _timingService.stopSequence();
      _sensorService.stopListening();
      _accelSub?.cancel();
      _accelSub = null;
      _adaptiveRelaxTimer?.cancel();
      _adaptiveRelaxTimer = null;
      _isGateRunning = false;
      _allowMovement = false;
      _candidateStartTime = null;

      setState(() {
        _errorMessage = 'No movement detected';
        _statusText = 'Session timed out';
      });
    });
  }

  int _calculateScore(double reactionSeconds) {
    // Score is higher for faster reactions. Typical BMX reaction time range:
    // 0.18 - 0.5 seconds. This mapping makes 0.18s close to 100 and 0.5s close to 0.
    final value = (100 - (reactionSeconds * 170)).round();
    return value.clamp(0, 100);
  }

  void _finishSession(SessionResult result) {
    _noMovementTimer?.cancel();
    _adaptiveRelaxTimer?.cancel();
    _accelSub?.cancel();
    _accelSub = null;
    _sensorService.stopListening();
    _timingService.stopSequence();
    _isGateRunning = false;
    _audioService.speak('Session complete');

    final updatedRuns = [...widget.sessionRuns, result];

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ResultScreen(
          rider: widget.rider,
          result: result,
          sessionRuns: updatedRuns,
        ),
      ),
    );
  }

  Widget _buildLight(GateLight light, Color color) {
    final active = _activeLight == light;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: active ? color : color.withAlpha((0.2 * 255).round()),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12, width: 2),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withAlpha((0.5 * 255).round()),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gate Start'),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: _showDebugOverlay ? 'Hide debug' : 'Show debug',
              icon: Icon(
                _showDebugOverlay
                    ? Icons.bug_report
                    : Icons.bug_report_outlined,
              ),
              onPressed: () {
                setState(() {
                  _showDebugOverlay = !_showDebugOverlay;
                });
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 24.0,
            ),
            child: Column(
              children: [
                Text(
                  'Rider: ${widget.rider.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  _statusText,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildLight(GateLight.red, Colors.red),
                    _buildLight(GateLight.yellow, Colors.yellow),
                    _buildLight(GateLight.green, Colors.green),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'Move forward when you see green. Stay as still as possible until then.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                        _startCountdown();
                      });
                    },
                    child: const Text('Try Again'),
                  ),
                  const SizedBox(height: 12),
                ],
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel Session'),
                ),
              ],
            ),
          ),
          if (_isCountingDown)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((0.7 * 255).round()),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _countdownValue > 0 ? '$_countdownValue' : 'GO!',
                  style: const TextStyle(
                    fontSize: 72,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_isCheckingStability)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((0.7 * 255).round()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Hold phone steady',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          if (kDebugMode)
            if (_showDebugOverlay)
              Positioned(
                left: 12,
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha((0.7 * 255).round()),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Debug',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Magnitude: ${_lastMagnitude.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Forward Y: ${_lastForwardY.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Raw magnitude: ${_lastRawMagnitude.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Raw forward Y: ${_lastRawForwardY.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Threshold: ${_threshold.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Confidence: ${_confidence.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Min confidence: ${_confidenceMin.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Calibrated threshold: $_usingCalibratedThreshold',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Movement detected: $_movementDetected',
                        style: const TextStyle(color: Colors.white),
                      ),
                      if (_sessionStart != null && _greenTime != null)
                        Text(
                          'Green time: ${_greenTime!.difference(_sessionStart!).inMilliseconds}ms',
                          style: const TextStyle(color: Colors.white),
                        ),
                      if (_sessionStart != null && _movementTime != null)
                        Text(
                          'Movement: ${_movementTime!.difference(_sessionStart!).inMilliseconds}ms',
                          style: const TextStyle(color: Colors.white),
                        ),
                      if (_reactionMs != null)
                        Text(
                          'Reaction: ${_reactionMs!.toStringAsFixed(0)}ms',
                          style: const TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
