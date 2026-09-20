import 'package:carry/notes/notes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_auth.dart';

void main() {
  setUp(Notes.clear);

  Note note(String title) => Note(
    id: title,
    ownerUid: 'firebase-uid',
    title: title,
    path: '/phone/$title.m4a',
    addedAt: DateTime.now(),
  );

  test('a note made now belongs to whoever is signed in', () async {
    await setUpTestAuth(signedIn: true);

    expect(Notes.owner, 'firebase-uid');
  });

  test('nothing is stamped with an owner while signed out', () async {
    await setUpTestAuth();

    expect(Notes.owner, isEmpty);
  });

  test('starts empty', () {
    expect(Notes.all.value, isEmpty);
  });

  test('keeps the newest note first', () {
    Notes.add(note('First'));
    Notes.add(note('Second'));

    expect(Notes.all.value.map((n) => n.title), ['Second', 'First']);
  });

  test('tells listeners when a note arrives', () {
    var changes = 0;
    void count() => changes++;
    Notes.all.addListener(count);
    addTearDown(() => Notes.all.removeListener(count));

    Notes.add(note('First'));

    expect(changes, 1);
  });
}
