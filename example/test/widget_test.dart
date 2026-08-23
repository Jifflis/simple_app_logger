import 'package:flutter_test/flutter_test.dart';
import 'package:simple_app_logger_example/main.dart';

void main() {
  testWidgets('shows API-key setup guidance when no key is provided', (
    tester,
  ) async {
    await tester.pumpWidget(const LoggerExampleApp());
    await tester.pump();

    expect(find.text('Simple App Logger'), findsOneWidget);
    expect(find.textContaining('Missing APP_LOGGER_API_KEY'), findsOneWidget);
    expect(find.textContaining('flutter run --dart-define'), findsOneWidget);
  });
}
