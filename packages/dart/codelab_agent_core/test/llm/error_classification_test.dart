import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/providers/http_support.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String _openAiError(String message, {String? code, String? type}) =>
    jsonEncode({
      'error': {'message': message, 'code': ?code, 'type': ?type},
    });

String _anthropicError(String type, String message) => jsonEncode({
  'type': 'error',
  'error': {'type': type, 'message': message},
});

void main() {
  group('classifyHttpError — table of §2.9', () {
    final cases = <(int, String, LlmErrorClass)>[
      (408, '', LlmErrorClass.timeout),
      (429, _openAiError('Rate limit reached'), LlmErrorClass.rateLimited),
      (500, '', LlmErrorClass.server),
      (502, '', LlmErrorClass.server),
      (503, '', LlmErrorClass.server),
      (504, '', LlmErrorClass.server),
      (529, '', LlmErrorClass.server),
      (599, '', LlmErrorClass.server),
      (501, '', LlmErrorClass.badRequest),
      (505, '', LlmErrorClass.badRequest),
      (400, _openAiError('Invalid value'), LlmErrorClass.badRequest),
      (404, _openAiError('model not found'), LlmErrorClass.badRequest),
      (405, '', LlmErrorClass.badRequest),
      (413, '', LlmErrorClass.badRequest),
      (415, '', LlmErrorClass.badRequest),
      (422, '', LlmErrorClass.badRequest),
      (401, _openAiError('Incorrect API key'), LlmErrorClass.auth),
      (403, '', LlmErrorClass.auth),
      (
        400,
        _openAiError('too long', code: 'context_length_exceeded'),
        LlmErrorClass.overflow,
      ),
      (
        400,
        _openAiError("This model's maximum context length is 8192 tokens"),
        LlmErrorClass.overflow,
      ),
      (413, 'prompt is too long', LlmErrorClass.overflow),
      (
        400,
        _openAiError('context length exceeded: tokens per minute limit'),
        LlmErrorClass.badRequest,
      ),
      (
        429,
        _anthropicError('rate_limit_error', 'slow down'),
        LlmErrorClass.rateLimited,
      ),
      (
        529,
        _anthropicError('overloaded_error', 'Overloaded'),
        LlmErrorClass.server,
      ),
      (500, _anthropicError('api_error', 'boom'), LlmErrorClass.server),
      (
        400,
        _anthropicError('invalid_request_error', 'bad field'),
        LlmErrorClass.badRequest,
      ),
      (
        400,
        _anthropicError('invalid_request_error', 'prompt is too long: 210000'),
        LlmErrorClass.overflow,
      ),
      (
        404,
        _anthropicError('not_found_error', 'no model'),
        LlmErrorClass.badRequest,
      ),
      (
        401,
        _anthropicError('authentication_error', 'invalid x-api-key'),
        LlmErrorClass.auth,
      ),
      (403, _anthropicError('permission_error', 'denied'), LlmErrorClass.auth),
    ];
    for (final (status, body, expected) in cases) {
      test('$status $body → ${expected.name}', () {
        expect(classifyHttpError(status, body), expected);
      });
    }
  });

  group('classifyStreamError — error objects inside a stream', () {
    test('OpenAI-compatible error object', () {
      expect(
        classifyStreamError({
          'message': 'Rate limit',
          'code': 'rate_limit_exceeded',
        }),
        LlmErrorClass.rateLimited,
      );
      expect(
        classifyStreamError({
          'message': 'too long',
          'code': 'context_length_exceeded',
        }),
        LlmErrorClass.overflow,
      );
      expect(
        classifyStreamError({'message': 'oops', 'type': 'server_error'}),
        LlmErrorClass.server,
      );
    });

    test('Anthropic error types', () {
      expect(
        classifyStreamError({'type': 'overloaded_error'}),
        LlmErrorClass.server,
      );
      expect(
        classifyStreamError({'type': 'rate_limit_error'}),
        LlmErrorClass.rateLimited,
      );
      expect(
        classifyStreamError({'type': 'authentication_error'}),
        LlmErrorClass.auth,
      );
    });
  });

  group('classifyException', () {
    test('client and socket failures are network', () {
      expect(
        classifyException(http.ClientException('Connection reset by peer')),
        LlmErrorClass.network,
      );
    });

    test('unparseable chunk JSON is server', () {
      expect(
        classifyException(const FormatException('Unexpected character')),
        LlmErrorClass.server,
      );
    });

    test('a timeout is timeout', () {
      expect(classifyException(TimeoutException('x')), LlmErrorClass.timeout);
    });
  });

  group('describeHttpError', () {
    test('format <provider> <status>: <message>', () {
      expect(
        describeHttpError(
          'openai',
          401,
          _openAiError('Incorrect API key provided'),
        ),
        'openai 401: Incorrect API key provided',
      );
      expect(
        describeHttpError('local', 503, 'Service Unavailable'),
        'local 503: Service Unavailable',
      );
    });

    test('the key and header values never reach the message', () {
      final message = describeHttpError(
        'openai',
        401,
        _openAiError('Incorrect API key provided: sk-secret-123.'),
        secrets: ['sk-secret-123', 'org-header-value'],
      );

      expect(message, isNot(contains('sk-secret-123')));
      expect(message, contains('[REDACTED]'));
    });

    test('the body is cut to 2000 characters', () {
      final message = describeHttpError('local', 500, 'x' * 5000);

      expect(message.length, lessThanOrEqualTo('local 500: '.length + 2001));
    });

    test('a hint about prompt_cache_key is added', () {
      expect(
        describeHttpError(
          'local',
          400,
          _openAiError('Unrecognized request argument: prompt_cache_key'),
        ),
        contains('set providers.local.prompt_cache_key: false'),
      );
    });
  });

  group('parseRetryAfter (§2.10.4)', () {
    final now = DateTime.utc(2026, 10, 23, 8);

    test('retry-after-ms wins', () {
      expect(
        parseRetryAfter({'retry-after-ms': '1500', 'retry-after': '9'}, now),
        const Duration(milliseconds: 1500),
      );
    });

    test('seconds and HTTP-date', () {
      expect(
        parseRetryAfter({'retry-after': '7'}, now),
        const Duration(seconds: 7),
      );
      expect(
        parseRetryAfter({'retry-after': 'Fri, 23 Oct 2026 08:00:30 GMT'}, now),
        const Duration(seconds: 30),
      );
    });

    test('negative is zero, garbage and absence are null', () {
      expect(parseRetryAfter({'retry-after': '-3'}, now), Duration.zero);
      expect(
        parseRetryAfter({'retry-after': 'Fri, 23 Oct 2026 07:00:00 GMT'}, now),
        Duration.zero,
      );
      expect(parseRetryAfter({'retry-after': 'soon'}, now), isNull);
      expect(parseRetryAfter(const {}, now), isNull);
    });
  });

  group('sendStreaming', () {
    test('a same-origin redirect is followed', () async {
      final seen = <Uri>[];
      final client = MockClient.streaming((request, _) async {
        seen.add(request.url);
        if (request.url.path == '/v1/old') {
          return http.StreamedResponse(
            const Stream.empty(),
            307,
            headers: {'location': '/v1/new'},
          );
        }
        return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
      });

      final response = await sendStreaming(
        client,
        method: 'POST',
        url: Uri.parse('https://api.example.com/v1/old'),
        headers: const {},
        body: '{}',
        cancel: null,
        providerName: 'example',
      );

      expect(response.statusCode, 200);
      expect(seen.map((u) => u.path), ['/v1/old', '/v1/new']);
    });

    test('a redirect to another origin is a badRequest', () async {
      final seen = <Uri>[];
      final client = MockClient.streaming((request, _) async {
        seen.add(request.url);
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'https://evil.example.org/v1'},
        );
      });

      await expectLater(
        sendStreaming(
          client,
          method: 'POST',
          url: Uri.parse('https://api.example.com/v1'),
          headers: const {'authorization': 'Bearer k'},
          body: '{}',
          cancel: null,
          providerName: 'example',
        ),
        throwsA(
          isA<ProviderHttpException>()
              .having((e) => e.errorClass, 'class', LlmErrorClass.badRequest)
              .having(
                (e) => e.message,
                'message',
                contains('redirect to another origin is not allowed'),
              ),
        ),
      );
      expect(seen, hasLength(1));
    });

    test('more than five redirects is a badRequest', () async {
      var n = 0;
      final client = MockClient.streaming((request, _) async {
        n++;
        return http.StreamedResponse(
          const Stream.empty(),
          307,
          headers: {'location': '/v1/r$n'},
        );
      });

      await expectLater(
        sendStreaming(
          client,
          method: 'POST',
          url: Uri.parse('https://api.example.com/v1'),
          headers: const {},
          body: '{}',
          cancel: null,
          providerName: 'example',
        ),
        throwsA(isA<ProviderHttpException>()),
      );
      expect(n, 6);
    });

    test('the request carries the cancel token as abortTrigger', () async {
      final source = CancelTokenSource();
      http.BaseRequest? sent;
      final client = MockClient.streaming((request, _) async {
        sent = request;
        return http.StreamedResponse(const Stream.empty(), 200);
      });

      await sendStreaming(
        client,
        method: 'POST',
        url: Uri.parse('https://api.example.com/v1'),
        headers: const {},
        body: '{}',
        cancel: source.token,
        providerName: 'example',
      );

      expect(sent, isA<http.Abortable>());
      var aborted = false;
      unawaited(
        (sent! as http.Abortable).abortTrigger!.then((_) => aborted = true),
      );
      source.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(aborted, isTrue);
    });
  });
}
