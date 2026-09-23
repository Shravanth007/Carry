import 'dart:async';

import 'package:carry/api/api.dart';
import 'package:carry/auth/auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Hands out a different token depending on whether a refresh was asked for,
/// so a test can see which one a request carried.
// ignore: must_be_immutable  MockUser's own fields aren't final.
class _TokenUser extends MockUser {
  _TokenUser() : super(uid: 'firebase-uid');

  final refreshes = <bool>[];

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async {
    refreshes.add(forceRefresh);
    return forceRefresh ? 'fresh-token' : 'stale-token';
  }
}

void main() {
  late _TokenUser user;
  final requests = <http.BaseRequest>[];

  setUp(() {
    requests.clear();
    user = _TokenUser();
    Auth.firebaseForTesting = MockFirebaseAuth(signedIn: true, mockUser: user);
  });

  tearDown(() {
    Auth.firebaseForTesting = null;
    Api.client = http.Client();
    Api.timeout = const Duration(seconds: 20);
  });

  /// Answers every request with [answers] in turn, recording what arrived.
  void serverAnswers(List<http.Response> answers) {
    var next = 0;
    Api.client = MockClient((request) async {
      requests.add(request);
      return answers[next++ < answers.length ? next - 1 : answers.length - 1];
    });
  }

  http.Response ok() => http.Response(
    '{"uid":"firebase-uid","email":"ada@example.com",'
    '"since":"2026-01-01T00:00:00Z"}',
    200,
  );

  String tokenOf(http.BaseRequest request) =>
      request.headers['Authorization'] ?? '';

  test('every call carries the signed-in account token', () async {
    serverAnswers([ok()]);

    final me = await Api.me();

    expect(me.uid, 'firebase-uid');
    expect(me.email, 'ada@example.com');
    expect(tokenOf(requests.single), 'Bearer stale-token');
    expect(requests.single.url.path, '/me');
  });

  test('an expired token is refreshed and the call retried once', () async {
    serverAnswers([http.Response('{"detail":"Expired."}', 401), ok()]);

    final me = await Api.me();

    expect(me.uid, 'firebase-uid');
    expect(requests, hasLength(2));
    expect(tokenOf(requests.first), 'Bearer stale-token');
    expect(tokenOf(requests.last), 'Bearer fresh-token');
    expect(user.refreshes, [false, true]);
  });

  test('a second 401 gives up rather than looping', () async {
    serverAnswers([http.Response('{"detail":"Sign in again."}', 401)]);

    await expectLater(
      Api.me(),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', 'Sign in again.'),
      ),
    );
    expect(requests, hasLength(2));
  });

  test('signed out, nothing is sent', () async {
    Auth.firebaseForTesting = MockFirebaseAuth();
    serverAnswers([ok()]);

    await expectLater(Api.me(), throwsA(isA<ApiFailure>()));
    expect(requests, isEmpty);
  });

  test("the server's own wording reaches the caller", () async {
    serverAnswers([
      http.Response('{"detail":"Too many requests. Slow down."}', 429),
    ]);

    await expectLater(
      Api.me(),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'message',
          'Too many requests. Slow down.',
        ),
      ),
    );
  });

  test('a server with nothing to say still gets a sentence', () async {
    serverAnswers([http.Response('', 500)]);

    await expectLater(
      Api.me(),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'message',
          contains('server is having trouble'),
        ),
      ),
    );
  });

  test('being offline says so', () async {
    Api.client = MockClient(
      (_) async => throw http.ClientException('Failed host lookup'),
    );

    await expectLater(
      Api.me(),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'message',
          contains('No internet'),
        ),
      ),
    );
  });

  test('a body that is not JSON is reported, not thrown raw', () async {
    serverAnswers([http.Response('not json', 200)]);

    await expectLater(Api.me(), throwsA(isA<ApiFailure>()));
  });

  test('JSON of the wrong shape is reported, not thrown raw', () async {
    // Valid JSON, but a field the app needs is gone: a renamed field on the
    // server must not throw a cast error at the screen that called.
    serverAnswers([http.Response('{"email":"ada@example.com"}', 200)]);

    await expectLater(
      Api.me(),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'message',
          contains("couldn't read"),
        ),
      ),
    );
  });

  test(
    'a server that stalls after the headers does not hang the call',
    () async {
      Api.timeout = const Duration(milliseconds: 50);
      // Headers arrive, then nothing: the body never comes and never closes.
      final stalled = StreamController<List<int>>();
      addTearDown(stalled.close);
      Api.client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(stalled.stream, 200),
      );

      await expectLater(
        Api.me(),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('took too long'),
          ),
        ),
      );
      // The reader let go of the stream rather than holding the socket open.
      expect(stalled.hasListener, isFalse);
    },
  );

  test('health needs no account', () async {
    Auth.firebaseForTesting = MockFirebaseAuth();
    serverAnswers([http.Response('{"status":"ok"}', 200)]);

    expect(await Api.health(), isTrue);
    expect(tokenOf(requests.single), isEmpty);
  });

  test('health is false when the server is down', () async {
    Api.client = MockClient((_) async => throw http.ClientException('down'));

    expect(await Api.health(), isFalse);
  });
}
