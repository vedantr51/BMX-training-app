import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

/// Processed sensor sample used for motion detection decisions.
class MotionSample {
  final double rawMagnitude;
  final double rawForwardY;
  final double magnitude;
  final double forwardY;

  const MotionSample({
    required this.rawMagnitude,
    required this.rawForwardY,
    required this.magnitude,
    required this.forwardY,
  });
}

/// Provides filtered user-acceleration samples for gate motion detection.
class SensorService {
  static const EventChannel _userAccelEventChannel = EventChannel(
    'dev.fluttercommunity.plus/sensors/user_accel',
  );

  StreamSubscription<dynamic>? _subscription;
  StreamController<MotionSample>? _controller;

  static const int _movingAverageWindow = 3;

  final List<double> _magnitudeWindow = <double>[];
  final List<double> _forwardYWindow = <double>[];

  /// Starts emitting smoothed samples derived from `userAccelerometerEvents`.
  Stream<MotionSample> startListening() {
    _controller ??= StreamController<MotionSample>.broadcast(
      onCancel: stopListening,
    );

    _subscription ??= _userAccelEventChannel.receiveBroadcastStream().listen((
      event,
    ) {
      final values = (event as List<dynamic>).cast<double>();
      final x = values[0];
      final y = values[1];
      final z = values[2];

      final rawMagnitude = sqrt(x * x + y * y + z * z);
      final rawForwardY = y;

      final smoothedMagnitude = _movingAverage(_magnitudeWindow, rawMagnitude);
      final smoothedForwardY = _movingAverage(_forwardYWindow, rawForwardY);

      _controller?.add(
        MotionSample(
          rawMagnitude: rawMagnitude,
          rawForwardY: rawForwardY,
          magnitude: smoothedMagnitude,
          forwardY: smoothedForwardY,
        ),
      );
    });

    return _controller!.stream;
  }

  double _movingAverage(List<double> window, double next) {
    window.add(next);
    if (window.length > _movingAverageWindow) {
      window.removeAt(0);
    }

    final sum = window.fold<double>(0.0, (acc, value) => acc + value);
    return sum / window.length;
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _controller?.close();
    _controller = null;
    _magnitudeWindow.clear();
    _forwardYWindow.clear();
  }
}
