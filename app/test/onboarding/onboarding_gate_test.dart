import 'package:carry/onboarding/onboarding.dart';
import 'package:carry/onboarding/permission_screen.dart';
import 'package:carry/onboarding/welcome_screen.dart';
import 'package:carry/permissions/permissions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';
import '../helpers/test_accounts.dart';
import '../helpers/test_device.dart';

void main() {
  setUp(setUpTestPrefs);

  Future<void> pumpGate(WidgetTester tester, MockUser user) async {
    await pumpScreen(
      tester,
      OnboardingGate(user: user, home: const Text('Home')),
    );
    await tester.pumpAndSettle();
  }

  final welcome = find.byType(WelcomeScreen);
  final microphone = find.byType(PermissionScreen);
  final home = find.text('Home');

  group('new account', () {
    testWidgets('welcome, then the microphone, then home', (tester) async {
      setUpTestPermissions();

      await pumpGate(tester, newAccount());
      expect(welcome, findsOneWidget);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(microphone, findsOneWidget);

      await tester.tap(find.text('Allow microphone'));
      await tester.pumpAndSettle();
      expect(home, findsOneWidget);
    });

    testWidgets('skips the microphone when the phone already allows it', (
      tester,
    ) async {
      final permissions = setUpTestPermissions(status: MicPermission.granted);

      await pumpGate(tester, newAccount(uid: 'user-2'));
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(microphone, findsNothing);
      expect(home, findsOneWidget);
      expect(permissions.prompts, 0);
    });

    testWidgets('skipping the microphone still finishes onboarding', (
      tester,
    ) async {
      setUpTestPermissions();

      await pumpGate(tester, newAccount());
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(home, findsOneWidget);
      expect(await Onboarding.isDone('user-1'), isTrue);
    });

    testWidgets('closing the app mid-flow starts the flow again', (
      tester,
    ) async {
      setUpTestPermissions();

      await pumpGate(tester, newAccount());
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(microphone, findsOneWidget);

      // Nothing is saved until the end, so a fresh launch starts over.
      expect(await Onboarding.isDone('user-1'), isFalse);
      await tester.pumpWidget(const SizedBox()); // tears the app down
      await pumpGate(tester, newAccount());

      expect(welcome, findsOneWidget);
    });
  });

  group('account that already exists', () {
    testWidgets('goes straight home after onboarding on this phone', (
      tester,
    ) async {
      setUpTestPermissions(status: MicPermission.granted);
      await Onboarding.markDone('user-1');

      await pumpGate(tester, existingAccount());

      expect(home, findsOneWidget);
      expect(welcome, findsNothing);
    });

    testWidgets('signing out and back in shows no welcome', (tester) async {
      setUpTestPermissions(status: MicPermission.granted);
      await pumpGate(tester, newAccount());
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(home, findsOneWidget);

      // Sign out, sign back in: same account, now an existing one.
      await tester.pumpWidget(const SizedBox());
      await pumpGate(tester, existingAccount());

      expect(home, findsOneWidget);
      expect(welcome, findsNothing);
    });

    testWidgets('goes straight home on a fresh install', (tester) async {
      // Nothing saved on this phone, but the account is not new.
      final permissions = setUpTestPermissions();

      await pumpGate(tester, existingAccount());

      expect(home, findsOneWidget);
      expect(welcome, findsNothing);
      expect(microphone, findsNothing);
      expect(permissions.prompts, 0);
    });

    testWidgets('is not re-onboarded when the microphone is off', (
      tester,
    ) async {
      // Home's banner handles this, rather than blocking the app again.
      setUpTestPermissions();
      await Onboarding.markDone('user-1');

      await pumpGate(tester, existingAccount());

      expect(home, findsOneWidget);
      expect(microphone, findsNothing);
    });
  });

  testWidgets('a new second account on the phone is welcomed', (tester) async {
    setUpTestPermissions(status: MicPermission.granted);
    await Onboarding.markDone('user-1');

    await pumpGate(tester, newAccount(uid: 'user-2'));

    expect(welcome, findsOneWidget);
  });
}
