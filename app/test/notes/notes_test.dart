import 'package:carry/notes/notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(Notes.clear);

  /// A note the way the app makes one: through the single gate.
  Note keep(String title) => Notes.addAudio(
    source: AudioSource.imported,
    ownerUid: 'firebase-uid',
    path: '/phone/$title.m4a',
    bytes: 2048,
    title: title,
  ).note!;

  test('starts empty', () {
    expect(Notes.all.value, isEmpty);
  });

  test('keeps the newest note first', () {
    keep('First');
    keep('Second');

    expect(Notes.all.value.map((n) => n.title), ['Second', 'First']);
  });

  test('tells listeners when a note arrives', () {
    var changes = 0;
    void count() => changes++;
    Notes.all.addListener(count);
    addTearDown(() => Notes.all.removeListener(count));

    keep('First');

    expect(changes, 1);
  });

  test('clearing drops everything, for the next person to sign in', () {
    keep('First');

    Notes.clear();

    expect(Notes.all.value, isEmpty);
  });
}
