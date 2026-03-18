import 'package:hive/hive.dart';

import 'session_result.dart';

/// A Hive adapter for storing the StartType enum.
class StartTypeAdapter extends TypeAdapter<StartType> {
  @override
  final int typeId = 2;

  @override
  StartType read(BinaryReader reader) {
    final value = reader.readByte();
    switch (value) {
      case 0:
        return StartType.valid;
      case 1:
        return StartType.falseStart;
      case 2:
        return StartType.lateStart;
      default:
        return StartType.valid;
    }
  }

  @override
  void write(BinaryWriter writer, StartType obj) {
    switch (obj) {
      case StartType.valid:
        writer.writeByte(0);
        break;
      case StartType.falseStart:
        writer.writeByte(1);
        break;
      case StartType.lateStart:
        writer.writeByte(2);
        break;
    }
  }
}
