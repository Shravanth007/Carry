import 'dart:async';
import 'dart:io';

import 'package:carry/recording/recorder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_recorder.dart';

void main() {
  late TestRecorder microphone;

  setUp(() => microphone = setUpTestRecorder());

  test('records into the app folder', () async {
    await Recorder.start();

    expect(Recorder.isRecording, isTrue);
    expect(microphone.startedPath, endsWith('.m4a'));
    expect(microphone.startedPath, startsWith(microphone.folder.path));
  });

  test('a second start changes nothing', () async {
    await Recorder.start();
    final first = microphone.startedPath;

    await Recorder.start();

    expect(microphone.startedPath, first, reason: 'still the same recording');
  });

  test('stopping keeps the file, its length and its size', () async {
    await Recorder.start();
    await Future<void>.delayed(
      Recorder.shortest + const Duration(milliseconds: 50),
    );

    final finished = await Recorder.stop();

    expect(finished, isNotNull);
    expect(File(finished!.path).existsSync(), isTrue);
    expect(finished.bytes, microphone.bytes);
    expect(finished.duration, greaterThanOrEqualTo(Recorder.shortest));
    expect(Recorder.isRecording, isFalse);
  });

  test('a mis-tap is thrown away rather than saved', () async {
    await Recorder.start();
    final path = microphone.startedPath!;

    final finished = await Recorder.stop(); // stopped immediately

    expect(finished, isNull, reason: 'shorter than a second');
    expect(File(path).existsSync(), isFalse, reason: 'and cleaned up');
  });

  test('a file the phone never wrote is thrown away', () async {
    microphone.bytes = 0;
    await Recorder.start();
    await Future<void>.delayed(
      Recorder.shortest + const Duration(milliseconds: 50),
    );

    expect(await Recorder.stop(), isNull);
  });

  test('discarding stops the phone and deletes the file', () async {
    await Recorder.start();
    final path = microphone.startedPath!;

    await Recorder.discard();

    expect(microphone.cancels, 1);
    expect(File(path).existsSync(), isFalse);
    expect(Recorder.isRecording, isFalse);
  });

  test('stopping when nothing is running is harmless', () async {
    expect(await Recorder.stop(), isNull);
    expect(microphone.stops, 0);
  });

  test(
    'a pause that lands after the recording ended cannot revive it',
    () async {
      // What backgrounding mid-pause does: the save stops the recorder while
      // the pause is still waiting on the phone.
      await Recorder.start();
      final phoneIsThinking = Completer<void>();
      microphone.pauseGate = phoneIsThinking;
      final pausing = Recorder.pause();
      await Recorder.discard(); // the recording ends underneath it

      phoneIsThinking.complete();
      await pausing;

      expect(
        Recorder.isRecording,
        isFalse,
        reason: 'a stale answer cannot revive it',
      );

      // And the next recording really starts, rather than being swallowed by
      // a leftover state.
      microphone.pauseGate = null;
      await Recorder.start();
      expect(Recorder.isRecording, isTrue);
      expect(Recorder.state, RecorderState.recording);
    },
  );

  test('a microphone held by another app fails loudly', () async {
    microphone.failOnStart = Exception('busy');

    await expectLater(Recorder.start(), throwsException);
    expect(Recorder.isRecording, isFalse, reason: 'nothing left half-started');
  });
}
