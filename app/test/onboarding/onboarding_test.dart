import 'package:carry/onboarding/onboarding.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_accounts.dart';
import '../helpers/test_device.dart';

void main() {
  setUp(setUpTestPrefs);

  group('isNewAccount', () {
    test('an account created by this sign-in is new', () {
      expect(Onboarding.isNewAccount(newAccount()), isTrue);
    });

    test('an account that signed in before is not new', () {
      expect(Onboarding.isNewAccount(existingAccount()), isFalse);
    });

    test('unknown timestamps count as an existing account', () {
      final noTimes = MockUser(
        uid: 'user-1',
        metadata: TestMetadata(creationTime: null, lastSignInTime: null),
      );

      expect(Onboarding.isNewAccount(noTimes), isFalse);
    });
  });

  test('a new account has not been welcomed', () async {
    expect(await Onboarding.isDone('user-1'), isFalse);
  });

  test('stays done once marked', () async {
    await Onboarding.markDone('user-1');

    expect(await Onboarding.isDone('user-1'), isTrue);
  });

  test('is remembered per account', () async {
    await Onboarding.markDone('user-1');

    expect(await Onboarding.isDone('user-2'), isFalse);
  });
}
