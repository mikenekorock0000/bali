import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/main.dart';

void main() {
  testWidgets('App renders home screen', (tester) async {
    await tester.pumpWidget(const MadamisApp());
    expect(find.text('マダミス GM'), findsOneWidget);
    expect(find.text('AIでシナリオ生成'), findsOneWidget);
    expect(find.text('固定シナリオで遊ぶ（4人・対立）'), findsOneWidget);
    expect(find.text('協力推理デモ（2人）'), findsOneWidget);
  });
}
