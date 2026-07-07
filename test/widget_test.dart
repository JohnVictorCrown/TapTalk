import 'package:flutter_test/flutter_test.dart';

import 'package:taptalk/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const TapTalkApp());

    expect(find.text('TapTalk'), findsOneWidget);
  });
}
