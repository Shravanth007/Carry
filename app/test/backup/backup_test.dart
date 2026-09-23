import 'package:carry/auth/auth.dart';
import 'package:carry/backup/backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/test_analytics.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';

/// Storage a test can interrupt part-way through reading, which is how a
/// sign-out lands in the middle of an upload check.
final class _InterruptiblePrefs extends InMemorySharedPreferencesAsync {
  _InterruptiblePrefs() : super.empty();

  /// Runs during the next stamp read, once.
  Future<void> Function()? duringNextRead;

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async {
    final interrupt = duringNextRead;
    duringNextRead = null;
    await interrupt?.call();
    return super.getInt(key, options);
  }
}

void main() {
  setUp(() async {
    setUpTestPrefs();
    await setUpTestAuth(signedIn: true);
  });

  test(
    'turning it on or off is counted, by the place that stores it',
    () async {
      final events = setUpTestAnalytics();

      await Backup.setOn(true);
      await Backup.setOn(false);

      expect(events.named('backup_toggled').map((e) => e.properties['on']), [
        true,
        false,
      ]);
    },
  );

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

    test('nothing while the flag says off, stamp or no stamp', () async {
      await Backup.setOn(true);
      // The flag is written last, so this is what a switch-off that died
      // halfway, or a stamp that failed to clear, leaves behind.
      await SharedPreferencesAsync().setBool('backup_on_firebase-uid', false);

      expect(await Backup.onSince(), isNotNull, reason: 'the stamp survived');
      expect(await Backup.shouldUpload(DateTime.now()), isFalse);
    });

    test("never on the last account's answer", () async {
      await Backup.setOn(true);

      await setUpTestAuth(signedIn: true, uid: 'someone-else');

      expect(await Backup.shouldUpload(DateTime.now()), isFalse);
    });

    test('nothing when the account goes mid-question', () async {
      final prefs = _InterruptiblePrefs();
      SharedPreferencesAsyncPlatform.instance = prefs;
      await Backup.setOn(true);
      prefs.duringNextRead = Auth.signOut;

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
