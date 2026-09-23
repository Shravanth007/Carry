import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../analytics/analytics.dart';
import '../auth/auth.dart';

/// Something the server refused or couldn't do. [message] is written for the
/// person using Carry, so a screen can show it as it stands.
class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => 'ApiFailure($status): $message';
}

/// Every call to the Carry server goes through here.
///
/// One place attaches the sign-in token, sets the timeout, retries once when
/// a token has just expired, and turns a status code into a sentence. Screens
/// and services call the methods below; nothing else in the app touches HTTP,
/// so there is no second place to forget the token or the error handling.
abstract final class Api {
  /// Where the server is. The emulator reaches the host machine on 10.0.2.2,
  /// so that's the default for development:
  ///   flutter run --dart-define=CARRY_API=https://api.example.com
  static const baseUrl = String.fromEnvironment(
    'CARRY_API',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// How long a whole call may take: connecting, the headers and the body.
  /// Tests shorten it so they don't have to wait one out.
  @visibleForTesting
  static Duration timeout = const Duration(seconds: 20);

  /// Tests put their own client here.
  @visibleForTesting
  static http.Client client = http.Client();

  static final _random = Random();

  /// Short, unique enough, and made only of characters the server accepts.
  static String _newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '-${_random.nextInt(0xffffff).toRadixString(16)}';

  /// Is the server up? Needs no account.
  static Future<bool> health() async {
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }

  /// Who the server thinks you are. Proves sign-in works end to end.
  static Future<ServerUser> me() async =>
      _parse(await _send('GET', '/me'), ServerUser.fromJson, '/me');

  /// Builds a value out of a body, turning a shape we didn't expect into an
  /// [ApiFailure] like any other. Without this a field the server renamed
  /// would throw a raw cast error at whatever screen made the call.
  static T _parse<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) build,
    String path,
  ) {
    try {
      return build(body);
    } catch (e) {
      debugPrint("Couldn't read the server's answer: $e");
      Analytics.event('api_failed', {'endpoint': path, 'kind': 'wrong_shape'});
      throw const ApiFailure("Carry couldn't read the server's answer.");
    }
  }

  /// Sends a request with the signed-in account's token.
  ///
  /// A `401` gets one retry with a freshly minted token, because a token
  /// expires an hour after it was issued and the person shouldn't notice.
  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    var response = await _once(method, path, body: body, freshToken: false);
    if (response.statusCode == 401) {
      Analytics.event('api_token_refreshed', {'endpoint': path});
      response = await _once(method, path, body: body, freshToken: true);
    }
    return _body(response, path);
  }

  static Future<http.Response> _once(
    String method,
    String path, {
    required bool freshToken,
    Map<String, dynamic>? body,
  }) async {
    final token = await Auth.idToken(forceRefresh: freshToken);
    if (token == null) {
      Analytics.event('api_failed', {'endpoint': path, 'kind': 'signed_out'});
      throw const ApiFailure('Sign in to use Carry.', status: 401);
    }
    final requestId = _newRequestId();
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Authorization'] = 'Bearer $token'
      // The server logs this and sends it back, so one event points at one
      // line in the server's log.
      ..headers['X-Request-ID'] = requestId;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      // One deadline for the whole call. The headers arriving doesn't mean the
      // body will: a server can send them and then stall, so the body gets
      // whatever time is left rather than no limit at all.
      final deadline = DateTime.now().add(timeout);
      final streamed = await client.send(request).timeout(timeout);
      return await _read(streamed, deadline.difference(DateTime.now()));
    } on ApiFailure {
      rethrow;
    } catch (e) {
      debugPrint('$method $path failed: $e');
      // The kind, never the message: an exception's text can carry a path or
      // a URL. The request id is what ties this to the server's own log.
      final kind = switch (e) {
        SocketException() || http.ClientException() => 'offline',
        TimeoutException() => 'timeout',
        _ => 'unreachable',
      };
      Analytics.event('api_failed', {
        'endpoint': path,
        'kind': kind,
        'request_id': requestId,
      });
      throw ApiFailure(switch (kind) {
        'offline' => 'No internet connection. Connect and try again.',
        'timeout' => 'That took too long. Try again.',
        _ => "Carry couldn't reach its server. Try again.",
      });
    }
  }

  /// Collects the body within [left].
  ///
  /// `http.Response.fromStream` has no deadline of its own, so this reads the
  /// stream directly and cancels it when the time runs out, which closes the
  /// socket instead of leaving it reading forever.
  static Future<http.Response> _read(
    http.StreamedResponse streamed,
    Duration left,
  ) async {
    final bytes = <int>[];
    final finished = Completer<void>();
    final body = streamed.stream.listen(
      bytes.addAll,
      onDone: finished.complete,
      onError: finished.completeError,
      cancelOnError: true,
    );
    try {
      await finished.future.timeout(left.isNegative ? Duration.zero : left);
    } catch (_) {
      await body.cancel();
      rethrow;
    }
    return http.Response.bytes(
      bytes,
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  /// Turns a response into a body, or a sentence worth showing.
  static Map<String, dynamic> _body(http.Response response, String path) {
    final status = response.statusCode;
    final requestId = response.headers['x-request-id'];
    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) return const {};
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Server sent something unreadable: $e');
        Analytics.event('api_failed', {
          'endpoint': path,
          'kind': 'bad_body',
          'status': status,
          'request_id': requestId,
        });
        throw const ApiFailure("Carry couldn't read the server's answer.");
      }
    }

    Analytics.event('api_failed', {
      'endpoint': path,
      'kind': switch (status) {
        401 => 'unauthorized',
        403 => 'forbidden',
        404 => 'missing',
        413 => 'too_large',
        429 => 'rate_limited',
        >= 500 => 'server_error',
        _ => 'refused',
      },
      'status': status,
      'request_id': requestId,
    });

    // The server writes these for people; use its words when it sent any.
    final detail = _detail(response);
    throw ApiFailure(switch (status) {
      401 => detail ?? 'Sign in again to carry on.',
      403 => detail ?? "This account can't use Carry.",
      404 => detail ?? "That isn't there any more.",
      413 => detail ?? 'That was too large to send.',
      429 => detail ?? 'Too many requests. Try again in a moment.',
      >= 500 => detail ?? 'Carry\'s server is having trouble. Try again.',
      _ => detail ?? 'Something went wrong. Try again.',
    }, status: status);
  }

  static String? _detail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final detail = body is Map ? body['detail'] : null;
      return detail is String && detail.isNotEmpty ? detail : null;
    } catch (_) {
      return null;
    }
  }
}

/// The account as the server knows it.
@immutable
class ServerUser {
  const ServerUser({required this.uid, this.email, required this.since});

  factory ServerUser.fromJson(Map<String, dynamic> json) => ServerUser(
    uid: json['uid'] as String,
    email: json['email'] as String?,
    since: DateTime.parse(json['since'] as String),
  );

  final String uid;
  final String? email;

  /// When this account first used Carry.
  final DateTime since;
}
