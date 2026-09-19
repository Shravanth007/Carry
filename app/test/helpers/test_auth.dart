import 'package:carry/auth/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

const testEmail = 'ada@example.com';
const testIdToken = 'google-id-token';

const googleUser = AuthenticationResults(
  user: GoogleSignInUserData(email: testEmail, id: 'google-uid'),
  authenticationTokens: AuthenticationTokenData(idToken: testIdToken),
);

GoogleSignInException googleError(GoogleSignInExceptionCode code) =>
    GoogleSignInException(code: code);

/// Firebase testAuth that remembers the credential it was given.
class TestFirebaseAuth extends MockFirebaseAuth {
  TestFirebaseAuth({super.signedIn})
    : super(
        mockUser: MockUser(uid: 'firebase-uid', email: testEmail),
      );

  AuthCredential? lastCredential;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    lastCredential = credential;
    return super.signInWithCredential(credential);
  }
}

/// Test Google Sign-In platform used instead of the native plugin.
class TestGoogleSignIn extends GoogleSignInPlatform {
  /// What the account picker does when opened. Defaults to picking [googleUser].
  Future<AuthenticationResults> Function() onAuthenticate = () async =>
      googleUser;
  int signOutCalls = 0;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) =>
      onAuthenticate();

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  /// What signing out does. Defaults to succeeding.
  Future<void> Function()? onSignOut;

  @override
  Future<void> signOut(SignOutParams params) async {
    signOutCalls++;
    await onSignOut?.call();
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

typedef TestAuth = ({TestFirebaseAuth firebase, TestGoogleSignIn google});

/// Makes the next Google sign-out fail, as a dead network would.
void failNextSignOut(TestAuth testAuth) {
  testAuth.google.onSignOut = () async =>
      throw googleError(GoogleSignInExceptionCode.unknownError);
}

/// Points [Auth] at the test Firebase and Google for the current test.
/// Call from `setUp`.
Future<TestAuth> setUpTestAuth({bool signedIn = false}) async {
  final firebase = TestFirebaseAuth(signedIn: signedIn);
  final google = TestGoogleSignIn();
  GoogleSignInPlatform.instance = google;
  Auth.firebaseForTesting = firebase;
  addTearDown(() => Auth.firebaseForTesting = null);
  await Auth.init();
  return (firebase: firebase, google: google);
}
