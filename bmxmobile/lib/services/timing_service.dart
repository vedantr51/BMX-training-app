import 'dart:async';
import 'dart:math';

/// Lights used for the gate sequence.
enum GateLight { off, red, yellow, green }

/// Provides a gate timing sequence (red → yellow → yellow → green).
///
/// The gate sequence is used to determine the "first yellow" timestamp which
/// serves as the reference for rider reaction time.
class TimingService {
  Timer? _stepTimer;
  Timer? _delayTimer;
  final Random _random = Random();

  /// Starts the gate sequence.
  ///
  /// [onUpdate] is called for each light change with the active light and the
  /// exact timestamp. The sequence is:
  ///   1) Red
  ///   2) Yellow (first)
  ///   3) Yellow (second)
  ///   4) Green
  ///
  /// Each step is held for ~1 second.
  void startSequence({
    required void Function(GateLight light, DateTime time) onUpdate,
    required void Function() onComplete,
  }) {
    const stepDuration = Duration(milliseconds: 1000);

    _stepTimer?.cancel();
    _delayTimer?.cancel();

    var step = 0;

    void tick(Timer timer) {
      final now = DateTime.now();
      switch (step) {
        case 0:
          onUpdate(GateLight.red, now);
          break;
        case 1:
          onUpdate(GateLight.yellow, now);
          break;
        case 2:
          onUpdate(GateLight.yellow, now);
          break;
        case 3:
          onUpdate(GateLight.green, now);
          break;
        default:
          timer.cancel();
          onComplete();
          return;
      }

      step += 1;
    }

    // Start with red immediately.
    final now = DateTime.now();
    onUpdate(GateLight.red, now);

    // Add random delay before first yellow (1-3 seconds).
    final randomDelayMs = 1000 + _random.nextInt(2001);
    _delayTimer = Timer(Duration(milliseconds: randomDelayMs), () {
      final firstYellowTime = DateTime.now();
      onUpdate(GateLight.yellow, firstYellowTime);
      step = 2;

      _stepTimer = Timer.periodic(stepDuration, tick);
    });
  }

  void stopSequence() {
    _stepTimer?.cancel();
    _stepTimer = null;
    _delayTimer?.cancel();
    _delayTimer = null;
  }
}
