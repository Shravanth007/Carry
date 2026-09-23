import 'package:file_selector/file_selector.dart';

import '../limits.dart';
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
        // iOS filters by uniform type identifier and throws on a group that
        // gives it none, so the extension list alone doesn't reach the
        // picker there. The umbrella type covers every audio format the
        // phone knows; the extension check below is what actually decides.
        // Ignored on Android, which filters on the two lines above.
        uniformTypeIdentifiers: const ['public.audio'],
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
  if (bytes > Limits.uploadBytes) {
    return (
      note: null,
      error: 'That file is over ${Limits.uploadSize}. Pick a shorter one.',
    );
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
