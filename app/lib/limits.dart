/// What Carry lets you do, as far as the phone knows.
///
/// These are courtesies. They let the app say no straight away instead of
/// after a long upload, and they keep a recording inside what the pipeline
/// can actually carry. They are **not** protection: the repo is public, so
/// anyone can build a client that ignores every line of this file. The same
/// numbers are checked again on the server, from the token and from the file
/// it receives — `server/docs/security.md` is where the real ones live.
abstract final class Limits {
  /// One recording. About 14 MB at our bitrate, comfortably under [uploadBytes].
  static const recording = Duration(hours: 1);

  /// One file, recorded or imported. The transcriber refuses anything bigger,
  /// so there is no point carrying it across the network first.
  static const uploadBytes = 25 * 1024 * 1024;

  /// For error messages: "25 MB".
  static String get uploadSize => '${uploadBytes ~/ (1024 * 1024)} MB';
}
