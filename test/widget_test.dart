import 'package:flutter_test/flutter_test.dart';

import 'package:xplored/main.dart';

void main() {
  testWidgets('App startet ohne Absturz', (WidgetTester tester) async {
    await tester.pumpWidget(const XploreDApp());
    // Reicht als Rauchtest - der generierte Counter-Test von `flutter create`
    // passt inhaltlich nicht zu XploreD, deshalb hier bewusst minimal gehalten.
    expect(find.byType(XploreDApp), findsOneWidget);
  });
}