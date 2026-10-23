import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../cancel/cancel_token.dart';
import '../errors.dart';
import '../overflow.dart';
import '../provider_config.dart';
import '../stream_state.dart';

/// HTTP layer shared by the provider adapters: error classes (§2.9),
/// error texts, `Retry-After` (§2.10.4), manual same-origin redirects and
/// cancellation that closes the request (§2.8, general rules; design.md, D5).

/// Longest error body kept in `errorMessage` (§2.9).
const maxErrorBodyLength = 2000;

const _maxRedirects = 5;

/// A failure the adapter already classified: an HTTP error status or a
/// refused redirect. `runProvider` turns it into `ErrorEvent`.
final class ProviderHttpException implements Exception {
  const ProviderHttpException(this.errorClass, this.message, {this.retryAfter});

  final LlmErrorClass errorClass;
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

/// Class of an HTTP error response by its status and body.
LlmErrorClass classifyHttpError(int status, String body) {
  final info = _ErrorInfo.parse(body);
  if (status == 429) {
    return LlmErrorClass.rateLimited;
  }
  if (const {400, 413, 422}.contains(status) && info.isOverflow(body)) {
    return LlmErrorClass.overflow;
  }
  if (_anthropicClass(info.type) case final cls?) {
    return cls;
  }
  return switch (status) {
    408 => LlmErrorClass.timeout,
    401 || 403 => LlmErrorClass.auth,
    501 || 505 => LlmErrorClass.badRequest,
    >= 500 => LlmErrorClass.server,
    >= 400 => LlmErrorClass.badRequest,
    _ => LlmErrorClass.unknown,
  };
}

/// Class of an `error` object inside a stream (OpenAI-compatible chunk or
/// Anthropic `error` event).
LlmErrorClass classifyStreamError(Map<String, Object?> error) {
  final info = _ErrorInfo.fromObject(error);
  if (info.isOverflow('')) {
    return LlmErrorClass.overflow;
  }
  final code = '${info.code ?? ''} ${info.type ?? ''}'.toLowerCase();
  if (code.contains('rate_limit') ||
      (info.message?.toLowerCase().contains('rate limit') ?? false)) {
    return LlmErrorClass.rateLimited;
  }
  return _anthropicClass(info.type) ??
      (code.contains('invalid_request')
          ? LlmErrorClass.badRequest
          : LlmErrorClass.server);
}

/// Class of an exception thrown while talking to the provider.
LlmErrorClass classifyException(Object error) {
  if (error is ProviderHttpException) {
    return error.errorClass;
  }
  if (error is TimeoutException) {
    return LlmErrorClass.timeout;
  }
  if (error is FormatException) {
    return LlmErrorClass.server;
  }
  if (error is http.ClientException) {
    return LlmErrorClass.network;
  }
  // `dart:io` types are not visible here (PKG-1): match them by name.
  final name = error.runtimeType.toString();
  if (const [
    'SocketException',
    'HandshakeException',
    'TlsException',
    'HttpException',
  ].any(name.contains)) {
    return LlmErrorClass.network;
  }
  return LlmErrorClass.unknown;
}

/// `<provider> <status>: <message>`; the body is cut to
/// [maxErrorBodyLength] characters and [secrets] are replaced with
/// `[REDACTED]` (design.md, D7).
String describeHttpError(
  String provider,
  int status,
  String body, {
  Iterable<String> secrets = const [],
}) {
  final info = _ErrorInfo.parse(body);
  var message = (info.message ?? body).trim();
  if (message.isEmpty) {
    message = 'HTTP $status';
  }
  if (message.length > maxErrorBodyLength) {
    message = '${message.substring(0, maxErrorBodyLength)}…';
  }
  if (message.contains('prompt_cache_key')) {
    message = '$message (set providers.$provider.prompt_cache_key: false)';
  }
  return redactSecrets('$provider $status: $message', secrets);
}

/// Replaces every non-empty value of [secrets] in [text].
String redactSecrets(String text, Iterable<String> secrets) {
  var result = text;
  for (final secret in secrets) {
    if (secret.isNotEmpty) {
      result = result.replaceAll(secret, '[REDACTED]');
    }
  }
  return result;
}

/// `retry-after-ms` (milliseconds) wins over `retry-after` (seconds or an
/// HTTP-date relative to [now]); negative is zero, unparseable is `null`.
/// Header names are lower case, as `package:http` gives them.
Duration? parseRetryAfter(Map<String, String> headers, DateTime now) {
  Duration clamp(Duration d) => d.isNegative ? Duration.zero : d;
  final ms = headers['retry-after-ms'];
  if (ms != null) {
    final value = num.tryParse(ms.trim());
    if (value != null) {
      return clamp(Duration(milliseconds: value.round()));
    }
  }
  final value = headers['retry-after']?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final seconds = int.tryParse(value);
  if (seconds != null) {
    return clamp(Duration(seconds: seconds));
  }
  final date = _parseHttpDate(value);
  return date == null ? null : clamp(date.difference(now));
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// IMF-fixdate of RFC 7231: `Fri, 23 Oct 2026 08:00:30 GMT`.
DateTime? _parseHttpDate(String value) {
  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  final month = match == null ? null : _months[match[2]!.toLowerCase()];
  if (match == null || month == null) {
    return null;
  }
  return DateTime.utc(
    int.parse(match[3]!),
    month,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6]!),
  );
}

