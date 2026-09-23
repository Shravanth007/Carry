import 'dart:async';

import 'package:carry/permissions/permissions.dart';
import 'package:carry/settings/permissions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import '../helpers/pump.dart';
import '../helpers/test_device.dart';

void main() {
  Future<void> pumpPermissions(WidgetTester tester) async {
    await pumpScreen(tester, const PermissionsScreen());
    await tester.pumpAndSettle();
  }

  Switch micSwitch(WidgetTester tester) => tester.widget(find.byType(Switch));

  testWidgets('a session ending while the prompt is up breaks nothing', (
    tester,
  ) async {
    // Signing out closes every pushed screen, so the prompt can come back to a
    // screen that no longer exists. Asking a dead screen for a dialog throws.
    final permissions = setUpTestPermissions();
    permissions.answer = PermissionStatus.permanentlyDenied;
    permissions.prompt = Completer<void>();
    await pumpPermissions(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pumpWidget(const SizedBox()); // the screen goes away
    permissions.prompt!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  Future<void> flip(WidgetTester tester) async {
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
  }

  testWidgets('is on when the microphone is allowed', (tester) async {
    setUpTestPermissions(status: MicPermission.granted);

    await pumpPermissions(tester);

    expect(micSwitch(tester).value, isTrue);
    expect(find.text('Carry can record.'), findsOneWidget);
  });

  testWidgets('is off when the microphone is not allowed', (tester) async {
    setUpTestPermissions();

    await pumpPermissions(tester);

    expect(micSwitch(tester).value, isFalse);
    expect(find.text('Needed to record notes.'), findsOneWidget);
  });

  testWidgets('switching on asks for the microphone', (tester) async {
    final permissions = setUpTestPermissions();
    await pumpPermissions(tester);

    await flip(tester);

    expect(permissions.prompts, 1);
    expect(micSwitch(tester).value, isTrue);
    expect(find.text('Carry can record.'), findsOneWidget);
  });

  group('turning it off', () {
    testWidgets('explains that the phone owns permissions', (tester) async {
      final permissions = setUpTestPermissions(status: MicPermission.granted);
      await pumpPermissions(tester);

      await flip(tester);

      expect(find.text('Turn off the microphone'), findsOneWidget);
      expect(
        find.textContaining('Carry cannot turn this off itself'),
        findsOneWidget,
      );
      expect(permissions.settingsOpened, 0, reason: 'not until confirmed');
    });

    testWidgets('Open settings goes to phone settings', (tester) async {
      final permissions = setUpTestPermissions(status: MicPermission.granted);
      await pumpPermissions(tester);
      await flip(tester);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(permissions.settingsOpened, 1);
      expect(permissions.prompts, 0);
    });

    testWidgets('Cancel leaves everything alone', (tester) async {
      final permissions = setUpTestPermissions(status: MicPermission.granted);
      await pumpPermissions(tester);
      await flip(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(permissions.settingsOpened, 0);
      expect(micSwitch(tester).value, isTrue, reason: 'still allowed');
    });

    testWidgets('says what to do when settings will not open', (tester) async {
      // The web preview, for one: the phone has no settings page to show.
      final permissions = setUpTestPermissions(status: MicPermission.granted);
      permissions.canOpenSettings = false;
      await pumpPermissions(tester);
      await flip(tester);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Settings → Apps → Carry → Permissions'),
        findsOneWidget,
      );
    });
  });

  group('when the phone will not prompt again', () {
    testWidgets('switching on explains and offers phone settings', (
      tester,
    ) async {
      final permissions = setUpTestPermissions(status: MicPermission.blocked);
      await pumpPermissions(tester);
      expect(find.text('Turn it on in phone settings.'), findsOneWidget);

      await flip(tester);

      expect(find.text('Allow the microphone'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(permissions.settingsOpened, 1);
      expect(permissions.prompts, 0);
    });

    testWidgets('a prompt that never appears ends in the same place', (
      tester,
    ) async {
      // Android reports "never ask again" as plain denied until asked.
      final permissions = setUpTestPermissions();
      permissions.answer = PermissionStatus.permanentlyDenied;
      await pumpPermissions(tester);

      await flip(tester);

      expect(permissions.prompts, 1);
      expect(find.text('Allow the microphone'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(permissions.settingsOpened, 1);
      expect(find.text('Turn it on in phone settings.'), findsOneWidget);
    });
  });
}
