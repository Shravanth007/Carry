import 'dart:io';

import 'package:carry/limits.dart';
import 'package:carry/notes/audio_import.dart';
import 'package:carry/notes/notes.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_files.dart';

void main() {
  late TestFilePicker picker;

  late Directory imports;

  setUp(() {
    picker = setUpTestFilePicker();
    imports = setUpTestImportFolder();
    Notes.clear();
  });

  test('adds the picked recording as a note', () async {
    picker.pick = testFile('Team standup.m4a');

    final result = await importAudio();

    expect(result.error, isNull);
    expect(result.note?.title, 'Team standup');
    // Kept in the app's own storage, not left in the picker's cache copy,
    // which the phone is free to delete.
    final kept = result.note!.path;
    expect(kept, startsWith(imports.path));
    expect(File(kept).existsSync(), isTrue);
    expect(kept, endsWith('.m4a'));
    expect(Notes.all.value.single.title, 'Team standup');
  });

  test('a file that cannot be copied in is refused, not half-added', () async {
    picker.pick = testFile('Gone.m4a');
    // The picker's copy is deleted before the import reads it, which is what a
    // cache the phone just cleared looks like.
    File(picker.pick!.path).deleteSync();

    final result = await importAudio();

    expect(result.note, isNull);
    expect(result.error, "Carry couldn't save that recording. Try again.");
    expect(Notes.all.value, isEmpty);
    // And nothing half-written was left behind: nothing sweeps this folder.
    expect(imports.listSync(), isEmpty);
  });

  test('storage that will not give us a folder is a refusal too', () async {
    picker.pick = testFile('Standup.m4a');
    // No space, or storage the phone won't hand over. The person gets the same
    // sentence; they must not get an error nobody caught.
    importFolderForTesting = () async =>
        throw const FileSystemException('no space left on device');
    addTearDown(() => importFolderForTesting = null);

    final result = await importAudio();

    expect(result.note, isNull);
    expect(result.error, "Carry couldn't save that recording. Try again.");
    expect(Notes.all.value, isEmpty);
  });

  test('the original is left where it was', () async {
    picker.pick = testFile('Keep me.m4a');
    final source = picker.pick!.path;

    await importAudio();

    expect(File(source).existsSync(), isTrue);
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
      picker.pick = testFile('marathon.m4a', bytes: Limits.uploadBytes + 1);

      final result = await importAudio();

      expect(result.error, 'That file is over 25 MB. Pick a shorter one.');
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

  // Each platform reads a different field, and iOS throws outright on a group
  // that gives it no identifier. Dropping one would break that platform alone,
  // while every test here kept passing.
  test('asks for audio in terms every platform understands', () async {
    picker.pick = testFile('note.m4a');

    await importAudio();

    final XTypeGroup group = picker.lastTypeGroups!.single;
    expect(group.extensions, containsAll(audioExtensions));
    expect(group.mimeTypes, contains('audio/*'));
    expect(group.uniformTypeIdentifiers, contains('public.audio'));
  });
}