/// Sends a streaming request through the host client. Redirects are
/// followed by hand: only same origin (scheme, host and port), at most five;
/// otherwise [ProviderHttpException] of class `badRequest`. The request is
/// abortable by [cancel]; an aborted send throws [CancelledException].
Future<http.StreamedResponse> sendStreaming(
  http.Client client, {
  required String method,
  required Uri url,
  required Map<String, String> headers,
  required String body,
  required CancelToken? cancel,
  required String providerName,
}) async {
  var target = url;
  for (var redirects = 0; ; redirects++) {
    cancel?.throwIfCancelled();
    final request =
        http.AbortableRequest(method, target, abortTrigger: cancel?.onCancel)
          ..followRedirects = false
          ..headers.addAll(headers)
          ..body = body;
    final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } on http.RequestAbortedException {
      throw CancelledException(cancel?.reason);
    }
    final location = response.headers['location'];
    if (!const {301, 302, 303, 307, 308}.contains(response.statusCode) ||
        location == null) {
      return response;
    }
    unawaited(response.stream.drain<void>().catchError((_) {}));
    final next = target.resolve(location);
    if (next.scheme != url.scheme ||
        next.host != url.host ||
        next.port != url.port) {
      throw ProviderHttpException(
        LlmErrorClass.badRequest,
        '$providerName ${response.statusCode}: redirect to another origin '
        'is not allowed (${next.origin})',
      );
    }
    if (redirects == _maxRedirects) {
      throw ProviderHttpException(
        LlmErrorClass.badRequest,
        '$providerName: more than $_maxRedirects redirects',
      );
    }
    target = next;
  }
}

/// The response body as UTF-8 text that ends with [CancelledException] as
/// soon as [cancel] fires; the subscription to the body is cancelled, which
/// closes the connection of the host client (LLM-7, LLM-10).
Stream<String> responseText(
  http.StreamedResponse response,
  CancelToken? cancel,
) {
  final bytes = response.stream;
  final text = bytes.cast<List<int>>().transform(
    const Utf8Decoder(allowMalformed: true),
  );
  if (cancel == null) {
    return text;
  }
  final controller = StreamController<String>();
  late final StreamSubscription<String> subscription;
  controller.onListen = () {
    if (cancel.isCancelled) {
      controller
        ..addError(CancelledException(cancel.reason))
        ..close();
      return;
    }
    subscription = text.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    cancel.onCancel.then((_) async {
      if (controller.isClosed) {
        return;
      }
      await subscription.cancel();
      controller
        ..addError(CancelledException(cancel.reason))
        ..close();
    });
  };
  controller.onCancel = () => subscription.cancel();
  return controller.stream;
}

