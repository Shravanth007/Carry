import 'dart:async';

import 'package:carry/analytics/analytics.dart';
import 'package:carry/api/api.dart';
import 'package:carry/auth/auth.dart';
import 'package:carry/limits.dart';
import 'package:carry/notes/audio_import.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/permissions/permissions.dart';
import 'package:carry/recording/recorder.dart';
import 'package:carry/recording/recording.dart';
import 'package:carry/session.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/test_analytics.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';
import '../helpers/test_files.dart';
import '../helpers/test_recorder.dart';

/// What the app reports about itself, checked where it is decided: in the
/// facades, not in the screens.
void main() {
  late TestAnalytics events;

  setUp(() {
    events = setUpTestAnalytics();
    setUpTestPrefs();
    Notes.clear();
  });

  group('signing in', () {
    test('a sign-in is counted, and the account is identified', () async {
      final testAuth = await setUpTestAuth();
      testAuth.google.onAuthenticate = () async => googleUser;

      await Auth.signInWithGoogle();

      expect(events.names(), containsAllInOrder(['sign_in_started']));
      expect(events.identified, ['firebase-uid']);
      expect(events.has('sign_in_succeeded'), isTrue);
    });

    test('closing the picker is counted as cancelled, not failed', () async {
      final testAuth = await setUpTestAuth();
      testAuth.google.onAuthenticate = () async =>
          throw googleError(GoogleSignInExceptionCode.canceled);

      await Auth.signInWithGoogle();

      expect(events.has('sign_in_cancelled'), isTrue);
      expect(events.has('sign_in_failed'), isFalse);
      expect(events.identified, isEmpty);
    });

    test('a failure carries a code, never the error text', () async {
      final testAuth = await setUpTestAuth();
      testAuth.google.onAuthenticate = () async =>
          throw googleError(GoogleSignInExceptionCode.clientConfigurationError);

      await expectLater(Auth.signInWithGoogle(), throwsA(isA<Object>()));

      expect(events.only('sign_in_failed').properties, {
        'reason': 'clientConfigurationError',
      });
    });

    test('signing out is counted as this account, then forgotten', () async {
      await setUpTestAuth(signedIn: true);

      await signOutAndForget();

      expect(events.has('signed_out'), isTrue);
      expect(events.resets, 1);
    });
  });

  group('recording', () {
    late TestRecorder microphone;

    setUp(() async {
      microphone = setUpTestRecorder();
      setUpTestPermissions(status: MicPermission.granted);
      await setUpTestAuth(signedIn: true, uid: 'ada');
    });

    testWidgets('a saved recording says how long, how big and why it ended', (
      tester,
    ) async {
      Recorder.clockForTesting = () => tester.binding.clock.now();
      await Recording.begin();
      await tester.pump(const Duration(seconds: 30));

      await Recording.finish(stoppedBy: 'length_limit');

      expect(events.has('recording_started'), isTrue);
      expect(events.only('recording_saved').properties, {
        'seconds': 30,
        'size': Analytics.sizeBucket(microphone.bytes),
        'stopped_by': 'length_limit',
        'notes_after': '1',
      });
    });

    testWidgets('a refusal says which refusal it was', (tester) async {
      await Auth.signOut();

      await Recording.begin();

      expect(events.only('recording_start_failed').properties, {
        'reason': 'signed_out',
      });
    });

    testWidgets('a blocked microphone is a different reason', (tester) async {
      setUpTestPermissions(status: MicPermission.blocked).answer =
          PermissionStatus.permanentlyDenied;

      await Recording.begin();

      expect(events.only('recording_start_failed').properties, {
        'reason': 'mic_blocked',
      });
    });

    testWidgets('throwing one away says who threw it', (tester) async {
      Recorder.clockForTesting = () => tester.binding.clock.now();
      await Recording.begin();
      await tester.pump(const Duration(seconds: 8));

      await Recording.throwAway();

      expect(events.only('recording_discarded').properties, {
        'seconds': 8,
        'by': 'user',
      });
    });

    testWidgets('tearing down with nothing running counts no discard', (
      tester,
    ) async {
      // abandon() runs whenever the bar goes away, recording or not.
      await Recording.abandon();

      expect(events.has('recording_discarded'), isFalse);
    });

    testWidgets('a pause the recorder ignored is not counted', (tester) async {
      Recorder.clockForTesting = () => tester.binding.clock.now();
      await Recording.begin();
      await tester.pump(const Duration(seconds: 3));
      // The recording ends while a pause is still in flight, so the recorder
      // drops the answer: nothing paused, so nothing is counted.
      microphone.pauseGate = Completer<void>();
      final pausing = Recording.pauseOrResume();
      await Recording.finish();
      microphone.pauseGate!.complete();
      await pausing;

      expect(events.has('recording_paused'), isFalse);
    });

    testWidgets('a recording lost to an account change is counted', (
      tester,
    ) async {
      Recorder.clockForTesting = () => tester.binding.clock.now();
      await Recording.begin();
      await tester.pump(const Duration(seconds: 12));
      Auth.firebaseForTesting = MockFirebaseAuth(signedIn: true);

      await Recording.finish();

      expect(events.has('recording_dropped_account_changed'), isTrue);
      expect(events.has('recording_saved'), isFalse);
    });
  });

  group('importing', () {
    test(
      'a rejected file says why, with its type but never its name',
      () async {
        final picker = setUpTestFilePicker();
        picker.pick = testFile('holiday-plans.txt', bytes: 10);

        await importAudio();

        expect(events.only('import_rejected').properties, {
          'reason': 'wrong_type',
          'extension': 'txt',
        });
        expect(
          events.only('import_rejected').properties.values,
          isNot(contains('holiday-plans')),
        );
      },
    );

    test('a name pretending to be an extension is reported as other', () async {
      final picker = setUpTestFilePicker();
      // The part after the last dot is only an extension by convention. Here
      // it is somebody's name, and it must not leave the phone.
      picker.pick = testFile('appointment.v1-Dr-Rao', bytes: 10);

      await importAudio();

      expect(events.only('import_rejected').properties, {
        'reason': 'wrong_type',
        'extension': 'other',
      });
    });

    test('a file over the cap is counted as too large', () async {
      final picker = setUpTestFilePicker();
      picker.pick = testFile('long.m4a', bytes: Limits.uploadBytes + 1);

      await importAudio();

      expect(events.only('import_rejected').properties, {
        'reason': 'too_large',
        'extension': 'm4a',
        'size': '25MB+',
      });
    });
  });

  group('the server', () {
    setUp(() async {
      await setUpTestAuth(signedIn: true);
    });

    tearDown(() => Api.client = http.Client());

    test('a refused call is counted with its status and request id', () async {
      Api.client = MockClient(
        (_) async => http.Response(
          '{"detail":"Slow down."}',
          429,
          headers: {'x-request-id': 'abc123'},
        ),
      );

      await expectLater(Api.me(), throwsA(isA<ApiFailure>()));

      expect(events.only('api_failed').properties, {
        'endpoint': '/me',
        'kind': 'rate_limited',
        'status': 429,
        'request_id': 'abc123',
      });
    });

    test('being offline is counted without an exception message', () async {
      Api.client = MockClient(
        (_) async => throw http.ClientException('Failed host lookup: carry'),
      );

      await expectLater(Api.me(), throwsA(isA<ApiFailure>()));

      final failure = events.only('api_failed').properties;
      expect(failure['kind'], 'offline');
      expect(failure['endpoint'], '/me');
      expect(failure.toString(), isNot(contains('host lookup')));
    });

    test('every request carries an id the server can log', () async {
      final ids = <String?>[];
      Api.client = MockClient((request) async {
        ids.add(request.headers['X-Request-ID']);
        return http.Response('{"detail":"no"}', 500);
      });

      await expectLater(Api.me(), throwsA(isA<ApiFailure>()));

      expect(ids.single, isNotNull);
      expect(ids.single, matches(RegExp(r'^[A-Za-z0-9-]{1,64}$')));
    });
  });
}
