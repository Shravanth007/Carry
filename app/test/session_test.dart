import 'package:carry/auth/auth.dart';
import 'package:carry/notes/notes.dart';
import 'package:carry/session.dart';
import 'package:carry/settings/avatar_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_auth.dart';
import 'helpers/test_device.dart';

void main() {
  late TestAuth testAuth;

  setUp(() async {
    testAuth = await setUpTestAuth(signedIn: true);
    setUpTestPrefs();
    setUpTestAvatarDownloads();
    Notes.clear();
  });

  test('signing out leaves nothing of the person behind', () async {
    await AvatarCache.load('https://example.com/ada.jpg');
    Notes.add(
      Note(
        id: '1',
        title: 'Private thought',
        path: '/phone/1.m4a',
        addedAt: DateTime.now(),
      ),
    );

    await signOutAndForget();

    expect(Auth.currentUser, isNull, reason: 'signed out of Firebase');
    expect(testAuth.google.signOutCalls, 1, reason: 'and out of Google');
    expect(Notes.all.value, isEmpty, reason: 'notes are not the next user\'s');
    expect(
      await AvatarCache.load('https://example.com/ada.jpg'),
      isNotNull,
      reason: 'a fresh download, not the old saved copy',
    );
  });

  test('the saved picture is really gone, not just replaced', () async {
    await AvatarCache.load('https://example.com/ada.jpg');

    await signOutAndForget();
    goOffline();

    expect(await AvatarCache.load('https://example.com/ada.jpg'), isNull);
  });

  test('a failed sign-out keeps the data', () async {
    Notes.add(
      Note(
        id: '1',
        title: 'Still mine',
        path: '/phone/1.m4a',
        addedAt: DateTime.now(),
      ),
    );
    failNextSignOut(testAuth);

    await expectLater(signOutAndForget(), throwsA(isA<Exception>()));

    expect(Notes.all.value, hasLength(1), reason: 'still signed in');
  });
}
