import 'package:carry/auth/auth.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_analytics.dart';
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

  testWidgets('counts the sign-in screen once, however often it rebuilds', (
    tester,
  ) async {
    final events = setUpTestAnalytics();
    await setUpTestAuth();
    await pumpScreen(tester, gate);
    await tester.pump();

    // Whatever makes this rebuild - a parent, a repeated auth snapshot - the
    // funnel must not gain a second arrival at the same screen.
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, gate);
    await tester.pump();
    await tester.pump();

    expect(events.screens.where((s) => s == 'sign_in'), hasLength(1));
  });

  testWidgets('a session ending on its own drops the analytics identity', (
    tester,
  ) async {
    final events = setUpTestAnalytics();
    final testAuth = await setUpTestAuth(signedIn: true);
    await pumpScreen(tester, gate);
    await tester.pump();

    // Nobody tapped sign out: Firebase ended the session itself, as it does
    // when a token is revoked or the account is deleted. Events after this
    // must not still be attributed to that account.
    await testAuth.firebase.signOut();
    await tester.pump();

    expect(events.resets, 1);
  });

  testWidgets('a session ending on its own drops the notes with it', (
    tester,
  ) async {
    final testAuth = await setUpTestAuth(signedIn: true);
    Notes.addAudio(
      source: AudioSource.recorded,
      ownerUid: 'firebase-uid',
      path: '/tmp/theirs.m4a',
      bytes: 2048,
    );
    await pumpScreen(tester, gate);
    await tester.pump();
    expect(Notes.all.value, hasLength(1));

    // Nobody tapped Sign out, so signOutAndForget never runs. If the list
    // survives this, the next person to sign in opens Carry onto somebody
    // else's recordings.
    await testAuth.firebase.signOut();
    await tester.pump();

    expect(Notes.all.value, isEmpty);
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
