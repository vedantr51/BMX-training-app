enum MotionSensitivity { low, medium, high }

extension MotionSensitivityExtension on MotionSensitivity {
  /// Returns the acceleration threshold (m/s²) used to detect a forward motion.
  double get accelerationThreshold {
    // Threshold that is compared against (|linear acceleration|).
    // Use these values to adjust how easily movement triggers a start.
    switch (this) {
      case MotionSensitivity.low:
        return 2.0; // ignores most noise
      case MotionSensitivity.medium:
        return 1.5; // normal behavior
      case MotionSensitivity.high:
        return 1.0; // triggers easily
    }
  }

  String get label {
    switch (this) {
      case MotionSensitivity.low:
        return 'Low';
      case MotionSensitivity.medium:
        return 'Medium';
      case MotionSensitivity.high:
        return 'High';
    }
  }
}
