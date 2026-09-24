import 'package:flutter_test/flutter_test.dart';

import 'package:music_app/main.dart';

void main() {
  testWidgets('App boots into the home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicApp());

    expect(find.byType(RootShell), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
  });
}
