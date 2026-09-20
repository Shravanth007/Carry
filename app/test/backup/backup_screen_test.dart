import 'package:carry/backup/backup.dart';
import 'package:carry/backup/backup_screen.dart';
import 'package:carry/settings/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';

void main() {
  setUp(() async {
    setUpTestPrefs();
    await setUpTestAuth(signedIn: true);
  });

  Future<void> pumpBackup(WidgetTester tester) async {
    await pumpScreen(tester, const BackupScreen());
    await tester.pumpAndSettle();
  }

  Switch backupSwitch(WidgetTester tester) =>
      tester.widget(find.byType(Switch));

  testWidgets('starts off, with recordings staying on the phone', (
    tester,
  ) async {
    await pumpBackup(tester);

    expect(backupSwitch(tester).value, isFalse);
    expect(find.text('Recordings stay on this phone.'), findsOneWidget);
    expect(
      find.textContaining('Anything already recorded stays here'),
      findsOneWidget,
    );
  });

  testWidgets('says what uploaded recordings are used for', (tester) async {
    await pumpBackup(tester);

    expect(find.textContaining('not used for anything else'), findsOneWidget);
  });

  testWidgets('turning it on covers new recordings only', (tester) async {
    await pumpBackup(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(backupSwitch(tester).value, isTrue);
    expect(find.text('New recordings are uploaded.'), findsOneWidget);
    expect(find.textContaining('On since'), findsOneWidget);
    expect(
      find.textContaining('does not reach back'),
      findsOneWidget,
      reason: 'the screen says older recordings stay put',
    );
    expect(await Backup.isOn(), isTrue);
  });

  testWidgets('turning it off again keeps recordings on the phone', (
    tester,
  ) async {
    await pumpBackup(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(backupSwitch(tester).value, isFalse);
    expect(await Backup.isOn(), isFalse);
  });

  testWidgets('remembers the answer next time the screen opens', (
    tester,
  ) async {
    await Backup.setOn(true);

    await pumpBackup(tester);

    expect(backupSwitch(tester).value, isTrue);
  });

  testWidgets('Google Drive is announced, not offered', (tester) async {
    await pumpBackup(tester);

    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.byType(SoonBadge), findsOneWidget);
    final drive = tester.widget<SettingsRow>(
      find.widgetWithText(SettingsRow, 'Google Drive'),
    );
    expect(drive.onTap, isNull);
  });
}
