import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:carry/permissions/permissions.dart';
import 'package:carry/settings/avatar_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A real 1x1 PNG, so `Image.memory` has something it can decode.
final testPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEh'
  'QGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Answers profile picture downloads with [bytes], or an error for [status].
/// Returns how many downloads were attempted.
List<Uri> setUpTestAvatarDownloads({Uint8List? bytes, int status = 200}) {
  final requests = <Uri>[];
  AvatarCache.client = MockClient((request) async {
    requests.add(request.url);
    return http.Response.bytes(bytes ?? testPngBytes, status);
  });
  addTearDown(() => AvatarCache.client = http.Client());
  return requests;
}

/// A phone with no connection, for profile picture downloads.
void goOffline() {
  AvatarCache.client = MockClient(
    (_) async => throw http.ClientException('offline'),
  );
  addTearDown(() => AvatarCache.client = http.Client());
}

/// Empty on-device storage for this test, so nothing leaks between tests.
void setUpTestPrefs() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
}

/// Stands in for the system permission prompts.
class TestPermissions extends PermissionHandlerPlatform {
  TestPermissions(this._status);

  PermissionStatus _status;

  /// What the user picks in the system prompt. Defaults to allowing.
  PermissionStatus answer = PermissionStatus.granted;

  /// Holds the system prompt open, so a test can take the screen away while
  /// it is still up.
  Completer<void>? prompt;

  int prompts = 0;
  int settingsOpened = 0;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      _status;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    prompts++;
    await prompt?.future; // a system prompt the test decides when to close
    _status = answer;
    return {for (final permission in permissions) permission: answer};
  }

  /// Whether the phone opens its settings page. False on web, for one.
  bool canOpenSettings = true;

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return canOpenSettings;
  }

  /// The user allowing the microphone in system Settings.
  void grantFromSettings() {
    _status = PermissionStatus.granted;
    answer = PermissionStatus.granted;
  }

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatus.enabled;

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async => true;
}

/// Points [Permissions] at the test prompts for the current test.
TestPermissions setUpTestPermissions({
  MicPermission status = MicPermission.denied,
}) {
  final permissions = TestPermissions(switch (status) {
    MicPermission.granted => PermissionStatus.granted,
    MicPermission.denied => PermissionStatus.denied,
    MicPermission.blocked => PermissionStatus.permanentlyDenied,
  });
  PermissionHandlerPlatform.instance = permissions;
  addTearDown(() => permissions.prompts = 0);
  return permissions;
}
