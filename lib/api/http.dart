import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class NotFoundException extends ApiException {
  NotFoundException(String path) : super('Not found: $path', 404);
}

class HttpResult {
  HttpResult(this.status, this.body);

  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;

  dynamic get json {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

/// Thin wrapper over dart:io HttpClient with a cookie jar and optional
/// acceptance of self-signed certificates.
class PanelHttp {
  PanelHttp({bool allowInsecure = false, this.timeout = const Duration(seconds: 20)})
      : _client = HttpClient() {
    _client.connectionTimeout = timeout;
    _client.userAgent = 'XUI-Manager';
    if (allowInsecure) {
      _client.badCertificateCallback = (cert, host, port) => true;
    }
  }

  final HttpClient _client;
  final Duration timeout;
  final Map<String, String> cookies = {};

  Future<HttpResult> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? json,
    Map<String, String>? form,
  }) async {
    try {
      return await _send(method, uri, headers, json, form).timeout(timeout);
    } on TimeoutException {
      throw ApiException('Connection timed out (${uri.host}).');
    } on HandshakeException catch (e) {
      throw ApiException(
          'TLS error: ${e.message}. For self-signed certificates enable "Allow insecure TLS".');
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.osError?.message ?? e.message}');
    } on HttpException catch (e) {
      throw ApiException('HTTP error: ${e.message}');
    }
  }

  Future<HttpResult> _send(String method, Uri uri, Map<String, String>? headers,
      Object? json, Map<String, String>? form) async {
    final req = await _client.openUrl(method, uri);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    headers?.forEach((k, v) => req.headers.set(k, v));
    if (cookies.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader,
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
    }
    List<int>? body;
    if (json != null) {
      req.headers.contentType = ContentType.json;
      body = utf8.encode(jsonEncode(json));
    } else if (form != null) {
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      body = utf8.encode(form.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
    }
    if (body != null) {
      req.contentLength = body.length;
      req.add(body);
    } else if (method != 'GET' && method != 'DELETE') {
      req.contentLength = 0;
    }
    final res = await req.close();
    try {
      for (final c in res.cookies) {
        cookies[c.name] = c.value;
      }
    } catch (_) {
      // Ignore malformed Set-Cookie headers.
    }
    final text =
        await res.transform(const Utf8Decoder(allowMalformed: true)).join();
    return HttpResult(res.statusCode, text);
  }

  void close() => _client.close(force: true);
}
