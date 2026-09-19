import 'package:carry/notes/audio_import.dart';
import 'package:carry/notes/notes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_files.dart';

void main() {
  late TestFilePicker picker;

  setUp(() {
    picker = setUpTestFilePicker();
    Notes.clear();
  });

  test('adds the picked recording as a note', () async {
    picker.pick = testFile('Team standup.m4a');

    final result = await importAudio();

    expect(result.error, isNull);
    expect(result.note?.title, 'Team standup');
    expect(result.note?.path, '/phone/Team standup.m4a');
    expect(Notes.all.value.single.title, 'Team standup');
  });

  test('cancelling adds nothing and says nothing', () async {
    picker.pick = null;

    final result = await importAudio();

    expect(result.error, isNull);
    expect(result.note, isNull);
    expect(Notes.all.value, isEmpty);
  });

  test('newest import comes first', () async {
    picker.pick = testFile('First.m4a');
    await importAudio();
    picker.pick = testFile('Second.mp3');
    await importAudio();

    expect(Notes.all.value.map((n) => n.title), ['Second', 'First']);
  });

  group('rejects', () {
    test('a file that is not audio', () async {
      picker.pick = testFile('budget.pdf');

      final result = await importAudio();

      expect(result.error, "That isn't an audio file. Pick a recording.");
      expect(Notes.all.value, isEmpty);
    });

    test('a file with no extension', () async {
      picker.pick = testFile('recording');

      expect((await importAudio()).error, isNotNull);
    });

    test('an empty file', () async {
      picker.pick = testFile('silence.wav', bytes: 0);

      final result = await importAudio();

      expect(result.error, 'That file is empty. Pick another recording.');
      expect(Notes.all.value, isEmpty);
    });

    test('a file over the size limit', () async {
      picker.pick = testFile('marathon.m4a', bytes: maxImportBytes + 1);

      final result = await importAudio();

      expect(result.error, 'That file is over 200 MB. Pick a shorter one.');
      expect(Notes.all.value, isEmpty);
    });
  });

  test('accepts every audio type we transcribe', () async {
    for (final extension in audioExtensions) {
      picker.pick = testFile('note.$extension');

      expect(
        (await importAudio()).error,
        isNull,
        reason: '.$extension should import',
      );
    }
  });
}
