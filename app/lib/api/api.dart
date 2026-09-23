import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  static const _timeout = Duration(seconds: 20);

  /// Tests put their own client here.
  @visibleForTesting
  static http.Client client = http.Client();

  /// Is the server up? Needs no account.
  static Future<bool> health() async {
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }

  /// Who the server thinks you are. Proves sign-in works end to end.
  static Future<ServerUser> me() async {
    final body = await _send('GET', '/me');
    return ServerUser.fromJson(body);
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
      response = await _once(method, path, body: body, freshToken: true);
    }
    return _read(response);
  }

  static Future<http.Response> _once(
    String method,
    String path, {
    required bool freshToken,
    Map<String, dynamic>? body,
  }) async {
    final token = await Auth.idToken(forceRefresh: freshToken);
    if (token == null) {
      throw const ApiFailure('Sign in to use Carry.', status: 401);
    }
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } on ApiFailure {
      rethrow;
    } catch (e) {
      debugPrint('$method $path failed: $e');
      throw ApiFailure(
        e is SocketException || e is http.ClientException
            ? 'No internet connection. Connect and try again.'
            : "Carry couldn't reach its server. Try again.",
      );
    }
  }

  /// Turns a response into a body, or a sentence worth showing.
  static Map<String, dynamic> _read(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) return const {};
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Server sent something unreadable: $e');
        throw const ApiFailure("Carry couldn't read the server's answer.");
      }
    }

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
