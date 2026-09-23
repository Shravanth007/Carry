import 'dart:io';

import 'package:carry/auth/auth.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/permissions/permissions.dart';
import 'package:carry/recording/recorder.dart';
import 'package:carry/recording/recording.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';
import '../helpers/test_recorder.dart';

/// Who a recording belongs to is decided here, not on the server, so these
/// tests are about ownership rather than about the microphone.
void main() {
  late TestRecorder microphone;
  late TestAuth testAuth;

  setUp(() async {
    microphone = setUpTestRecorder();
    setUpTestPermissions(status: MicPermission.granted);
    testAuth = await setUpTestAuth(signedIn: true, uid: 'ada');
    Notes.clear();
  });

  testWidgets('signed out, nothing records', (tester) async {
    await Auth.signOut();

    expect(await Recording.begin(), 'Sign in to record.');
    expect(microphone.starts, 0);
    expect(Recording.inProgress, isFalse);
  });

  testWidgets('a saved note belongs to the account that started it', (
    tester,
  ) async {
    Recorder.clockForTesting = () => tester.binding.clock.now();
    expect(await Recording.begin(), isNull);
    await tester.pump(const Duration(seconds: 3));

    final result = await Recording.finish();

    expect(result.message, isNull);
    expect(Notes.all.value.single.ownerUid, 'ada');
  });

  testWidgets('a recording whose account changed mid-way is thrown away', (
    tester,
  ) async {
    Recorder.clockForTesting = () => tester.binding.clock.now();
    await Recording.begin();
    await tester.pump(const Duration(seconds: 3));

    // Someone else signs in while it is still running.
    await testAuth.firebase.signOut();
    Auth.firebaseForTesting = TestFirebaseAuth(signedIn: true, uid: 'grace');

    final result = await Recording.finish();

    expect(result.message, contains('the account changed'));
    expect(result.stillRecording, isFalse);
    expect(Notes.all.value, isEmpty);
    expect(File(microphone.startedPath!).existsSync(), isFalse);
  });

  testWidgets('signing out mid-recording leaves no file behind', (
    tester,
  ) async {
    Recorder.clockForTesting = () => tester.binding.clock.now();
    await Recording.begin();
    await tester.pump(const Duration(seconds: 3));
    await Auth.signOut();

    final result = await Recording.finish();

    expect(result.message, contains('the account changed'));
    expect(Notes.all.value, isEmpty);
    expect(File(microphone.startedPath!).existsSync(), isFalse);
  });
}
