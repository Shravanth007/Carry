/// What Carry lets you do, as far as the phone knows.
///
/// These are courtesies. They let the app say no straight away instead of
/// after a long upload, and they keep a recording inside what the pipeline
/// can actually carry. They are **not** protection: the repo is public, so
/// anyone can build a client that ignores every line of this file. The same
/// numbers are checked again on the server, from the token and from the file
/// it receives — `server/docs/security.md` is where the real ones live.
abstract final class Limits {
  /// The longest a recording may run. The bar stops and saves at this, and
  /// the server checks it again from the file. It is deliberately **not** a
  /// reason to throw audio away afterwards: a recording stopped at the cap is
  /// always a shade past it by the time it is written, and deleting an hour of
  /// someone's voice over a few milliseconds would be the worst answer
  /// available. About 14 MB at our bitrate, comfortably under [uploadBytes].
  static const recording = Duration(hours: 1);

  /// Anything shorter than this is a mis-tap, not a note.
  static const shortest = Duration(seconds: 1);

  /// One file, recorded or imported. The transcriber refuses anything bigger,
  /// so there is no point carrying it across the network first.
  static const uploadBytes = 25 * 1024 * 1024;

  /// For error messages: "25 MB".
  static String get uploadSize => '${uploadBytes ~/ (1024 * 1024)} MB';
}

/// What a plan allows, in the words the paywall uses.
///
/// Mirrors `server/app/services/plans.py`, which is the one that decides.
/// Here rather than inside the screen so the paywall, an "out of minutes"
/// message and anything else quote the same numbers, and so a price change on
/// the server is one edit here instead of a search through widgets.
///
/// Prices are **not** here: they come from the store, per country, and a
/// number typed into the app would be wrong for most of the world.
abstract final class Plans {
  static const free = (
    transcription: '1 hour of transcription a month',
    audio: 'Audio kept for 30 days',
  );

  static const plus = (
    transcription: '20 hours of transcription a month',
    audio: 'Audio kept for as long as you keep the plan',
  );
}
