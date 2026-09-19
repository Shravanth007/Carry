import 'package:carry/auth/auth.dart';
import 'package:carry/permissions/permissions.dart';
import 'package:carry/settings/permissions_screen.dart';
import 'package:carry/settings/settings_screen.dart';
import 'package:carry/settings/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';

void main() {
  late TestAuth testAuth;

  setUp(() async {
    testAuth = await setUpTestAuth(signedIn: true);
    setUpTestPermissions(status: MicPermission.granted);
    setUpTestPrefs();
    setUpTestAvatarDownloads();
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    String? name = 'Ada Lovelace',
    String? photoUrl,
  }) async {
    await pumpScreen(
      tester,
      SettingsScreen(name: name, email: testEmail, photoUrl: photoUrl),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows who is signed in', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text(testEmail), findsOneWidget);
  });

  testWidgets('shows the Google photo when there is one', (tester) async {
    await pumpSettings(tester, photoUrl: 'https://example.com/ada.jpg');

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('shows the initial while the photo is offline', (tester) async {
    setUpTestAvatarDownloads(status: 500);

    await pumpSettings(tester, photoUrl: 'https://example.com/ada.jpg');

    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('falls back to an initial without a photo', (tester) async {
    await pumpSettings(tester);

    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('uses the email initial when there is no name', (tester) async {
    await pumpSettings(tester, name: null);

    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text(testEmail.substring(0, 1).toUpperCase()), findsOneWidget);
  });

  testWidgets('opens permissions', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Permissions'));
    await tester.pumpAndSettle();

    expect(find.byType(PermissionsScreen), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
  });

  testWidgets('shows MCP as on the way, not as something to tap', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('Soon'), findsOneWidget);
    final mcpRow = tester.widget<SettingsRow>(
      find.widgetWithText(SettingsRow, 'MCP'),
    );
    expect(mcpRow.onTap, isNull);
  });

  testWidgets('signs out of Firebase and Google', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(Auth.currentUser, isNull);
    expect(testAuth.google.signOutCalls, 1);
  });
}
