import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Where events go. Swapped in tests, so nothing leaves the machine.
abstract interface class AnalyticsSink {
  void identify(String uid, Map<String, Object> onceOnly);
  void reset();
  void screen(String name);
  void event(String name, Map<String, Object> properties);
}

/// Every analytics call in the app goes through here.
///
/// Events are sent from the feature facades — [Analytics] is called by `Auth`,
/// `Recording`, `Permissions`, `Api` and friends, never from a widget's build
/// method. Those facades already work out what happened and why, so an event
/// sent from one can't disagree with the message the person was shown.
///
/// Nothing is sent unless a key was given at build time:
///   flutter run --dart-define=POSTHOG_KEY=phc_...
/// so development runs, tests and CI are silent by default.
///
/// **Never pass** a note title, a file name, a file path, an email address, a
/// display name, a token, or the text of an exception. Reasons are short codes
/// decided in code: `mic_blocked`, not "Carry can't record without...".
abstract final class Analytics {
  /// A PostHog project key is meant to be public — it can only write events —
  /// but it still comes from the build rather than the source, so a fork
  /// doesn't send its events into this project.
  static const _key = String.fromEnvironment('POSTHOG_KEY');

  /// Use `https://eu.i.posthog.com` for an EU project.
  static const _host = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );

  /// Drops everything until [init] finds a key. Tests put their own here.
  @visibleForTesting
  static AnalyticsSink sink = const _Silent();

  static bool get isOn => sink is! _Silent;

  /// What a test goes back to when it's done collecting.
  @visibleForTesting
  static const AnalyticsSink silentForTesting = _Silent();

  /// Starts PostHog if this build was given a key. Never throws: analytics
  /// failing is not a reason for the app not to open.
  static Future<void> init() async {
    if (_key.isEmpty) {
      debugPrint('No POSTHOG_KEY in this build: analytics off.');
      return;
    }
    try {
      final config = PostHogConfig(_key)
        ..host = _host
        // Filming someone's notes to find out which button they pressed is a
        // trade nobody agreed to.
        ..sessionReplay = false
        // Carry has no feature flags and no push, so neither should cost a
        // request or collect a device token.
        ..preloadFeatureFlags = false
        ..capturePushNotificationSubscriptions = false
        ..capturePushNotificationOpened = false;
      await Posthog().setup(config);
      sink = const _PostHog();
    } catch (e) {
      // A dead analytics SDK must not take the app down with it.
      debugPrint('PostHog would not start, carrying on without it: $e');
    }
  }

  /// Ties what follows to one account. [isNewAccount] is recorded once, so a
  /// person's first day stays their first day.
  static void identify(String uid, {bool? isNewAccount, DateTime? since}) {
    if (uid.isEmpty) return;
    sink.identify(uid, {
      'is_new_account': ?isNewAccount,
      'created_at': ?since?.toUtc().toIso8601String(),
    });
  }

  /// Forgets who this was, so the next person to sign in on this phone is not
  /// counted as the last one.
  static void reset() => sink.reset();

  static void screen(String name) => sink.screen(name);

  /// Nulls are dropped, so a call site can pass a value it might not have.
  static void event(String name, [Map<String, Object?> properties = const {}]) {
    final kept = <String, Object>{};
    properties.forEach((key, value) {
      if (value != null) kept[key] = value;
    });
    sink.event(name, kept);
  }

  /// Sizes as buckets. An exact byte count of a file, next to a timestamp, is
  /// closer to identifying a recording than to measuring anything.
  static String sizeBucket(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '<1MB';
    if (mb < 5) return '1-5MB';
    if (mb < 15) return '5-15MB';
    if (mb < 25) return '15-25MB';
    return '25MB+';
  }

  /// Counts as buckets, for the same reason.
  static String countBucket(int count) => switch (count) {
    0 => '0',
    1 => '1',
    <= 5 => '2-5',
    <= 20 => '6-20',
    <= 50 => '21-50',
    _ => '50+',
  };
}

/// No key, no analytics. Also what every test gets unless it asks otherwise.
class _Silent implements AnalyticsSink {
  const _Silent();

  @override
  void identify(String uid, Map<String, Object> onceOnly) {}

  @override
  void reset() {}

  @override
  void screen(String name) {}

  @override
  void event(String name, Map<String, Object> properties) {}
}

/// The real one. Every call is fire and forget: an event is never worth making
/// someone wait, and a failed send is never worth an error on screen.
class _PostHog implements AnalyticsSink {
  const _PostHog();

  @override
  void identify(String uid, Map<String, Object> onceOnly) =>
      _send(Posthog().identify(userId: uid, userPropertiesSetOnce: onceOnly));

  @override
  void reset() => _send(Posthog().reset());

  @override
  void screen(String name) => _send(Posthog().screen(screenName: name));

  @override
  void event(String name, Map<String, Object> properties) =>
      _send(Posthog().capture(eventName: name, properties: properties));

  static void _send(Future<void> call) => unawaited(
    call.catchError((Object e) => debugPrint('Event not sent: $e')),
  );
}
