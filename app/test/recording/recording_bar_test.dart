import 'dart:io';

import 'package:carry/notes/notes.dart';
import 'package:carry/recording/recorder.dart';
import 'package:carry/recording/recording_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_recorder.dart';

void main() {
  late TestRecorder microphone;
  String? finishedWith;
  var finishedTimes = 0;

  setUp(() async {
    microphone = setUpTestRecorder();
    await setUpTestAuth(signedIn: true);
    Notes.clear();
    finishedWith = null;
    finishedTimes = 0;
  });

  /// Starts a recording and shows the bar, then lets it run for [seconds].
  Future<void> showBar(WidgetTester tester, {int seconds = 3}) async {
    Recorder.clockForTesting = () => tester.binding.clock.now();
    await Recorder.start();
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
