import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth.dart';

/// Whether recordings are copied to Carry cloud, and from when.
///
/// Off until the person turns it on. Turning it on covers **new** recordings
/// only, so the moment it was switched on is stored alongside the flag: a
/// recording older than that was made under the old answer, and uploading it
/// later would be a surprise.
///
/// Stored per account on the phone, like the welcome flag, so two accounts on
/// one phone answer separately.
abstract final class Backup {
  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  static String? get _uid => Auth.currentUser?.uid;

  static String _onKey(String uid) => 'backup_on_$uid';
  static String _sinceKey(String uid) => 'backup_since_$uid';

  /// False when signed out, so nothing uploads without an owner.
  static Future<bool> isOn() async {
    final uid = _uid;
    if (uid == null) return false;
    return await _prefs.getBool(_onKey(uid)) ?? false;
  }

  /// When backup was switched on, or null while it's off.
  static Future<DateTime?> onSince() async {
    final uid = _uid;
    if (uid == null) return null;
    final millis = await _prefs.getInt(_sinceKey(uid));
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Turning it on stamps the moment. Turning it off clears the stamp, so
  /// turning it on again doesn't sweep up everything recorded in between.
  static Future<void> setOn(bool on) async {
    final uid = _uid;
    if (uid == null) return;
    await _prefs.setBool(_onKey(uid), on);
    if (on) {
      await _prefs.setInt(
        _sinceKey(uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      await _prefs.remove(_sinceKey(uid));
    }
  }

  /// Whether a recording made at [addedAt] should be uploaded.
  ///
  /// Nothing uploads yet; this is the rule the upload queue will follow.
  static Future<bool> shouldUpload(DateTime addedAt) async {
    final since = await onSince();
    return since != null && !addedAt.isBefore(since);
  }

  /// Forgets the answer. Called when an account signs out.
  static Future<void> clear() async {
    final uid = _uid;
    if (uid == null) return;
    await _prefs.remove(_onKey(uid));
    await _prefs.remove(_sinceKey(uid));
  }
}
