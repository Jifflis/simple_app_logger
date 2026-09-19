import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CrashJournal {
  CrashJournal._(this._file);

  static const _fileName = 'simple_app_logger_crashes.jsonl';
  static const _maxBytes = 256 * 1024;

  final File _file;

  static Future<CrashJournal> create() async {
    final directory = await getApplicationSupportDirectory();
    return CrashJournal._(
      File('${directory.path}${Platform.pathSeparator}$_fileName'),
    );
  }

  static CrashJournal atPath(String path) => CrashJournal._(File(path));

  bool writeSync(Map<String, dynamic> record) {
    try {
      _file.parent.createSync(recursive: true);
      final mode = _file.existsSync() && _file.lengthSync() < _maxBytes
          ? FileMode.append
          : FileMode.write;
      _file.writeAsStringSync(
        '${jsonEncode(record)}\n',
        mode: mode,
        flush: true,
      );
      return true;
    } catch (_) {
      // A crash handler must never throw while handling the original error.
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> read() async {
    try {
      if (!await _file.exists()) return const [];
      final records = <Map<String, dynamic>>[];
      for (final line in await _file.readAsLines()) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map) {
            records.add(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {
          // Skip partial records left by an interrupted synchronous write.
        }
      }
      return records;
    } catch (_) {
      return const [];
    }
  }

  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.writeAsString('');
    } catch (_) {
      // Retaining the journal causes a safe idempotent retry next launch.
    }
  }
}