/// Reads an error body, keeping at most [maxErrorBodyLength] × 2 characters.
Future<String> readErrorBody(http.StreamedResponse response) async {
  final buffer = StringBuffer();
  await for (final chunk in response.stream.transform(
    const Utf8Decoder(allowMalformed: true),
  )) {
    if (buffer.length < maxErrorBodyLength * 2) {
      buffer.write(chunk);
    }
  }
  return buffer.toString();
}

/// Fails [state] when [response] is not a `200` event stream: an HTTP
/// error status (§2.9) or another content type (a JSON `error` object takes
/// its class, anything else is `badRequest`). Returns whether the stream
/// can be read.
Future<bool> acceptEventStream(
  http.StreamedResponse response,
  ProviderStreamState state,
  ProviderConfig config,
) async {
  if (response.statusCode != 200) {
    final body = await readErrorBody(response);
    state.fail(
      classifyHttpError(response.statusCode, body),
      describeHttpError(
        config.name,
        response.statusCode,
        body,
        secrets: config.secrets,
      ),
      retryAfter: parseRetryAfter(response.headers, state.clock.now()),
    );
    return false;
  }
  final contentType = response.headers['content-type'] ?? '';
  if (contentType.toLowerCase().contains('text/event-stream')) {
    return true;
  }
  final body = await readErrorBody(response);
  final error = errorObjectOf(body);
  if (error != null) {
    state.fail(classifyStreamError(error), streamErrorText(config, error));
  } else {
    state.fail(
      LlmErrorClass.badRequest,
      'endpoint did not return an event stream '
      '(content-type: $contentType); check baseUrl',
    );
  }
  return false;
}

/// The `error` object of a JSON body, if any.
Map<String, Object?>? errorObjectOf(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map<String, Object?> && json['error'] is Map<String, Object?>) {
      return json['error']! as Map<String, Object?>;
    }
  } on FormatException {
    // Not JSON.
  }
  return null;
}

/// `<provider>: <message>` of an error object inside a stream, redacted.
String streamErrorText(
  ProviderConfig config,
  Map<String, Object?> error,
) => redactSecrets(
  '${config.name}: ${error['message'] ?? error['type'] ?? 'provider error'}',
  config.secrets,
);

/// `{baseUrl}/{path}` whether or not [base] ends with `/`.
Uri endpointOf(Uri base, String path) {
  final text = base.toString();
  return Uri.parse(text.endsWith('/') ? '$text$path' : '$text/$path');
}

LlmErrorClass? _anthropicClass(String? type) => switch (type) {
  'rate_limit_error' => LlmErrorClass.rateLimited,
  'overloaded_error' || 'api_error' => LlmErrorClass.server,
  'authentication_error' || 'permission_error' => LlmErrorClass.auth,
  'invalid_request_error' || 'not_found_error' => LlmErrorClass.badRequest,
  _ => null,
};

/// `error` of OpenAI-compatible bodies (`{"error": {"message", "type",
/// "code"}}`) and of Anthropic bodies (`{"type": "error", "error": {"type",
/// "message"}}`).
final class _ErrorInfo {
  const _ErrorInfo({this.message, this.type, this.code});

  factory _ErrorInfo.parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, Object?>) {
        final error = json['error'];
        if (error is Map<String, Object?>) {
          return _ErrorInfo.fromObject(error);
        }
        if (error is String) {
          return _ErrorInfo(message: error);
        }
        if (json['message'] is String) {
          return _ErrorInfo(message: json['message']! as String);
        }
      }
    } on FormatException {
      // A plain-text body.
    }
    return const _ErrorInfo();
  }

  factory _ErrorInfo.fromObject(Map<String, Object?> error) => _ErrorInfo(
    message: error['message'] is String ? error['message']! as String : null,
    type: error['type'] is String ? error['type']! as String : null,
    code: error['code'] is String ? error['code']! as String : null,
  );

  final String? message;
  final String? type;
  final String? code;

  bool isOverflow(String body) =>
      code == 'context_length_exceeded' || hasOverflowPhrase(message ?? body);
}
