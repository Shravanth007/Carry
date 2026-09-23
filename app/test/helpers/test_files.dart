import 'dart:io';
import 'dart:typed_data';

import 'package:carry/notes/audio_import.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the system file picker.
class TestFilePicker extends FileSelectorPlatform {
  /// What the picker returns. Null means the user cancelled.
  XFile? pick;

  /// The filter the app asked for, so a test can check what it requests.
  List<XTypeGroup>? lastTypeGroups;

  int opens = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opens++;
    lastTypeGroups = acceptedTypeGroups;
    return pick;
  }
}

/// Points the app's file picking at [TestFilePicker] for the current test.
TestFilePicker setUpTestFilePicker() {
  final picker = TestFilePicker();
  FileSelectorPlatform.instance = picker;
  return picker;
}

/// A file the picker can hand back.
///
/// Written to a real temporary file, because importing copies it into the
/// app's own storage now. Still carries its bytes, so reading its length costs
/// no disk I/O — which a widget test's fake clock would never finish.
XFile testFile(String name, {int bytes = 1024}) {
  final folder = Directory.systemTemp.createTempSync('carry_picked');
  addTearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });
  final path = '${folder.path}${Platform.pathSeparator}$name';
  File(path).writeAsBytesSync(Uint8List(bytes));
  return XFile.fromData(Uint8List(bytes), name: name, path: path);
}

/// Points imports at a temporary folder for the current test, and says where.
Directory setUpTestImportFolder() {
  final folder = Directory.systemTemp.createTempSync('carry_imports');
  importFolderForTesting = () async => folder;
  addTearDown(() {
    importFolderForTesting = null;
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });
  return folder;
}
