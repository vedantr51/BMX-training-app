import 'dart:async';
import 'dart:math';

import 'sensor_service.dart';

class CalibrationResult {
  const CalibrationResult({
    required this.noiseLevel,
    required this.threshold,
    required this.samples,
    required this.confidenceMin,
    required this.forwardRatio,
  });

  final double noiseLevel;
  final double threshold;
  final List<double> samples;
  final double confidenceMin;
  final double forwardRatio;
}

class CalibrationService {
  CalibrationService({SensorService? sensorService})
    : _sensorService = sensorService ?? SensorService();

  final SensorService _sensorService;

  Future<CalibrationResult> runCalibration({
    Duration baselineDuration = const Duration(seconds: 1),
    int pushSampleCount = 3,
  }) async {
    final noiseLevel = await measureBaselineNoise(duration: baselineDuration);
    final samples = await collectForwardPushSamples(
      noiseLevel: noiseLevel,
      sampleCount: pushSampleCount,
    );

    final averagePush =
        samples.fold<double>(0.0, (sum, value) => sum + value) / samples.length;
    final margin = max(0.20, noiseLevel * 0.6);
    final threshold = max(noiseLevel + margin, averagePush * 0.50);

    return CalibrationResult(
      noiseLevel: noiseLevel,
      threshold: threshold,
      samples: samples,
      confidenceMin: 1.0,
      forwardRatio: 0.30,
    );
  }

  Future<double> measureBaselineNoise({
    Duration duration = const Duration(seconds: 1),
  }) async {
    final samples = <double>[];
    final completer = Completer<double>();

    late final StreamSubscription<MotionSample> sub;
    sub = _sensorService.startListening().listen(
      (sample) {
        samples.add(sample.magnitude);
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    Timer(duration, () async {
      await sub.cancel();
      _sensorService.stopListening();
      if (samples.isEmpty) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('No sensor samples captured during baseline step.'),
          );
        }
        return;
      }

      final avg = samples.fold<double>(0.0, (sum, value) => sum + value) /
          samples.length;
      if (!completer.isCompleted) {
        completer.complete(avg);
      }
    });

    return completer.future;
  }

  Future<List<double>> collectForwardPushSamples({
    required double noiseLevel,
    int sampleCount = 3,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final samples = <double>[];
    final completer = Completer<List<double>>();

    final triggerMagnitude = noiseLevel + 0.25;
    final minForward = max(0.15, triggerMagnitude * 0.2);

    var inPush = false;
    var currentPeak = 0.0;
    DateTime? lastAcceptedAt;

    late final StreamSubscription<MotionSample> sub;
    Timer? timeoutTimer;

    Future<void> completeWithError(Object error) async {
      await sub.cancel();
      timeoutTimer?.cancel();
      _sensorService.stopListening();
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    Future<void> completeWithSamples() async {
      await sub.cancel();
      timeoutTimer?.cancel();
      _sensorService.stopListening();
      if (!completer.isCompleted) {
        completer.complete(List<double>.from(samples));
      }
    }

    sub = _sensorService.startListening().listen(
      (sample) {
        final now = DateTime.now();
        final forward = sample.rawForwardY >= minForward;
        final enoughMagnitude = sample.rawMagnitude >= triggerMagnitude;

        if (forward && enoughMagnitude) {
          inPush = true;
          currentPeak = max(currentPeak, sample.rawMagnitude);
          return;
        }

        if (!inPush) {
          return;
        }

        final acceptedRecently =
            lastAcceptedAt != null &&
            now.difference(lastAcceptedAt!).inMilliseconds < 250;

        if (!acceptedRecently && currentPeak >= triggerMagnitude) {
          samples.add(currentPeak);
          lastAcceptedAt = now;
        }

        inPush = false;
        currentPeak = 0.0;

        if (samples.length >= sampleCount) {
          completeWithSamples();
        }
      },
      onError: completeWithError,
    );

    timeoutTimer = Timer(timeout, () {
      if (samples.length >= 2) {
        completeWithSamples();
      } else {
        completeWithError(
          StateError('Not enough forward pushes detected. Try again.'),
        );
      }
    });

    return completer.future;
  }

  void dispose() {
    _sensorService.stopListening();
  }
}
