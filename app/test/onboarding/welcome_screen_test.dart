import 'package:carry/onboarding/welcome_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';

void main() {
  testWidgets('greets the user by first name', (tester) async {
    await pumpScreen(
      tester,
      WelcomeScreen(name: 'Ada Lovelace', onContinue: () {}),
    );

    expect(find.text('Welcome, Ada'), findsOneWidget);
  });

  testWidgets('falls back to a plain greeting without a name', (tester) async {
    await pumpScreen(tester, WelcomeScreen(name: null, onContinue: () {}));

    expect(find.text('Welcome to Carry'), findsOneWidget);
  });

  testWidgets('says nothing about permissions', (tester) async {
    await pumpScreen(tester, WelcomeScreen(name: 'Ada', onContinue: () {}));

    expect(find.textContaining('microphone'), findsNothing);
  });

  testWidgets('Get started moves on', (tester) async {
    var continued = 0;
    await pumpScreen(
      tester,
      WelcomeScreen(name: 'Ada', onContinue: () => continued++),
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(continued, 1);
  });
}
