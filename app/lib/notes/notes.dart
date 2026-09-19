import 'package:flutter/foundation.dart';

/// A voice note. Imported audio for now; recordings come later.
@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.path,
    required this.addedAt,
  });

  final String id;

  /// What the user sees. The file name without its extension.
  final String title;

  /// Where the audio sits on the phone.
  final String path;

  final DateTime addedAt;
}

/// The notes shown on the home screen, newest first.
// ponytail: kept in memory, so notes are lost on restart. Swap the list for
// Drift when the database lands; nothing outside this file should change.
abstract final class Notes {
  static final ValueNotifier<List<Note>> all = ValueNotifier(const []);

  static void add(Note note) => all.value = [note, ...all.value];

  /// Drops every note. Used when an account signs out, so the next person
  /// never sees notes that aren't theirs.
  static void clear() => all.value = const [];
}
