import 'package:carry/auth/auth.dart';
import 'package:carry/backup/backup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';

void main() {
  setUp(() async {
    setUpTestPrefs();
    await setUpTestAuth(signedIn: true);
  });

  test('is off until somebody turns it on', () async {
    expect(await Backup.isOn(), isFalse);
    expect(await Backup.onSince(), isNull);
  });

  test('turning it on remembers when', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));

    await Backup.setOn(true);

    expect(await Backup.isOn(), isTrue);
    expect(await Backup.onSince(), isNotNull);
    expect((await Backup.onSince())!.isAfter(before), isTrue);
  });

  group('what gets uploaded', () {
    test('nothing at all while it is off', () async {
      expect(await Backup.shouldUpload(DateTime.now()), isFalse);
    });

    test('recordings made after it was turned on', () async {
      await Backup.setOn(true);

      final later = DateTime.now().add(const Duration(minutes: 1));
      expect(await Backup.shouldUpload(later), isTrue);
    });

    test('never what was recorded beforehand', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await Backup.setOn(true);

      expect(await Backup.shouldUpload(yesterday), isFalse);
    });

    test('and turning it off again stops everything', () async {
      await Backup.setOn(true);
      await Backup.setOn(false);

      expect(await Backup.isOn(), isFalse);
      expect(await Backup.onSince(), isNull);
      expect(await Backup.shouldUpload(DateTime.now()), isFalse);
    });

    test('turning it on again does not sweep up the gap', () async {
      await Backup.setOn(true);
      await Backup.setOn(false);
      final duringTheGap = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await Backup.setOn(true);

      expect(await Backup.shouldUpload(duringTheGap), isFalse);
    });
  });

  test('a signed-out phone uploads nothing', () async {
    await Backup.setOn(true);
    await Auth.signOut();

    expect(await Backup.isOn(), isFalse);
    expect(await Backup.shouldUpload(DateTime.now()), isFalse);
  });

  test('is answered per account', () async {
    await Backup.setOn(true);
    final firstAccount = await Backup.isOn();

    await setUpTestAuth(signedIn: true, uid: 'someone-else');

    expect(firstAccount, isTrue);
    expect(await Backup.isOn(), isFalse, reason: 'their own answer');
  });
}
