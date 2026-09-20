import 'package:carry/auth/sign_in_screen.dart';
import 'package:carry/backup/backup_screen.dart';
import 'package:carry/home/home_screen.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/onboarding/microphone_screen.dart';
import 'package:carry/onboarding/welcome_screen.dart';
import 'package:carry/settings/permissions_screen.dart';
import 'package:carry/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump.dart';
import 'helpers/test_auth.dart';
import 'helpers/test_device.dart';
import 'helpers/test_files.dart';

/// Every screen, on every phone size we support, at normal and large text.
///
/// A layout that doesn't fit throws in tests, which is what catches text
/// spilling out of a button or a column running off the bottom.
void main() {
  setUp(() async {
    await setUpTestAuth(signedIn: true);
    setUpTestPermissions();
    setUpTestPrefs();
    setUpTestFilePicker();
    Notes.clear();
  });

  final screens = <String, Widget>{
    'sign in': const SignInScreen(),
    'welcome': WelcomeScreen(name: 'Ada Lovelace', onContinue: () {}),
    'microphone': MicrophoneScreen(onDone: () {}),
    'home': const HomeScreen(name: 'Ada Lovelace', email: testEmail),
    'settings': const SettingsScreen(name: 'Ada Lovelace', email: testEmail),
    'permissions': const PermissionsScreen(),
    'backup': const BackupScreen(),
  };

  // 1.0 is the default. 1.5 is a common accessibility setting, and Android
  // goes past it, so a screen that survives 1.5 has room to spare.
  const textScales = [1.0, 1.5];

  for (final screen in screens.entries) {
    for (final phone in phoneSizes.entries) {
      for (final textScale in textScales) {
        testWidgets('${screen.key} fits a ${phone.key} at ${textScale}x text', (
          tester,
        ) async {
          await pumpScreen(
            tester,
            screen.value,
            size: phone.value,
            textScale: textScale,
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('a long note title does not break the list', (tester) async {
    Notes.add(
      Note(
        id: '1',
        title: 'Quarterly planning with the whole team about next year' * 3,
        path: '/phone/long.m4a',
        addedAt: DateTime.now(),
      ),
    );

    await pumpScreen(
      tester,
      const HomeScreen(name: 'Ada', email: testEmail),
      size: phoneSizes['small phone']!,
      textScale: 1.5,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
