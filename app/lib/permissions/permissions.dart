import 'package:permission_handler/permission_handler.dart';

import '../analytics/analytics.dart';

/// What the app can do about the microphone right now.
enum MicPermission {
  /// Recording is allowed.
  granted,

  /// Not allowed yet, but the system prompt can still be shown.
  denied,

  /// The system won't prompt again. Only Settings can change it.
  blocked,
}

/// Every permission call in the app goes through here.
abstract final class Permissions {
  /// The current microphone state. Never prompts.
  static Future<MicPermission> micStatus() async =>
      _read(await Permission.microphone.status);

  /// Shows the system prompt when allowed, and returns the state afterwards.
  ///
  /// [where] says which screen asked — onboarding, recording or settings — so
  /// it's possible to see which one people say no on.
  static Future<MicPermission> requestMic({required String where}) async {
    Analytics.event('mic_requested', {'where': where});
    final mic = _read(await Permission.microphone.request());
    Analytics.event('mic_result', {'where': where, 'status': mic.name});
    return mic;
  }

  /// Opens the app's page in system Settings, for a permission only the phone
  /// can change. False when the phone wouldn't open it (and always on web).
  static Future<bool> openSettings({required String where}) async {
    Analytics.event('mic_settings_opened', {'where': where});
    return openAppSettings();
  }

  static MicPermission _read(PermissionStatus status) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited ||
    PermissionStatus.provisional => MicPermission.granted,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => MicPermission.blocked,
    PermissionStatus.denied => MicPermission.denied,
  };
}
