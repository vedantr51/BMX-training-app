import 'package:flutter/material.dart';

import '../models/rider.dart';
import '../models/sensitivity.dart';
import '../models/session_record.dart';
import '../models/session_result.dart';
import '../storage/rider_storage.dart';
import '../storage/settings_storage.dart';
import '../storage/session_storage.dart';

/// Manages rider profiles and app-wide settings.
class ProfileService extends ChangeNotifier {
  List<Rider> _riders = [];
  Rider? _selectedRider;
  MotionSensitivity _sensitivity = MotionSensitivity.medium;
  List<SessionRecord> _sessionHistory = [];
  bool _hasCalibration = false;
  double? _calibratedThreshold;
  double _calibrationNoiseLevel = 0.0;
  double _confidenceMin = 1.0;
  double _forwardRatio = 0.30;

  ProfileService() {
    _loadFromStorage();
  }

  List<Rider> get riders => List.unmodifiable(_riders);
  Rider? get selectedRider => _selectedRider;
  MotionSensitivity get sensitivity => _sensitivity;
  bool get hasCalibration => _hasCalibration;
  double? get calibratedThreshold => _calibratedThreshold;
  double get calibrationNoiseLevel => _calibrationNoiseLevel;
  double get confidenceMin => _confidenceMin;
  double get forwardRatio => _forwardRatio;

  Future<void> _loadFromStorage() async {
    _riders = RiderStorage.getAllRiders();

    // Restore selected rider if available.
    final savedId = SettingsStorage.selectedRiderId;
    if (savedId != null) {
      _selectedRider = RiderStorage.getRider(savedId);
      _sessionHistory = SessionStorage.getSessions(savedId);
    }

    // Restore sensitivity.
    final saved = SettingsStorage.motionSensitivity;
    _sensitivity = MotionSensitivity.values.firstWhere(
      (element) => element.name == saved,
      orElse: () => MotionSensitivity.medium,
    );

    _hasCalibration = SettingsStorage.hasCalibration;
    _calibratedThreshold = SettingsStorage.calibrationThreshold;
    _calibrationNoiseLevel = SettingsStorage.calibrationNoiseLevel ?? 0.0;
    _confidenceMin = SettingsStorage.calibrationConfidenceMin;
    _forwardRatio = SettingsStorage.calibrationForwardRatio;

    notifyListeners();
  }

  Future<void> addRider(String name) async {
    final rider = Rider(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      personalBestReactionTime: double.infinity,
      bestScore: 0,
    );
    _riders = [..._riders, rider];
    await RiderStorage.saveRider(rider);
    notifyListeners();
  }

  Future<void> deleteRider(String riderId) async {
    await RiderStorage.deleteRider(riderId);
    _riders = RiderStorage.getAllRiders();

    if (_selectedRider?.id == riderId) {
      _selectedRider = null;
      await SettingsStorage.setSelectedRiderId('');
    }

    notifyListeners();
  }

  Future<void> selectRider(Rider rider) async {
    _selectedRider = rider;
    _sessionHistory = SessionStorage.getSessions(rider.id);
    await SettingsStorage.setSelectedRiderId(rider.id);
    notifyListeners();
  }

  List<SessionRecord> get sessionHistory => List.unmodifiable(_sessionHistory);

  double get averageReaction {
    if (_sessionHistory.isEmpty) return 0.0;
    final total = _sessionHistory.map((e) => e.reactionTimeSeconds).reduce((a, b) => a + b);
    return total / _sessionHistory.length;
  }

  Future<void> updateRiderResult({
    required Rider rider,
    required double reactionTime,
    required int score,
    required StartType startType,
  }) async {
    final updated = rider.copyWith(
      personalBestReactionTime:
          reactionTime < rider.personalBestReactionTime ? reactionTime : rider.personalBestReactionTime,
      bestScore: score > rider.bestScore ? score : rider.bestScore,
    );

    await RiderStorage.saveRider(updated);

    _riders = RiderStorage.getAllRiders();
    if (_selectedRider?.id == updated.id) {
      _selectedRider = updated;
    }

    // Add session history.
    final record = SessionRecord(
      timestamp: DateTime.now(),
      reactionTimeSeconds: reactionTime,
      score: score,
      startType: startType,
    );
    if (updated.id.isNotEmpty) {
      await SessionStorage.addSession(updated.id, record);
    }

    if (_selectedRider?.id == updated.id) {
      _sessionHistory = SessionStorage.getSessions(updated.id);
    }

    notifyListeners();
  }

  Future<void> setSensitivity(MotionSensitivity sensitivity) async {
    _sensitivity = sensitivity;
    await SettingsStorage.setMotionSensitivity(sensitivity.name);
    notifyListeners();
  }

  Future<void> saveCalibration({
    required double threshold,
    required double noiseLevel,
    double confidenceMin = 1.0,
    double forwardRatio = 0.30,
  }) async {
    await SettingsStorage.saveCalibration(
      threshold: threshold,
      noiseLevel: noiseLevel,
      confidenceMin: confidenceMin,
      forwardRatio: forwardRatio,
    );

    _hasCalibration = true;
    _calibratedThreshold = threshold;
    _calibrationNoiseLevel = noiseLevel;
    _confidenceMin = confidenceMin;
    _forwardRatio = forwardRatio;
    notifyListeners();
  }

  Future<void> clearCalibration() async {
    await SettingsStorage.clearCalibration();
    _hasCalibration = false;
    _calibratedThreshold = null;
    _calibrationNoiseLevel = 0.0;
    _confidenceMin = 1.0;
    _forwardRatio = 0.30;
    notifyListeners();
  }
}
