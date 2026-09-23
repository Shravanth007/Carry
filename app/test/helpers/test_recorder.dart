import 'dart:async';
import 'dart:io';

import 'package:carry/recording/recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the phone's microphone. Writes a real file, so everything
/// that reads size or deletes the recording behaves as it would on a phone.
class TestRecorder implements RecorderBackend {
  TestRecorder(this.folder);

  final Directory folder;

  /// What the level meter reports.
  double loudness = 0.5;

  /// Set to make starting fail, as a microphone held by another app does.
  Object? failOnStart;

  /// Set to make stopping fail, as a phone that won't let go does.
  Object? failOnStop;

  /// Set to make pausing fail.
  Object? failOnPause;

  /// Holds a pause open, so a test can land it after the recording ended.
  Completer<void>? pauseGate;

  /// Holds starting open, so a test can tap twice before the first finishes.
  Completer<void>? startGate;

  int starts = 0;

  /// Bytes written when the recording stops. Zero mimics a file the phone
  /// never actually wrote.
  int bytes = 4096;

  String? startedPath;
  int stops = 0;
  int cancels = 0;

  @override
  Future<void> start(String path) async {
    final failure = failOnStart;
    if (failure != null) throw failure;
    await startGate?.future;
    starts++;
    startedPath = path;
    File(path).writeAsBytesSync(<int>[]);
  }

  int pauses = 0;
  int resumes = 0;

  @override
  Future<void> pause() async {
    final failure = failOnPause;
    if (failure != null) throw failure;
    await pauseGate?.future;
    pauses++;
  }

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<String?> stop() async {
    final failure = failOnStop;
    if (failure != null) throw failure;
    stops++;
    final path = startedPath;
    if (path != null && bytes > 0) {
      File(path).writeAsBytesSync(List.filled(bytes, 0));
    }
    return path;
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<double> level() async => loudness;
}

/// Points [Recorder] at a test microphone and a temporary folder.
TestRecorder setUpTestRecorder() {
  final folder = Directory.systemTemp.createTempSync('carry_recordings');
  final recorder = TestRecorder(folder);
  Recorder.backendForTesting = recorder;
  Recorder.folderForTesting = () async => folder;
  addTearDown(() async {
    await Recorder.discard();
    Recorder.backendForTesting = null;
    Recorder.folderForTesting = null;
    Recorder.clockForTesting = null;
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });
  return recorder;
}
