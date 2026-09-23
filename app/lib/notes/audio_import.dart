import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

/// Where imported audio is kept, and tests point this at a temporary folder.
@visibleForTesting
Future<Directory> Function()? importFolderForTesting;

/// The app's own folder for imported audio.
///
/// It has to be the app's own storage. What the picker hands back on Android is
/// a copy in the cache directory (`{cacheDir}/{uuid}/{name}` — see
/// `file_selector_android`), and the system clears that whenever it wants
/// space, as does "Clear cache" in the phone's settings. A note pointing there
/// is a note whose audio can disappear.
Future<Directory> _importFolder() async {
  final folder = importFolderForTesting != null
      ? await importFolderForTesting!()
      : Directory(
          '${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}imports',
        );
  if (!folder.existsSync()) folder.createSync(recursive: true);
  return folder;
}

/// Where the copy will go. The name is ours, not the one from the phone, so
/// nothing about a file name reaches the disk layout either.
String _targetPath(Directory folder, String extension) =>
    '${folder.path}${Platform.pathSeparator}'
    '${DateTime.now().microsecondsSinceEpoch}.$extension';

/// Removes a file we started writing and then couldn't finish.
///
/// A copy that runs out of space leaves a partial file behind, and nothing
/// deletes the imports folder for us.
void _deletePartial(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (e) {
    debugPrint('Could not clean up $path: $e');
  }
}

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

  // Async on purpose: an import can be 25 MB, and copying that on the UI
  // isolate would freeze the screen while it ran.
  final kept = _targetPath(await _importFolder(), extension);
  try {
    await File(file.path).copy(kept);
  } catch (e) {
    debugPrint('Could not copy the imported file in: $e');
    _deletePartial(kept);
    Analytics.event('import_rejected', {
      'reason': 'could_not_copy',
      'extension': _reportable(extension),
    });
    return (
      note: null,
      error: "Carry couldn't save that recording. Try again.",
    );
  }

  final now = DateTime.now();
  final note = Note(
    id: '${now.microsecondsSinceEpoch}',
    ownerUid: Notes.owner,
    title: name.substring(0, name.length - extension.length - 1),
    path: kept,
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
