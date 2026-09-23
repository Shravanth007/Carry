import 'package:file_selector/file_selector.dart';

import '../analytics/analytics.dart';
import '../limits.dart';
import 'notes.dart';

/// File types other than audio that are worth knowing people tried.
///
/// Needed because the part after the last dot is only an extension by
/// convention: in "appointment.Rao" it is part of someone's name. Bounding it
/// by length was not enough — a short name passes a length check. So a type is
/// reported only if it is one of these or one of [audioExtensions], and
/// anything else is `other`. Nothing read from a file name can leave the phone.
const _otherKnownTypes = {
  'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp', // video: the common mistake
  'pdf', 'txt', 'doc', 'docx', 'csv', 'json', 'xml',
  'jpg', 'jpeg', 'png', 'heic', 'gif', 'webp',
  'zip', 'rar', '7z', 'mid', 'midi',
};

String _reportable(String extension) =>
    audioExtensions.contains(extension) || _otherKnownTypes.contains(extension)
    ? extension
    : 'other';

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
  Analytics.event('import_opened');
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
  if (file == null) {
    Analytics.event('import_cancelled');
    return _cancelled;
  }

  // Some pickers hand back a whole path as the name, so take the last segment
  // ourselves rather than trusting it.
  final name = file.name.split(RegExp(r'[\\/]')).last;
  final extension = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  if (!audioExtensions.contains(extension)) {
    // The extension, never the file name: "Chat with Dr Rao.m4a" is not ours
    // to send anywhere.
    Analytics.event('import_rejected', {
      'reason': 'wrong_type',
      'extension': _reportable(extension),
    });
    return (note: null, error: "That isn't an audio file. Pick a recording.");
  }

  final bytes = await file.length();
  if (bytes == 0) {
    Analytics.event('import_rejected', {
      'reason': 'empty',
      'extension': _reportable(extension),
    });
    return (note: null, error: 'That file is empty. Pick another recording.');
  }
  if (bytes > Limits.uploadBytes) {
    // How often this fires is how we find out whether the cap is wrong.
    Analytics.event('import_rejected', {
      'reason': 'too_large',
      'extension': _reportable(extension),
      'size': Analytics.sizeBucket(bytes),
    });
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
  Analytics.event('import_added', {
    'extension': _reportable(extension),
    'size': Analytics.sizeBucket(bytes),
    'notes_after': Analytics.countBucket(Notes.all.value.length),
  });
  return (note: note, error: null);
}
