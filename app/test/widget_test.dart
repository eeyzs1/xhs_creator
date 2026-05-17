import 'package:flutter_test/flutter_test.dart';
import 'package:xhs_creator/main.dart';

void main() {
  testWidgets('App renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const XHSCreatorApp());
    await tester.pump();
    expect(find.text('小红书创作助手'), findsOneWidget);
  });
}
