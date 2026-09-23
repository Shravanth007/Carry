import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the Google profile picture on the phone.
///
/// The picture never changes between launches, so fetching it every time is
/// wasted work and leaves the account card blank when offline. It's a
/// thumbnail, so it's small enough to sit in the phone's key-value storage
/// next to the other small flags.
///
/// This is the one HTTP call outside `api/`: the URL comes from Google, it
/// carries no Carry token, and nothing about it belongs in the API client.
abstract final class AvatarCache {
  static const _bytesKey = 'avatar_bytes';
  static const _urlKey = 'avatar_url';

  /// A profile thumbnail, not a photo library. Google's are a few KB, and
  /// this is stored as text in the phone's small key-value store, so the cap
  /// stays low.
  static const maxBytes = 64 * 1024;

  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  /// Tests swap in their own HTTP client here.
  @visibleForTesting
  static http.Client client = http.Client();

  /// The picture for [url], from the phone when it's already there.
  ///
  /// Returns null only when there's nothing saved and the download fails.
  /// A saved picture is used even when the URL has changed and the new one
  /// can't be fetched: a slightly old face beats an empty circle.
  static Future<Uint8List?> load(String url) async {
    final saved = await _prefs.getString(_bytesKey);
    final savedUrl = await _prefs.getString(_urlKey);
    if (saved != null && savedUrl == url) return base64Decode(saved);

    final fresh = await _download(url);
    if (fresh == null) return saved == null ? null : base64Decode(saved);

    await _prefs.setString(_bytesKey, base64Encode(fresh));
    await _prefs.setString(_urlKey, url);
    return fresh;
  }

  /// Forgets the saved picture. Call when an account signs out.
  static Future<void> clear() async {
    try {
      await _prefs.remove(_bytesKey);
      await _prefs.remove(_urlKey);
    } catch (e) {
      // The person is already signed out; a storage hiccup shouldn't show up
      // as a failed sign-out. The next account's URL won't match anyway.
      debugPrint('Clearing the saved profile picture failed: $e');
    }
  }

  static Future<Uint8List?> _download(String url) async {
    try {
      final response = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.isEmpty ||
          bytes.length > maxBytes) {
        return null;
      }
      return bytes;
    } catch (e) {
      // Offline, a bad URL, a timeout: the caller falls back to the initial.
      debugPrint('Profile picture download failed: $e');
      return null;
    }
  }
}
