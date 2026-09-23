import 'package:flutter/foundation.dart';

import '../auth/auth.dart';

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

  static void add(Note note) => all.value = [note, ...all.value];

  /// Adds a note for something just recorded, titled by the time it was made.
  ///
  /// Takes plain values rather than the recorder's own type, so notes and
  /// recording don't depend on each other.
  static Note addRecorded({
    required String path,
    required Duration duration,
    required int bytes,
    String? ownerUid,
  }) {
    final now = DateTime.now();
    final note = Note(
      id: '${now.microsecondsSinceEpoch}',
      // Whoever started the recording, not whoever happens to be here now.
      ownerUid: ownerUid ?? owner,
      title: _recordedAt(now),
      path: path,
      addedAt: now,
      duration: duration,
      bytes: bytes,
    );
    add(note);
    return note;
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

  /// The uid to stamp on something being created now. Empty when signed out,
  /// which only happens in previews: the app can't reach the recorder or the
  /// importer without an account.
  static String get owner => Auth.currentUser?.uid ?? '';

  /// Drops every note. Used when an account signs out, so the next person
  /// never sees notes that aren't theirs.
  static void clear() => all.value = const [];
}
