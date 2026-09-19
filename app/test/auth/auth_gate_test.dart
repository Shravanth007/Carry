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

  testWidgets('signing out closes screens pushed above the gate', (
    tester,
  ) async {
    // Settings and permissions are pushed on top of the gate. Swapping what
    // the gate shows doesn't remove them, so they'd otherwise stay in front
    // of the sign-in screen.
    await setUpTestAuth(signedIn: true);
    await pumpScreen(
      tester,
      AuthGate(
        signedIn: (user) => Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Settings')),
              ),
            ),
            child: const Text('Open settings'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.runAsync(Auth.signOut);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing, reason: 'route was closed');
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
