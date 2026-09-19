import 'package:carry/notes/notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(Notes.clear);

  Note note(String title) => Note(
    id: title,
    title: title,
    path: '/phone/$title.m4a',
    addedAt: DateTime.now(),
  );

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
