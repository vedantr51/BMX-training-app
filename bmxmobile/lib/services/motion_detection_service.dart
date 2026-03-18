import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

/// A simple motion-detection service that uses the device's user accel data.
///
/// This uses `userAccelerometerEvents` instead of `accelerometerEvents` so that
/// gravity is already removed by the platform. The service detects a single
/// motion event then stops listening.
class MotionDetectionService {
  static const EventChannel _userAccelEventChannel = EventChannel(
    'dev.fluttercommunity.plus/sensors/user_accel',
  );

  StreamSubscription<dynamic>? _subscription;

  static const int _windowSize = 3;
  final List<double> _magnitudeWindow = <double>[];
  final List<double> _forwardWindow = <double>[];
  bool _hasTriggered = false;

  /// Starts listening for movement and calls [onMovementDetected] once when
  /// the magnitude crosses a dynamic threshold.
  ///
  /// This is based on the _difference_ from a running baseline magnitude, which
  /// helps ignore constant orientation/gravity and focus on **new motion**.
  ///
  /// [threshold] is the additional magnitude above baseline required to trigger.
  /// Typical values are 0.8–1.5.
  void startListening({
    required double threshold,
    required void Function(double magnitude, DateTime time) onMovementDetected,
    void Function(Object error)? onError,
  }) {
    stopListening();

    _hasTriggered = false;
    _magnitudeWindow.clear();
    _forwardWindow.clear();
    final forwardThreshold = threshold * 0.35;

    _subscription = _userAccelEventChannel.receiveBroadcastStream().listen(
      (event) {
        if (_hasTriggered) return;

        final values = (event as List<dynamic>).cast<double>();
        final x = values[0];
        final y = values[1];
        final z = values[2];

        final rawMagnitude = sqrt(x * x + y * y + z * z);

        final smoothedMagnitude = _movingAverage(
          _magnitudeWindow,
          rawMagnitude,
        );
        final smoothedForwardY = _movingAverage(_forwardWindow, y);

        final rawForwardTrigger =
            rawMagnitude >= threshold && y >= forwardThreshold;
        final smoothedForwardTrigger =
            smoothedMagnitude >= (threshold * 0.85) &&
            smoothedForwardY >= (forwardThreshold * 0.85);
        final orientationFallbackTrigger =
            rawMagnitude >= (threshold * 1.2) &&
            y.abs() >= (forwardThreshold * 1.2);

        if (rawForwardTrigger ||
            smoothedForwardTrigger ||
            orientationFallbackTrigger) {
          _hasTriggered = true;
          stopListening();
          onMovementDetected(rawMagnitude, DateTime.now());
        }
      },
      onError: (error) {
        onError?.call(error);
      },
      cancelOnError: false,
    );
  }

  double _movingAverage(List<double> window, double next) {
    window.add(next);
    if (window.length > _windowSize) {
      window.removeAt(0);
    }

    final sum = window.fold<double>(0.0, (acc, value) => acc + value);
    return sum / window.length;
  }

  /// Stops listening for motion.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _magnitudeWindow.clear();
    _forwardWindow.clear();
    _hasTriggered = false;
  }
}
