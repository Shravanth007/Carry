import 'package:carry/analytics/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_analytics.dart';

void main() {
  test('nothing is sent unless a test asks to collect', () {
    // The build that runs tests carries no POSTHOG_KEY, so the sink is silent
    // and every call in the app is a no-op.
    expect(Analytics.isOn, isFalse);

    Analytics.event('recording_started');
    Analytics.screen('home');
    Analytics.identify('someone');
  });

  test('a collecting test sees what was sent', () {
    final events = setUpTestAnalytics();

    Analytics.event('recording_saved', {'seconds': 12});
    Analytics.screen('home');

    expect(events.only('recording_saved').properties, {'seconds': 12});
    expect(events.screens, ['home']);
  });

  test('a property with nothing in it is left out, not sent as null', () {
    final events = setUpTestAnalytics();

    Analytics.event('sign_in_succeeded', {'is_new_account': null});

    expect(events.only('sign_in_succeeded').properties, isEmpty);
  });

  test('identifying records the account and its first day once', () {
    final events = setUpTestAnalytics();

    Analytics.identify(
      'ada',
      isNewAccount: true,
      since: DateTime.utc(2026, 3, 1, 9, 30),
    );

    expect(events.identified, ['ada']);
    expect(events.only(r'$identify').properties, {
      'is_new_account': true,
      'created_at': '2026-03-01T09:30:00.000Z',
    });
  });

  test('an account with no uid is nobody, so nothing is sent', () {
    final events = setUpTestAnalytics();

    Analytics.identify('');

    expect(events.identified, isEmpty);
  });

  group('buckets', () {
    test('a size becomes a range, never an exact count of bytes', () {
      expect(Analytics.sizeBucket(500), '<1MB');
      expect(Analytics.sizeBucket(3 * 1024 * 1024), '1-5MB');
      expect(Analytics.sizeBucket(14 * 1024 * 1024), '5-15MB');
      expect(Analytics.sizeBucket(24 * 1024 * 1024), '15-25MB');
      expect(Analytics.sizeBucket(80 * 1024 * 1024), '25MB+');
    });

    test('a count becomes a range too', () {
      expect(Analytics.countBucket(0), '0');
      expect(Analytics.countBucket(1), '1');
      expect(Analytics.countBucket(4), '2-5');
      expect(Analytics.countBucket(19), '6-20');
      expect(Analytics.countBucket(40), '21-50');
      expect(Analytics.countBucket(999), '50+');
    });
  });
}
