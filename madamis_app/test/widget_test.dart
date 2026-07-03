import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/main.dart';

void main() {
  testWidgets('App renders home screen', (tester) async {
    await tester.pumpWidget(const MadamisApp());
    expect(find.text('マダミス GM'), findsOneWidget);
    expect(find.text('新しいゲームを始める'), findsOneWidget);
  });
}
