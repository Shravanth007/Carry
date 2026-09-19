import 'package:permission_handler/permission_handler.dart';

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
  static Future<MicPermission> requestMic() async =>
      _read(await Permission.microphone.request());

  /// Opens the app's page in system Settings, for a permission only the phone
  /// can change. False when the phone wouldn't open it (and always on web).
  static Future<bool> openSettings() => openAppSettings();

  static MicPermission _read(PermissionStatus status) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited ||
    PermissionStatus.provisional => MicPermission.granted,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => MicPermission.blocked,
    PermissionStatus.denied => MicPermission.denied,
  };
}
