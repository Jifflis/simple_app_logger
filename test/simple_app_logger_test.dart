import 'package:flutter_test/flutter_test.dart';

import 'package:simple_app_logger/simple_app_logger.dart';

void main() {
  test('logging before initialization is safely ignored', () async {
    await expectLater(SimpleAppLogger.info('test message'), completes);
  });
}
