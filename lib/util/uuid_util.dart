import 'package:uuid/uuid.dart';

class UUIDGenerator {
  // Private constructor
  UUIDGenerator._internal();

  // The single instance (lazily initialized)
  static final UUIDGenerator _instance = UUIDGenerator._internal();

  // Getter to access the singleton instance
  static UUIDGenerator get instance => _instance;

  // UUID instance (v4 for random UUIDs)
  final Uuid _uuid = Uuid();

  // Method to generate UUID v4
  String generate() {
    return _uuid.v4();
  }
}
