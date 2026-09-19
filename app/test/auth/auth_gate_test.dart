import 'package:carry/auth/auth.dart';
import 'package:carry/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';
import '../helpers/test_auth.dart';

final gate = AuthGate(signedIn: (user) => Text('Home for ${user.email}'));

void main() {
  testWidgets('shows sign-in when signed out', (tester) async {
    await setUpTestAuth();
    await pumpScreen(tester, gate);
    await tester.pump();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('shows the signed-in screen when signed in', (tester) async {
    await setUpTestAuth(signedIn: true);
    await pumpScreen(tester, gate);
    await tester.pump();

    expect(find.text('Home for $testEmail'), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('switches screens on sign-in and sign-out', (tester) async {
    await setUpTestAuth();
    await pumpScreen(tester, gate);
    await tester.pump();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Home for $testEmail'), findsOneWidget);

    await tester.runAsync(Auth.signOut);
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
