import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

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

/// A file the picker can hand back, without touching the disk.
XFile testFile(String name, {int bytes = 1024}) =>
    XFile.fromData(Uint8List(bytes), name: name, path: '/phone/$name');
