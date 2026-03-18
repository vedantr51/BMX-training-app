// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rider.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RiderAdapter extends TypeAdapter<Rider> {
  @override
  final int typeId = 0;

  @override
  Rider read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Rider(
      id: fields[0] as String,
      name: fields[1] as String,
      personalBestReactionTime: fields[2] as double,
      bestScore: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Rider obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.personalBestReactionTime)
      ..writeByte(3)
      ..write(obj.bestScore);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
