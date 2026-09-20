import 'package:file_selector/file_selector.dart';

import 'notes.dart';

/// Audio the transcriber can handle.
const audioExtensions = {
  'm4a',
  'mp3',
  'wav',
  'aac',
  'ogg',
  'opus',
  'flac',
  'amr',
  'wma',
};

/// Big enough for a long meeting, small enough to survive an upload.
const maxImportBytes = 200 * 1024 * 1024;

/// A finished import. Both fields are null when the user cancels.
/// [error] is shown to the user as written.
typedef ImportResult = ({Note? note, String? error});

const _cancelled = (note: null, error: null);

/// Asks for an audio file and adds it to [Notes].
///
/// The file comes from outside the app, so its type and size are checked here
/// rather than trusted: a file picker can hand back anything the user taps.
Future<ImportResult> importAudio() async {
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Audio',
        extensions: audioExtensions.toList(),
        mimeTypes: const ['audio/*'],
      ),
    ],
  );
  if (file == null) return _cancelled;

  // Some pickers hand back a whole path as the name, so take the last segment
  // ourselves rather than trusting it.
  final name = file.name.split(RegExp(r'[\\/]')).last;
  final extension = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  if (!audioExtensions.contains(extension)) {
    return (note: null, error: "That isn't an audio file. Pick a recording.");
  }

  final bytes = await file.length();
  if (bytes == 0) {
    return (note: null, error: 'That file is empty. Pick another recording.');
  }
  if (bytes > maxImportBytes) {
    return (note: null, error: 'That file is over 200 MB. Pick a shorter one.');
  }

  final now = DateTime.now();
  final note = Note(
    id: '${now.microsecondsSinceEpoch}',
    ownerUid: Notes.owner,
    title: name.substring(0, name.length - extension.length - 1),
    path: file.path,
    addedAt: now,
    bytes: bytes,
  );
  Notes.add(note);
  return (note: note, error: null);
}
