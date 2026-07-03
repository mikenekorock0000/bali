import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/main.dart';

void main() {
  testWidgets('App renders home screen', (tester) async {
    await tester.pumpWidget(const MadamisApp());
    await tester.pumpAndSettle();

    expect(find.text('マダミス GM'), findsWidgets);
    expect(find.text('はじめかた'), findsOneWidget);
    expect(find.text('AIでシナリオを作る'), findsOneWidget);
    expect(find.text('保存シナリオ'), findsOneWidget);
  });
}
