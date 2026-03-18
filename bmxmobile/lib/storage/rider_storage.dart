import 'package:hive/hive.dart';

import '../models/rider.dart';

/// A simple wrapper around Hive to persist rider profiles.
class RiderStorage {
  static const _boxName = 'ridersBox';

  static Future<void> init() async {
    await Hive.openBox<Rider>(_boxName);
  }

  static Box<Rider> get _box => Hive.box<Rider>(_boxName);

  static List<Rider> getAllRiders() {
    return _box.values.toList();
  }

  static Future<void> saveRider(Rider rider) async {
    await _box.put(rider.id, rider);
  }

  static Future<void> deleteRider(String riderId) async {
    await _box.delete(riderId);
  }

  static Rider? getRider(String id) {
    return _box.get(id);
  }
}
