import 'package:carry/auth/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import '../helpers/test_auth.dart';

void main() {
  late TestAuth testAuth;

  setUp(() async => testAuth = await setUpTestAuth());

  group('signInWithGoogle', () {
    test('signs in to Firebase with the Google ID token', () async {
      final result = await Auth.signInWithGoogle();

      expect(result?.user?.email, testEmail);
      expect(Auth.currentUser?.email, testEmail);
      final credential = testAuth.firebase.lastCredential! as OAuthCredential;
      expect(credential.providerId, 'google.com');
      expect(credential.idToken, testIdToken);
    });

    test(
      'returns null and stays signed out when the picker is closed',
      () async {
        testAuth.google.onAuthenticate = () async =>
            throw googleError(GoogleSignInExceptionCode.canceled);

        expect(await Auth.signInWithGoogle(), isNull);
        expect(Auth.currentUser, isNull);
        expect(testAuth.firebase.lastCredential, isNull);
      },
    );

    test('rethrows other Google errors', () async {
      testAuth.google.onAuthenticate = () async =>
          throw googleError(GoogleSignInExceptionCode.clientConfigurationError);

      await expectLater(
        Auth.signInWithGoogle(),
        throwsA(
          isA<GoogleSignInException>().having(
            (e) => e.code,
            'code',
            GoogleSignInExceptionCode.clientConfigurationError,
          ),
        ),
      );
      expect(Auth.currentUser, isNull);
    });

    test('passes Firebase errors through', () async {
      whenCalling(Invocation.method(#signInWithCredential, null))
          .on(testAuth.firebase)
          .thenThrow(FirebaseAuthException(code: 'user-disabled'));

      await expectLater(
        Auth.signInWithGoogle(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'user-disabled',
          ),
        ),
      );
    });
  });

  test('signOut signs out of Firebase and Google', () async {
    await Auth.signInWithGoogle();

    await Auth.signOut();

    expect(Auth.currentUser, isNull);
    expect(testAuth.google.signOutCalls, 1);
  });

  test('userChanges reports sign-in and sign-out', () async {
    final emails = <String?>[];
    final sub = Auth.userChanges.listen((user) => emails.add(user?.email));
    addTearDown(sub.cancel);

    await Auth.signInWithGoogle();
    await Auth.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(emails, containsAllInOrder([testEmail, null]));
  });

  group('idToken', () {
    test('is null when signed out', () async {
      expect(await Auth.idToken(), isNull);
    });

    test('is a token for the signed-in user', () async {
      await Auth.signInWithGoogle();

      expect(await Auth.idToken(), isNotEmpty);
      expect(await Auth.idToken(forceRefresh: true), isNotEmpty);
    });

    test('is null again after sign-out', () async {
      await Auth.signInWithGoogle();
      await Auth.signOut();

      expect(await Auth.idToken(), isNull);
    });
  });
}
