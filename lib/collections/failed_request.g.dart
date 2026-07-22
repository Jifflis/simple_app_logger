// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'failed_request.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FailedRequestAdapter extends TypeAdapter<FailedRequest> {
  @override
  final typeId = 0;

  @override
  FailedRequest read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FailedRequest(
      url: fields[0] as String,
      headers: (fields[1] as Map).cast<String, String>(),
      body: (fields[2] as Map).cast<String, dynamic>(),
      retryCount: fields[3] == null ? 0 : (fields[3] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, FailedRequest obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.url)
      ..writeByte(1)
      ..write(obj.headers)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(3)
      ..write(obj.retryCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FailedRequestAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
