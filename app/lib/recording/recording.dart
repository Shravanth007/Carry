import 'package:flutter/foundation.dart';

import '../auth/auth.dart';
import '../limits.dart';
import '../notes/notes.dart';
import '../permissions/permissions.dart';
import 'recorder.dart';

/// Every recording call in the app goes through here: the microphone
/// permission, the hardware, and turning what was recorded into a note.
///
/// The screens only draw. They never talk to [Recorder] or [Permissions]
/// themselves, so there is one place that knows what recording means and one
/// set of sentences for when it goes wrong.
abstract final class Recording {
  /// Who started the recording that is running. Captured at the start, not
  /// at the end: a recording belongs to whoever spoke into it, and the
  /// account can change while it runs.
  static String? _startedBy;

  static bool get inProgress => Recorder.isRecording;

  static bool get isPaused => Recorder.isPaused;

  static Duration get elapsed => Recorder.elapsed;

  /// True once a recording has run as long as one is allowed to. The bar
  /// stops it and keeps what it has: a recording that grew past what can be
  /// uploaded would be a recording nobody can transcribe.
  static bool get atLimit => inProgress && elapsed >= Limits.recording;

  /// How loud it is now, 0 to 1. Silent while paused.
  static Future<double> level() async {
    if (!inProgress || isPaused) return 0;
    try {
      return await Recorder.level();
    } catch (e) {
      debugPrint('Could not read the level: $e');
      return 0;
    }
  }

  /// Asks for the microphone if needed and starts recording.
  ///
  /// Returns null when it started, or a sentence to show the user.
  static Future<String?> begin() async {
    // Nothing is recorded without an account to own it. The server will check
    // the same thing again from the token: this is only so the person is told
    // now, rather than losing the recording later.
    final uid = Auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return 'Sign in to record.';
    }
    var mic = await Permissions.micStatus();
    if (mic != MicPermission.granted) mic = await Permissions.requestMic();
    if (mic != MicPermission.granted) {
      return "Carry can't record without the microphone. "
          'Turn it on in Settings → Permissions.';
    }
    try {
      await Recorder.start();
      _startedBy = uid;
      return null;
    } catch (e) {
      debugPrint('Could not start recording: $e');
      return "Carry couldn't start recording. Try again.";
    }
  }

  /// Returns null when it worked, or a sentence to show the user.
  static Future<String?> pauseOrResume() async {
    try {
      if (isPaused) {
        await Recorder.resume();
      } else {
        await Recorder.pause();
      }
      return null;
    } catch (e) {
      debugPrint('Could not pause or resume: $e');
      return isPaused
          ? "Carry couldn't carry on recording. Try again."
          : "Carry couldn't pause. The recording is still running.";
    }
  }

  /// Stops and keeps what was recorded.
  ///
  /// Returns null when a note was saved, or a sentence to show the user.
  /// [stillRecording] says whether the microphone is still running, so a
  /// screen knows whether to keep its controls up.
  static Future<({String? message, bool stillRecording})> finish() async {
    final Finished? finished;
    try {
      finished = await Recorder.stop();
    } catch (e) {
      debugPrint('Could not stop recording: $e');
      // The microphone is still going, so the controls must stay.
      return (
        message: "Carry couldn't stop the recording. Try again.",
        stillRecording: inProgress,
      );
    }
    final owner = _startedBy;
    _startedBy = null;

    if (finished == null) {
      return (
        message: 'Too short to save. Hold on a little longer.',
        stillRecording: false,
      );
    }

    // The account changed while this was recording: signed out, or a
    // different person signed in. Attaching it to whoever is here now would
    // hand them someone else's words, so it goes no further.
    if (owner == null || owner != Auth.currentUser?.uid) {
      Recorder.deleteFile(finished.path);
      return (
        message:
            "That recording wasn't saved: the account changed while it "
            'was running.',
        stillRecording: false,
      );
    }

    Notes.addRecorded(
      ownerUid: owner,
      path: finished.path,
      duration: finished.duration,
      bytes: finished.bytes,
    );
    return (message: null, stillRecording: false);
  }

  /// Stops and deletes the file, because the user said to.
  static Future<void> throwAway() => _stopAndDrop();

  /// Stops and deletes the file because the recording has nowhere to go:
  /// the account signed out, or the screen holding it went away.
  static Future<void> abandon() => _stopAndDrop();

  static Future<void> _stopAndDrop() async {
    _startedBy = null;
    try {
      await Recorder.discard();
    } catch (e) {
      // Recorder.discard already drops the file and the state whatever
      // happens; this is only about not throwing at the caller.
      debugPrint('Could not discard cleanly: $e');
    }
  }
}
