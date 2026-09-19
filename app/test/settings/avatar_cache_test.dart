import 'dart:typed_data';

import 'package:carry/settings/avatar_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/test_device.dart';

const url = 'https://lh3.googleusercontent.com/ada';
const newUrl = 'https://lh3.googleusercontent.com/ada-new';

void main() {
  setUp(setUpTestPrefs);

  /// A phone with no connection.
  void goOffline() {
    AvatarCache.client = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    addTearDown(() => AvatarCache.client = http.Client());
  }

  test('downloads the picture the first time', () async {
    final requests = setUpTestAvatarDownloads();

    expect(await AvatarCache.load(url), testPngBytes);
    expect(requests, [Uri.parse(url)]);
  });

  test('uses the saved copy next time, without the network', () async {
    final requests = setUpTestAvatarDownloads();
    await AvatarCache.load(url);

    expect(await AvatarCache.load(url), testPngBytes);
    expect(requests.length, 1, reason: 'only the first load hits the network');
  });

  test('works offline once the picture is saved', () async {
    setUpTestAvatarDownloads();
    await AvatarCache.load(url);
    goOffline();

    expect(await AvatarCache.load(url), testPngBytes);
  });

  test('has nothing to show when offline and never loaded', () async {
    goOffline();

    expect(await AvatarCache.load(url), isNull);
  });

  test('fetches again when the picture changes', () async {
    setUpTestAvatarDownloads();
    await AvatarCache.load(url);
    final newBytes = Uint8List.fromList([...testPngBytes, 0]);
    final requests = setUpTestAvatarDownloads(bytes: newBytes);

    expect(await AvatarCache.load(newUrl), newBytes);
    expect(requests, [Uri.parse(newUrl)]);
  });

  test('keeps the old picture when the new one cannot be fetched', () async {
    setUpTestAvatarDownloads();
    await AvatarCache.load(url);
    goOffline();

    expect(await AvatarCache.load(newUrl), testPngBytes);
  });

  group('refuses', () {
    test('an error response', () async {
      setUpTestAvatarDownloads(status: 404);

      expect(await AvatarCache.load(url), isNull);
    });

    test('an empty response', () async {
      setUpTestAvatarDownloads(bytes: Uint8List(0));

      expect(await AvatarCache.load(url), isNull);
    });

    test('a file too big to be a thumbnail', () async {
      setUpTestAvatarDownloads(bytes: Uint8List(AvatarCache.maxBytes + 1));

      expect(await AvatarCache.load(url), isNull);
    });
  });

  test('clear forgets the saved picture', () async {
    setUpTestAvatarDownloads();
    await AvatarCache.load(url);

    await AvatarCache.clear();
    goOffline();

    expect(await AvatarCache.load(url), isNull);
  });
}
