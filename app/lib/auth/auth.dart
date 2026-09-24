import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../analytics/analytics.dart';
import '../billing/billing.dart';

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

  /// Null when signed out, and also when Firebase was never started — which
  /// is how widget previews run. `main()` awaits `Firebase.initializeApp`
  /// before the app builds, so a real app can't reach this any other way.
  static User? get currentUser {
    try {
      return _firebase.currentUser;
    } catch (e) {
      debugPrint('No Firebase, treating as signed out: $e');
      return null;
    }
  }

  static Stream<User?> get userChanges => _firebase.authStateChanges();

  /// Firebase ID token to send to the Carry server as
  /// `Authorization: Bearer <token>`. Null when signed out.
  /// The SDK refreshes it before expiry. After a 401, retry once with
  /// [forceRefresh].
  static Future<String?> idToken({bool forceRefresh = false}) async =>
      await currentUser?.getIdToken(forceRefresh);

  /// Returns null when the user closes the Google account picker.
  static Future<UserCredential?> signInWithGoogle() async {
    Analytics.event('sign_in_started');
    try {
      final account = await _google.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      final signedIn = await _firebase.signInWithCredential(credential);
      _recordSignIn(signedIn);
      return signedIn;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // Closing the picker isn't a failure. It's still worth counting: a
        // screen people back out of is a screen worth looking at.
        Analytics.event('sign_in_cancelled');
        return null;
      }
      Analytics.event('sign_in_failed', {'reason': failureCode(e)});
      rethrow;
    } catch (e) {
      // Firebase can refuse a credential Google was happy with.
      Analytics.event('sign_in_failed', {'reason': failureCode(e)});
      rethrow;
    }
  }

  /// True only for an account signing in for the first time ever.
  ///
  /// Firebase stamps both times from its own clock when it creates an account,
  /// so they match until that account signs in a second time — including after
  /// a reinstall or on a new phone. Unknown times count as existing, so a
  /// returning account is never treated as new.
  static bool isNewAccount(User user) {
    final created = user.metadata.creationTime;
    final lastSignIn = user.metadata.lastSignInTime;
    if (created == null || lastSignIn == null) return false;
    return lastSignIn.difference(created).abs() < const Duration(minutes: 1);
  }

  /// Counting a sign-in must never be the reason a sign-in fails, so anything
  /// this touches is allowed to go wrong quietly.
  static void _recordSignIn(UserCredential signedIn) {
    bool? isNew;
    try {
      final user = signedIn.user;
      if (user != null) {
        isNew = isNewAccount(user);
        Analytics.identify(
          user.uid,
          isNewAccount: isNew,
          since: user.metadata.creationTime,
        );
      }
    } catch (e) {
      debugPrint("Couldn't read the account for analytics: $e");
    }
    Analytics.event('sign_in_succeeded', {'is_new_account': isNew});
    // Purchases are tied to the same uid the server keys everything on. A
    // purchase made under a different id is one the server can't credit.
    final signedInUser = signedIn.user;
    if (signedInUser != null) unawaited(Billing.identify(signedInUser.uid));
  }

  /// A short code for why a sign-in failed, for events and logs. Never the
  /// error's text: that can carry a path or a URL.
  @visibleForTesting
  static String failureCode(Object error) => switch (error) {
    GoogleSignInException() => error.code.name,
    FirebaseAuthException() => error.code,
    _ => error.runtimeType.toString(),
  };

  /// Firebase first, so the app flips to signed out immediately: that call is
  /// local and instant, while Google's can take a moment. Google follows, so
  /// the account picker shows again next time.
  static Future<void> signOut() async {
    await _firebase.signOut();
    await _google.signOut();
  }

  /// What to show the user when a sign-in fails. Kept here so every screen
  /// says the same thing.
  static String messageFor(Object error) {
    final offline =
        error is FirebaseAuthException &&
        error.code == 'network-request-failed';
    return offline
        ? 'No internet connection. Connect and try again.'
        : "Couldn't sign in with Google. Try again.";
  }
}

/// Shows the sign-in screen when signed out, [signedIn] otherwise.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.signedIn});

  final Widget Function(User user) signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _watch;

  /// Null until the first answer arrives. Kept so the sign-in screen is
  /// counted when someone arrives at it, not every time this rebuilds.
  bool? _wasSignedOut;

  @override
  void initState() {
    super.initState();
    // Screens pushed above the gate (settings, permissions) belong to the
    // signed-in app. Swapping what the gate shows doesn't remove them, so
    // close them here. Covers sign-out from anywhere, and a session that
    // ends on its own.
    _watch = Auth.userChanges.listen((user) {
      final signedOut = user == null;
      if (signedOut != _wasSignedOut) {
        _wasSignedOut = signedOut;
        if (signedOut) {
          // However the session ended — signed out here, revoked by Firebase,
          // the account deleted — this is the moment the app stops being that
          // person, so analytics stops being them too. One place owns it, so
          // an expired session can't leave events attributed to whoever was
          // here last.
          Analytics.reset();
          unawaited(Billing.forget());
          Analytics.screen('sign_in');
        }
      }
      if (user != null || !mounted) return;
      final navigator = Navigator.maybeOf(context);
      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: Auth.userChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold();
        }
        final user = snapshot.data;
        return user == null ? const SignInScreen() : widget.signedIn(user);
      },
    );
  }
}
