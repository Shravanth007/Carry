import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'sign_in_screen.dart';

/// Every auth call in the app goes through here.
abstract final class Auth {
  static FirebaseAuth? _firebaseOverride;
  static FirebaseAuth get _firebase =>
      _firebaseOverride ?? FirebaseAuth.instance;
  static final _google = GoogleSignIn.instance;

  /// Tests swap in a test Firebase here. Google is swapped through
  /// `GoogleSignInPlatform.instance`.
  @visibleForTesting
  static set firebaseForTesting(FirebaseAuth? auth) => _firebaseOverride = auth;

  /// Call once after Firebase.initializeApp.
  // On Android the server client ID is read from google-services.json.
  static Future<void> init() => _google.initialize();

  static User? get currentUser => _firebase.currentUser;

  static Stream<User?> get userChanges => _firebase.authStateChanges();

  /// Firebase ID token to send to the Carry server as
  /// `Authorization: Bearer <token>`. Null when signed out.
  /// The SDK refreshes it before expiry. After a 401, retry once with
  /// [forceRefresh].
  static Future<String?> idToken({bool forceRefresh = false}) async =>
      await currentUser?.getIdToken(forceRefresh);

  /// Returns null when the user closes the Google account picker.
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      final account = await _google.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      return await _firebase.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Signs out of Google too, so the account picker shows again next time.
  static Future<void> signOut() =>
      Future.wait([_firebase.signOut(), _google.signOut()]);
}

/// Shows the sign-in screen when signed out, [signedIn] otherwise.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.signedIn});

  final Widget Function(User user) signedIn;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: Auth.userChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold();
        }
        final user = snapshot.data;
        return user == null ? const SignInScreen() : signedIn(user);
      },
    );
  }
}
