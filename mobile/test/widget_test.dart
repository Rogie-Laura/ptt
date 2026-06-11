import 'package:flutter_test/flutter_test.dart';
import 'package:ptt_app/main.dart';

void main() {
  testWidgets('PTT app loads join screen', (tester) async {
    await tester.pumpWidget(const PttApp());
    expect(find.text('📻 PTT'), findsOneWidget);
    expect(find.text('Sumali sa channel'), findsOneWidget);
  });
}
