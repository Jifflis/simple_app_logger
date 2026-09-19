import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_app_logger/service/crash_journal_io.dart';

void main() {
  test('writes and recovers complete crash records', () async {
    final directory = await Directory.systemTemp.createTemp('logger_crash_');
    addTearDown(() => directory.delete(recursive: true));
    final journal = CrashJournal.atPath('${directory.path}/crashes.jsonl');

    journal.writeSync({
      'id': 'event-1',
      'message': 'boom',
      'tag': 'uncaught_crash',
    });

    final records = await journal.read();
    expect(records, hasLength(1));
    expect(records.single['id'], 'event-1');

    await journal.clear();
    expect(await journal.read(), isEmpty);
  });

  test('skips an incomplete record while recovering valid records', () async {
    final directory = await Directory.systemTemp.createTemp('logger_crash_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/crashes.jsonl');
    await file.writeAsString('{incomplete}\n{"id":"event-2"}\n');
    final journal = CrashJournal.atPath(file.path);

    final records = await journal.read();
    expect(records, hasLength(1));
    expect(records.single['id'], 'event-2');
  });
}
