import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

/// Firebase's account timestamps, which say whether an account is brand new.
class TestMetadata implements UserMetadata {
  TestMetadata({required this.creationTime, required this.lastSignInTime});

  @override
  final DateTime? creationTime;

  @override
  final DateTime? lastSignInTime;
}

/// An account created by this very sign-in: both times match.
MockUser newAccount({String uid = 'user-1', String? name = 'Ada Lovelace'}) {
  final now = DateTime.now();
  return MockUser(
    uid: uid,
    displayName: name,
    metadata: TestMetadata(creationTime: now, lastSignInTime: now),
  );
}

/// An account that existed before today, signing in again.
MockUser existingAccount({
  String uid = 'user-1',
  String? name = 'Ada Lovelace',
}) {
  final now = DateTime.now();
  return MockUser(
    uid: uid,
    displayName: name,
    metadata: TestMetadata(
      creationTime: now.subtract(const Duration(days: 30)),
      lastSignInTime: now,
    ),
  );
}
