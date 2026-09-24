import 'dart:io';

import 'package:carry/auth/auth.dart';
import 'package:carry/limits.dart';
import 'package:carry/notes/audio_import.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/permissions/permissions.dart';
import 'package:carry/recording/recorder.dart';
import 'package:carry/recording/recording.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_analytics.dart';
import '../helpers/test_auth.dart';
import '../helpers/test_device.dart';
import '../helpers/test_files.dart';
import '../helpers/test_recorder.dart';

/// A recording and an import are the same thing by the time they are a note:
/// the server only ever sees a file and an owner. These check the two paths
/// can't drift apart.
void main() {
  late TestFilePicker picker;
  late TestRecorder microphone;

  setUp(() async {
    picker = setUpTestFilePicker();
    setUpTestImportFolder();
    microphone = setUpTestRecorder();
    setUpTestPermissions(status: MicPermission.granted);
    setUpTestAnalytics();
    await setUpTestAuth(signedIn: true, uid: 'ada');
    Notes.clear();
  });

  group('both paths', () {
    testWidgets('produce a note with the same fields filled in', (
      tester,
    ) async {
      Recorder.clockForTesting = () => tester.binding.clock.now();
      await Recording.begin();
      await tester.pump(const Duration(seconds: 5));
      await Recording.finish();
      picker.pick = testFile('Standup.m4a', bytes: 2048);
      // Importing copies the file: real disk I/O, which a fake clock never
      // runs, so it needs the real event loop.
      await tester.runAsync(importAudio);

      final imported = Notes.all.value.first;
      final recorded = Notes.all.value.last;
      for (final note in [imported, recorded]) {
        expect(note.ownerUid, 'ada');
        expect(note.bytes, isNotNull);
        expect(note.path, isNotEmpty);
        expect(File(note.path).existsSync(), isTrue);
        expect(note.title, isNotEmpty);
      }
      // The only difference: a recording knows its length, an import doesn't
      // until the server reads the file.
      expect(recorded.duration, const Duration(seconds: 5));
      expect(imported.duration, isNull);
    });

    testWidgets('refuse audio with no owner', (tester) async {
      // Recording refuses before the microphone, importing before the picker.
      await Auth.signOut();

      expect(await Recording.begin(), 'Sign in to record.');
      final imported = (await tester.runAsync(importAudio))!;

      expect(imported.error, 'Sign in to import a recording.');
      expect(Notes.all.value, isEmpty);
    });

    test('refuse a file over the same size cap', () async {
      // The import is refused before it is copied; a recording of that size
      // would be refused by the same rule in Notes.addAudio.
      picker.pick = testFile('Long.m4a', bytes: Limits.uploadBytes + 1);
      final imported = await importAudio();

      final recorded = Notes.addAudio(
        source: AudioSource.recorded,
        ownerUid: 'ada',
        path: '/phone/too-big.m4a',
        bytes: Limits.uploadBytes + 1,
        duration: const Duration(minutes: 30),
      );

      expect(imported.note, isNull);
      expect(recorded.note, isNull);
      expect(imported.error, isNotNull);
      expect(recorded.error, isNotNull);
      expect(Notes.all.value, isEmpty);
    });

    test('refuse an empty file', () async {
      picker.pick = testFile('Nothing.m4a', bytes: 0);

      final imported = await importAudio();
      final recorded = Notes.addAudio(
        source: AudioSource.recorded,
        ownerUid: 'ada',
        path: '/phone/empty.m4a',
        bytes: 0,
        duration: const Duration(seconds: 5),
      );

      expect(imported.note, isNull);
      expect(recorded.note, isNull);
      expect(Notes.all.value, isEmpty);
    });
  });

  testWidgets('a recording too big to send is dropped, not half kept', (
    tester,
  ) async {
    Recorder.clockForTesting = () => tester.binding.clock.now();
    microphone.bytes = Limits.uploadBytes + 1; // a phone that wrote too much
    await Recording.begin();
    await tester.pump(const Duration(seconds: 5));

    final result = await Recording.finish();

    expect(result.message, contains('too big to keep'));
    expect(Notes.all.value, isEmpty);
    // No file left behind for a note that was never made.
    expect(File(microphone.startedPath!).existsSync(), isFalse);
  });
}
