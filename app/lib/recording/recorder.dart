import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../limits.dart';

/// Speech, not music: mono at 32 kbps keeps an hour of audio near 14 MB,
/// which is under the transcriber's 25 MB limit and cheap to upload.
/// 16 kHz is what the transcriber resamples to anyway.
const recordingConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 32000,
  sampleRate: 16000,
  numChannels: 1,
);

enum RecorderState { idle, recording, paused }

/// A recording that was finished and saved.
@immutable
class Finished {
  const Finished({
    required this.path,
    required this.duration,
    required this.bytes,
  });

  final String path;
  final Duration duration;
  final int bytes;
}

/// What the recorder needs from the phone. The real one wraps the `record`
/// package; tests put their own in its place.
abstract interface class RecorderBackend {
  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();

  /// The finished file's path, or null if the phone gave nothing back.
  Future<String?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  /// How loud it is right now, 0 (silence) to 1 (loud).
  Future<double> level();
}

/// Every recording call in the app goes through here.
abstract final class Recorder {
  static RecorderBackend? _backend;
  static String? _path;

  /// When the current run of recording began. Null while paused.
  static DateTime? _runningSince;

  /// Time from earlier runs, before the last pause.
  static Duration _before = Duration.zero;

  static RecorderState _state = RecorderState.idle;

  /// Bumped every time a recording starts or ends. A call that was waiting on
  /// the phone checks this before touching state: if the number moved, the
  /// recording it belonged to is over and its answer is stale.
  static int _session = 0;

  /// Tests swap in their own recorder and folder.
  @visibleForTesting
  static RecorderBackend? backendForTesting;

  /// Tests point this at a temporary folder.
  @visibleForTesting
  static Future<Directory> Function()? folderForTesting;

  /// Widget tests run on their own clock, so they lend it to the recorder.
  @visibleForTesting
  static DateTime Function()? clockForTesting;

  /// A clock that only goes forwards.
  ///
  /// The wall clock can jump: a phone syncing with the network, or somebody
  /// changing the time, would make a recording's duration wrong and could trip
  /// the length cap early. Durations come from a stopwatch instead, read as a
  /// time so the rest of the code is unchanged.
  static final Stopwatch _ticks = Stopwatch()..start();
  static final DateTime _startedAt = DateTime.now();

  static DateTime get _now =>
      clockForTesting?.call() ?? _startedAt.add(_ticks.elapsed);

  static RecorderBackend get _current =>
      backendForTesting ?? (_backend ??= _DeviceRecorder());

  static RecorderState get state => _state;

  static bool get isRecording => _state != RecorderState.idle;

  static bool get isPaused => _state == RecorderState.paused;

  /// How much audio there is so far, pauses not counted.
  static Duration get elapsed {
    final since = _runningSince;
    return since == null ? _before : _before + _now.difference(since);
  }

  static Future<Directory> _folder() async {
    final folder = folderForTesting != null
        ? await folderForTesting!()
        : Directory(
            '${(await getApplicationDocumentsDirectory()).path}'
            '${Platform.pathSeparator}recordings',
          );
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }

  /// A start that hasn't finished yet. A second caller waits for it rather
  /// than starting a rival recording on the same microphone.
  static Future<void>? _starting;

  /// Starts recording into the app's own folder. Throws if the phone refuses,
  /// which the caller turns into a message.
  ///
  /// Starting is serialised: two quick taps wait on one recording instead of
  /// racing, where the loser would cancel the winner's microphone and leave
  /// a screen that looks like it's recording but isn't.
  static Future<void> start() {
    final already = _starting;
    if (already != null) return already;
    if (isRecording) return Future<void>.value(); // already going
    final work = _startNow();
    _starting = work;
    // Clear it however it ends, so a failure doesn't block the next attempt.
    unawaited(
      work.then<void>((_) {}, onError: (_, _) {}).whenComplete(() {
        if (identical(_starting, work)) _starting = null;
      }),
    );
    return work;
  }

  static Future<void> _startNow() async {
    final mine = ++_session;
    final folder = await _folder();
    final name = _now.millisecondsSinceEpoch;
    final path = '${folder.path}${Platform.pathSeparator}$name.m4a';
    await _current.start(path);
    if (mine != _session) {
      // Something ended this recording while the phone was starting it.
      await _current.cancel();
      _delete(path);
      return;
    }
    _path = path;
    _before = Duration.zero;
    _runningSince = _now;
    _state = RecorderState.recording;
  }

  /// Keeps the file open and stops adding to it. The clock stops with it.
  static Future<void> pause() async {
    if (_state != RecorderState.recording) return;
    final mine = _session;
    // The phone first: if it refuses, our state must not claim it paused.
    await _current.pause();
    // The recording ended while we waited: this answer is about a recording
    // that no longer exists.
    if (mine != _session) return;
    _before = elapsed;
    _runningSince = null;
    _state = RecorderState.paused;
  }

  static Future<void> resume() async {
    if (_state != RecorderState.paused) return;
    final mine = _session;
    await _current.resume();
    if (mine != _session) return;
    _runningSince = _now;
    _state = RecorderState.recording;
  }

  static Future<double> level() => _current.level();

  /// Stops and keeps the file. Null when nothing usable was recorded, in
  /// which case the file is already gone.
  static Future<Finished?> stop() async {
    if (!isRecording) return null;
    final mine = _session;
    final duration = elapsed;
    final path = await _current.stop() ?? _path;
    if (mine != _session) return null; // something else already ended it
    _reset();

    if (path == null) return null;
    final file = File(path);
    // Sync on purpose: these are small local files, and async file I/O
    // never completes inside a widget test's fake clock.
    final bytes = file.existsSync() ? file.lengthSync() : 0;
    // An empty or barely-there file is a mis-tap or a refused microphone.
    if (bytes == 0 || duration < Limits.shortest) {
      _delete(path);
      return null;
    }
    return Finished(path: path, duration: duration, bytes: bytes);
  }

  /// Stops and deletes the file.
  static Future<void> discard() async {
    if (!isRecording) return;
    final path = _path;
    // Claim the end straight away: anything already waiting on the phone
    // must not put the state back afterwards.
    _session++;
    try {
      await _current.cancel();
    } finally {
      // Whatever the phone does, stop claiming a recording and drop the file.
      _reset();
      if (path != null) _delete(path);
    }
  }

  static void _reset() {
    _session++;
    _path = null;
    _runningSince = null;
    _before = Duration.zero;
    _state = RecorderState.idle;
  }

  /// Drops a file the caller decided not to keep, after it was finished.
  static void deleteFile(String path) => _delete(path);

  static void _delete(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      // A leftover file wastes space but breaks nothing.
      debugPrint('Could not delete $path: $e');
    }
  }
}

class _DeviceRecorder implements RecorderBackend {
  final _recorder = AudioRecorder();

  @override
  Future<void> start(String path) =>
      _recorder.start(recordingConfig, path: path);

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<double> level() async {
    final amplitude = await _recorder.getAmplitude();
    // The platform reports decibels, loudest at 0 and silence far below.
    // -45 dB is quiet-room quiet, so that's the bottom of the bar.
    const floor = -45.0;
    final current = amplitude.current.clamp(floor, 0.0);
    return (current - floor) / -floor;
  }
}
