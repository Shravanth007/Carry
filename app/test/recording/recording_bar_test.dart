import 'dart:io';

import 'package:carry/notes/notes.dart';
import 'package:carry/permissions/permissions.dart';
import 'package:carry/recording/recorder.dart';
import 'package:carry/recording/recording.dart';
import 'package:carry/recording/recording_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';
import '../helpers/test_recorder.dart';

void main() {
  late TestRecorder microphone;
  String? finishedWith;
  var finishedTimes = 0;

  setUp(() async {
    microphone = setUpTestRecorder();
    setUpTestPermissions(status: MicPermission.granted);
    await setUpTestAuth(signedIn: true);
    Notes.clear();
    finishedWith = null;
    finishedTimes = 0;
  });

  /// Starts a recording and shows the bar, then lets it run for [seconds].
  Future<void> showBar(WidgetTester tester, {int seconds = 3}) async {
    Recorder.clockForTesting = () => tester.binding.clock.now();
    await Recording.begin();
    await pumpScreen(
      tester,
      Scaffold(
        bottomNavigationBar: RecordingBar(
          onFinished: (message) {
            finishedWith = message;
            finishedTimes++;
          },
        ),
      ),
    );
    await tester.pump(Duration(seconds: seconds));
  }

  testWidgets('counts the seconds up', (tester) async {
    await showBar(tester, seconds: 75);

    expect(find.text('01:15'), findsOneWidget);
  });

  group('pause', () {
    testWidgets('stops the clock', (tester) async {
      await showBar(tester, seconds: 5);

      await tester.tap(find.byTooltip('Pause recording'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));

      expect(find.text('00:05'), findsOneWidget, reason: 'still five seconds');
      expect(Recorder.isPaused, isTrue);
    });

    testWidgets('carries on from where it stopped', (tester) async {
      await showBar(tester, seconds: 5);
      await tester.tap(find.byTooltip('Pause recording'));
      await tester.pump(const Duration(seconds: 10));

      await tester.tap(find.byTooltip('Resume recording'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('00:08'), findsOneWidget, reason: '5 + 3, not 18');
    });

    testWidgets('saves only the recorded time, not the pause', (tester) async {
      await showBar(tester, seconds: 4);
      await tester.tap(find.byTooltip('Pause recording'));
      await tester.pump(const Duration(seconds: 30));
      await tester.tap(find.byTooltip('Resume recording'));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(Notes.all.value.single.duration!.inSeconds, 6);
    });
  });

  testWidgets('saving keeps the file and makes a note', (tester) async {
    await showBar(tester, seconds: 4);

    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));

    final note = Notes.all.value.single;
    expect(note.ownerUid, 'firebase-uid');
    expect(note.bytes, microphone.bytes);
    expect(File(note.path).existsSync(), isTrue);
    expect(finishedWith, isNull, reason: 'saved, so nothing to explain');
    expect(Recorder.isRecording, isFalse);
  });

  testWidgets('a mis-tap says why nothing was saved', (tester) async {
    await showBar(tester, seconds: 0);

    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(Notes.all.value, isEmpty);
    expect(finishedWith, 'Too short to save. Hold on a little longer.');
  });

  testWidgets('tapping Save twice saves one note', (tester) async {
    await showBar(tester, seconds: 4);

    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(Notes.all.value, hasLength(1));
    expect(microphone.stops, 1);
    expect(finishedTimes, 1);
  });

  group('when the phone misbehaves', () {
    testWidgets('a failed stop leaves the controls usable', (tester) async {
      await showBar(tester, seconds: 4);
      microphone.failOnStop = Exception('phone will not let go');

      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text("Carry couldn't stop the recording. Try again."),
        findsOneWidget,
      );
      expect(finishedTimes, 0, reason: 'the bar stays: nothing is finished');
      expect(Recorder.isRecording, isTrue, reason: 'still recording');
      final save = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save.onPressed, isNotNull, reason: 'and Save can be tried again');
    });

    testWidgets('a failed stop can be retried', (tester) async {
      await showBar(tester, seconds: 4);
      microphone.failOnStop = Exception('phone will not let go');
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 300));

      microphone.failOnStop = null;
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(Notes.all.value, hasLength(1));
      expect(finishedTimes, 1);
    });

    testWidgets('a failed pause says the recording is still running', (
      tester,
    ) async {
      await showBar(tester, seconds: 4);
      microphone.failOnPause = Exception('cannot pause');

      await tester.tap(find.byTooltip('Pause recording'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('still running'), findsOneWidget);
      expect(Recorder.isPaused, isFalse, reason: 'state matches the phone');
      expect(find.byTooltip('Pause recording'), findsOneWidget);
    });
  });

  group('when the bar goes away', () {
    testWidgets('leaving the app saves rather than losing it', (tester) async {
      await showBar(tester, seconds: 4);

      // Android can take the microphone back once Carry is out of sight.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(Notes.all.value, hasLength(1), reason: 'saved, not lost');
      expect(Recorder.isRecording, isFalse);
    });

    testWidgets('being torn down stops the microphone and drops the file', (
      tester,
    ) async {
      // What signing out does: the screen holding the bar disappears.
      await showBar(tester, seconds: 4);
      final path = microphone.startedPath!;

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(
        Recorder.isRecording,
        isFalse,
        reason: 'no recording without controls',
      );
      expect(microphone.cancels, 1);
      expect(File(path).existsSync(), isFalse);
      expect(Notes.all.value, isEmpty);
    });
  });

  group('throwing it away', () {
    testWidgets('asks first, and says how much would be lost', (tester) async {
      await showBar(tester, seconds: 7);

      await tester.tap(find.byTooltip('Throw recording away'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Throw this recording away?'), findsOneWidget);
      expect(find.textContaining('00:07'), findsWidgets);
      expect(Recorder.isRecording, isTrue, reason: 'still going until told');
    });

    testWidgets('keeps recording when the answer is no', (tester) async {
      await showBar(tester, seconds: 4);
      await tester.tap(find.byTooltip('Throw recording away'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Keep recording'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(Recorder.isRecording, isTrue);
      expect(Notes.all.value, isEmpty);
      expect(finishedTimes, 0);
    });

    testWidgets('deletes the file when the answer is yes', (tester) async {
      await showBar(tester, seconds: 4);
      final path = microphone.startedPath!;
      await tester.tap(find.byTooltip('Throw recording away'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Throw away'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(Notes.all.value, isEmpty);
      expect(File(path).existsSync(), isFalse);
      expect(finishedTimes, 1);
      expect(finishedWith, isNull, reason: 'they meant to throw it away');
    });
  });
}
