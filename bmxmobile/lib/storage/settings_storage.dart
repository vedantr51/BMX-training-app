import 'package:hive/hive.dart';

/// Stores basic application settings such as selected rider and calibration.
class SettingsStorage {
  static const _boxName = 'settingsBox';

  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  static Box get _box => Hive.box(_boxName);

  static String? get selectedRiderId => _box.get('selectedRiderId') as String?;

  static Future<void> setSelectedRiderId(String id) async {
    await _box.put('selectedRiderId', id);
  }

  static String get motionSensitivityKey => 'motionSensitivity';
  static String get defaultSensitivity => 'medium';
  static String get calibrationThresholdKey => 'calibrationThreshold';
  static String get calibrationNoiseLevelKey => 'calibrationNoiseLevel';
  static String get calibrationConfidenceMinKey => 'calibrationConfidenceMin';
  static String get calibrationForwardRatioKey => 'calibrationForwardRatio';
  static String get hasCalibrationKey => 'hasCalibration';

  static String get motionSensitivity {
    return _box.get(motionSensitivityKey, defaultValue: defaultSensitivity) as String;
  }

  static Future<void> setMotionSensitivity(String value) async {
    await _box.put(motionSensitivityKey, value);
  }

  static bool get hasCalibration {
    return _box.get(hasCalibrationKey, defaultValue: false) as bool;
  }

  static double? get calibrationThreshold {
    final value = _box.get(calibrationThresholdKey);
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static double? get calibrationNoiseLevel {
    final value = _box.get(calibrationNoiseLevelKey);
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static double get calibrationConfidenceMin {
    final value = _box.get(calibrationConfidenceMinKey, defaultValue: 1.0);
    if (value is num) {
      return value.toDouble();
    }
    return 1.0;
  }

  static double get calibrationForwardRatio {
    final value = _box.get(calibrationForwardRatioKey, defaultValue: 0.30);
    if (value is num) {
      return value.toDouble();
    }
    return 0.30;
  }

  static Future<void> saveCalibration({
    required double threshold,
    required double noiseLevel,
    required double confidenceMin,
    required double forwardRatio,
  }) async {
    await _box.put(calibrationThresholdKey, threshold);
    await _box.put(calibrationNoiseLevelKey, noiseLevel);
    await _box.put(calibrationConfidenceMinKey, confidenceMin);
    await _box.put(calibrationForwardRatioKey, forwardRatio);
    await _box.put(hasCalibrationKey, true);
  }

  static Future<void> clearCalibration() async {
    await _box.put(hasCalibrationKey, false);
    await _box.delete(calibrationThresholdKey);
    await _box.delete(calibrationNoiseLevelKey);
    await _box.delete(calibrationConfidenceMinKey);
    await _box.delete(calibrationForwardRatioKey);
  }
}
