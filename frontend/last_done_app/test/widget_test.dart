import 'package:flutter_test/flutter_test.dart';

import 'package:last_done_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows setup screen on first launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LastDoneApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('初期設定'), findsOneWidget);
    expect(find.text('保存して開始'), findsOneWidget);
  });
}
