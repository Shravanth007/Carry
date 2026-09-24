import 'package:flutter/foundation.dart';

import '../limits.dart';

/// Where a note's audio came from.
///
/// The rules are the same either way — the server can't tell the difference
/// and shouldn't have to. This only changes the wording when something is
/// refused, because "pick a shorter file" is no use to someone who was talking.
enum AudioSource { recorded, imported }

/// A voice note. Imported audio for now; recordings come later.
@immutable
class Note {
  const Note({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.path,
    required this.addedAt,
    this.duration,
    this.bytes,
  });

  final String id;

  /// Who it belongs to: the Firebase user ID, never anything typed in.
  /// Every note, and later every transcript, is filtered by this.
  final String ownerUid;

  /// What the user sees: the time it was recorded, or an imported file's name.
  final String title;

  /// Where the audio sits on the phone.
  final String path;

  final DateTime addedAt;

  /// Known for recordings. Null for imports until something reads the file.
  final Duration? duration;

  /// File size, which the upload queue will need.
  final int? bytes;
}

/// The notes shown on the home screen, newest first.
// ponytail: kept in memory, so notes are lost on restart. Swap the list for
// Drift when the database lands; nothing outside this file should change.
abstract final class Notes {
  static final ValueNotifier<List<Note>> all = ValueNotifier(const []);

  /// Private on purpose: everything comes through [addAudio], so there is no
  /// way to add a note that skipped the rules.
  static void _add(Note note) => all.value = [note, ...all.value];

  /// The one way audio becomes a note, recorded or imported.
  ///
  /// Both pipelines end here, so both are held to the same limits. The server
  /// treats a recording and an import identically — it only ever sees a file
  /// and an owner — so two sets of rules on this side would mean one of them
  /// was wrong.
  ///
  /// Returns the note, or a sentence to show the person. Takes plain values
  /// rather than the recorder's own type, so notes and recording don't depend
  /// on each other. [duration] is null for an import: nothing here reads an
  /// audio file's length, and the server works it out from the file itself.
  ///
  /// The caller owns the file. When this refuses, the caller deletes it.
  static ({Note? note, String? error}) addAudio({
    required AudioSource source,
    required String ownerUid,
    required String path,
    required int bytes,
    Duration? duration,
    String? title,
  }) {
    final recorded = source == AudioSource.recorded;

    // Every note carries the uid of whoever it belongs to. Without one there
    // is nobody to keep it for, and the server would refuse it anyway.
    if (ownerUid.isEmpty) {
      return (
        note: null,
        error: recorded
            ? 'Sign in to record.'
            : 'Sign in to import a recording.',
      );
    }
    if (bytes <= 0) {
      return (
        note: null,
        error: recorded
            ? 'Too short to save. Hold on a little longer.'
            : 'That file is empty. Pick another recording.',
      );
    }
    if (bytes > Limits.uploadBytes) {
      return (
        note: null,
        error: recorded
            ? "That recording is too big to keep. Carry can't send it on."
            : 'That file is over ${Limits.uploadSize}. Pick a shorter one.',
      );
    }
    if (duration != null && duration < Limits.shortest) {
      return (
        note: null,
        error: recorded
            ? 'Too short to save. Hold on a little longer.'
            : 'That recording is too short to keep.',
      );
    }
    if (duration != null && duration > Limits.recording) {
      return (
        note: null,
        error: 'That is longer than Carry can keep in one note.',
      );
    }

    final now = DateTime.now();
    final note = Note(
      id: '${now.microsecondsSinceEpoch}',
      ownerUid: ownerUid,
      title: title ?? _recordedAt(now),
      path: path,
      addedAt: now,
      duration: duration,
      bytes: bytes,
    );
    _add(note);
    return (note: note, error: null);
  }

  static String _recordedAt(DateTime when) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    return '${when.day} ${months[when.month - 1]}, $hour:$minute'
        '${when.hour < 12 ? 'am' : 'pm'}';
  }

  /// Drops every note. Used when an account signs out, so the next person
  /// never sees notes that aren't theirs.
  static void clear() => all.value = const [];
}
