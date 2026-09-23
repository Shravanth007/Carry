import 'package:carry/analytics/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

/// One thing that happened, as analytics saw it.
typedef Recorded = ({String name, Map<String, Object> properties});

/// Collects events instead of sending them. Nothing leaves the machine.
class TestAnalytics implements AnalyticsSink {
  final events = <Recorded>[];
  final screens = <String>[];
  final identified = <String>[];
  int resets = 0;

  @override
  void identify(String uid, Map<String, Object> onceOnly) {
    identified.add(uid);
    events.add((name: r'$identify', properties: onceOnly));
  }

  @override
  void reset() => resets++;

  @override
  void screen(String name) => screens.add(name);

  @override
  void event(String name, Map<String, Object> properties) =>
      events.add((name: name, properties: properties));

  /// Every event named [name], in the order they happened.
  Iterable<Recorded> named(String name) => events.where((e) => e.name == name);

  /// The one event named [name]. Fails when there isn't exactly one.
  Recorded only(String name) {
    final found = named(name).toList();
    expect(found, hasLength(1), reason: 'events so far: ${names()}');
    return found.single;
  }

  bool has(String name) => named(name).isNotEmpty;

  List<String> names() => events.map((e) => e.name).toList();
}

/// Points [Analytics] at a collector for this test, and puts the silent one
/// back afterwards so a test that doesn't ask for analytics has none.
TestAnalytics setUpTestAnalytics() {
  final collected = TestAnalytics();
  Analytics.sink = collected;
  addTearDown(() => Analytics.sink = Analytics.silentForTesting);
  return collected;
}
