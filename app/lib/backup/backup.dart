import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics.dart';
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
    return _readOn(uid);
  }

  /// When backup was switched on, or null while it's off.
  static Future<DateTime?> onSince() async {
    final uid = _uid;
    if (uid == null) return null;
    return _readSince(uid);
  }

  static Future<bool> _readOn(String uid) async =>
      await _prefs.getBool(_onKey(uid)) ?? false;

  static Future<DateTime?> _readSince(String uid) async {
    final millis = await _prefs.getInt(_sinceKey(uid));
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Turning it on stamps the moment. Turning it off clears the stamp, so
  /// turning it on again doesn't sweep up everything recorded in between.
  ///
  /// The stamp is written before the flag either way, so a half-finished
  /// change always lands on "don't upload": switching on leaves the flag
  /// false, and switching off leaves no stamp.
  static Future<void> setOn(bool on) async {
    final uid = _uid;
    if (uid == null) return;
    if (on) {
      await _prefs.setInt(
        _sinceKey(uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      await _prefs.remove(_sinceKey(uid));
    }
    await _prefs.setBool(_onKey(uid), on);
    // Sent from here, not from the switch: this is the line that decides the
    // setting changed, and any other caller must count too.
    Analytics.event('backup_toggled', {'on': on});
  }

  /// Whether a recording made at [addedAt] should be uploaded.
  ///
  /// Nothing uploads yet; this is the rule the upload queue will follow.
  ///
  /// Both answers have to agree, and both are read for the one account that
  /// was signed in when the question was asked. If that account is gone by
  /// the time they come back — signed out, or swapped for another — the
  /// answer is no, because it was the other person's answer.
  static Future<bool> shouldUpload(DateTime addedAt) async {
    final uid = _uid;
    if (uid == null) return false;
    final on = await _readOn(uid);
    final since = await _readSince(uid);
    if (_uid != uid) return false;
    return on && since != null && !addedAt.isBefore(since);
  }
}
