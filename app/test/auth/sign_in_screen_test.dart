import 'dart:async';

import 'package:carry/auth/auth.dart';
import 'package:carry/auth/sign_in_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    show AuthenticationResults;
import 'package:mock_exceptions/mock_exceptions.dart';

import '../helpers/pump.dart';
import '../helpers/test_auth.dart';

const genericError = "Couldn't sign in with Google. Try again.";
const networkError = 'No internet connection. Connect and try again.';

void main() {
  late TestAuth testAuth;

  setUp(() async => testAuth = await setUpTestAuth());

  final cta = find.text('Continue with Google');
  OutlinedButton button(WidgetTester tester) =>
      tester.widget(find.byType(OutlinedButton));

  testWidgets('shows the heading, CTA and privacy note', (tester) async {
    await pumpScreen(tester, const SignInScreen());

    expect(find.text('Carry'), findsOneWidget);
    expect(cta, findsOneWidget);
    expect(
      find.text('Carry only uses your Google account to sign you in.'),
      findsOneWidget,
    );
    expect(button(tester).onPressed, isNotNull);
  });

  testWidgets('shows a spinner and blocks taps while signing in', (
    tester,
  ) async {
    final picker = Completer<AuthenticationResults>();
    testAuth.google.onAuthenticate = () => picker.future;
    await pumpScreen(tester, const SignInScreen());

    await tester.tap(cta);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(cta, findsNothing);
    expect(button(tester).onPressed, isNull);

    picker.complete(googleUser);
    await tester.pumpAndSettle();

    expect(Auth.currentUser?.email, testEmail);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('closing the picker shows no error', (tester) async {
    testAuth.google.onAuthenticate = () async =>
        throw googleError(GoogleSignInExceptionCode.canceled);
    await pumpScreen(tester, const SignInScreen());

    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(find.text(genericError), findsNothing);
    expect(button(tester).onPressed, isNotNull);
    expect(Auth.currentUser, isNull);
  });

  testWidgets('shows the offline message on a network error', (tester) async {
    whenCalling(Invocation.method(#signInWithCredential, null))
        .on(testAuth.firebase)
        .thenThrow(FirebaseAuthException(code: 'network-request-failed'));
    await pumpScreen(tester, const SignInScreen());

    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(find.text(networkError), findsOneWidget);
    expect(button(tester).onPressed, isNotNull);
  });

  testWidgets('shows the generic message, then clears it on retry', (
    tester,
  ) async {
    testAuth.google.onAuthenticate = () async =>
        throw googleError(GoogleSignInExceptionCode.clientConfigurationError);
    await pumpScreen(tester, const SignInScreen());

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text(genericError), findsOneWidget);

    testAuth.google.onAuthenticate = () async => googleUser;
    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(find.text(genericError), findsNothing);
    expect(Auth.currentUser?.email, testEmail);
  });
}
