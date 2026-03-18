import 'package:hive/hive.dart';

import '../models/session_record.dart';

/// Stores per-rider session history for review.
class SessionStorage {
  static const _boxName = 'sessionHistoryBox';
  static const _maxEntries = 20;

  static Future<void> init() async {
    await Hive.openBox<List<dynamic>>(_boxName);
  }

  static Box<List<dynamic>> get _box => Hive.box<List<dynamic>>(_boxName);

  static Future<void> addSession(String riderId, SessionRecord record) async {
    final existing = _box.get(riderId)?.cast<SessionRecord>() ?? <SessionRecord>[];
    final updated = [record, ...existing];
    if (updated.length > _maxEntries) {
      updated.removeLast();
    }
    await _box.put(riderId, updated);
  }

  static List<SessionRecord> getSessions(String riderId) {
    return _box.get(riderId)?.cast<SessionRecord>() ?? <SessionRecord>[];
  }

  static Future<void> clearSessions(String riderId) async {
    await _box.delete(riderId);
  }
}
