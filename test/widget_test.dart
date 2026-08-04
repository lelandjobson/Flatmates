import 'package:flutter_test/flutter_test.dart';

import 'package:flatmates/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const FlatmatesApp());
    await tester.pumpAndSettle();
    expect(find.text('flatmates'), findsOneWidget);
  });
}
