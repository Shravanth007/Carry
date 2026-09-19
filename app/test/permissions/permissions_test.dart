import 'package:carry/permissions/permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import '../helpers/test_device.dart';

void main() {
  test('reads the current state without prompting', () async {
    final permissions = setUpTestPermissions(status: MicPermission.granted);

    expect(await Permissions.micStatus(), MicPermission.granted);
    expect(permissions.prompts, 0);
  });

  test('allowing at the prompt grants the microphone', () async {
    final permissions = setUpTestPermissions();

    expect(await Permissions.requestMic(), MicPermission.granted);
    expect(await Permissions.micStatus(), MicPermission.granted);
    expect(permissions.prompts, 1);
  });

  test('denying at the prompt leaves it askable', () async {
    setUpTestPermissions().answer = PermissionStatus.denied;

    expect(await Permissions.requestMic(), MicPermission.denied);
  });

  test('"never ask again" is reported as blocked', () async {
    setUpTestPermissions().answer = PermissionStatus.permanentlyDenied;

    expect(await Permissions.requestMic(), MicPermission.blocked);
  });

  test('a restricted phone (parental controls) is blocked', () async {
    setUpTestPermissions(status: MicPermission.granted).answer =
        PermissionStatus.restricted;

    expect(await Permissions.requestMic(), MicPermission.blocked);
  });

  test('openSettings opens the app settings page', () async {
    final permissions = setUpTestPermissions(status: MicPermission.blocked);

    await Permissions.openSettings();

    expect(permissions.settingsOpened, 1);
  });
}
