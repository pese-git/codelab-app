import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/providers/openai_compatible.dart';
import 'package:test/test.dart';

import '../support/provider_harness.dart';

/// Маркер ключа: по нему ищем утечку в ошибках и журнале.
const _key = 'sk-test-leak-0123456789';

ProviderConfig _config(String baseUrl) => ProviderConfig(
  name: 'litellm',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse(baseUrl),
  apiKey: _key,
);

ModelRef _model(String baseUrl) => ModelRef(
  provider: 'litellm',
  id: 'any-litellm-model',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse(baseUrl),
  contextWindow: 128000,
  maxOutputTokens: 16384,
);

final _context = LlmContext(
  systemPrompt: 'You are CodeLab.',
  messages: [
    UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
  ],
);

Future<(ProviderHarness, List<AssistantMessageEvent>)> _run(
  String baseUrl, {
  String? body,
  int status = 200,
}) async {
  final h = ProviderHarness(
    body: body ?? readSseFixture('openai/text.sse'),
    status: status,
    chunking: Chunking.byChar,
  );
  final events = await h.run(
    openAiCompatibleStreamFunction(_config(baseUrl), h.services),
    _model(baseUrl),
    _context,
  );
  return (h, events);
}

/// Приёмка R-14 (agent-parity-goals; agent-core-architecture §2.7): любой
/// провайдер LiteLLM доступен через LiteLLM Proxy, указанный как
/// OpenAI-совместимый `baseUrl`. Поведение адаптера уже верное, поэтому тест
/// приёмочный; id первым литералом — правило D3 change
/// `switch-default-agent-to-dart`.
void main() {
  group('core/litellm-proxy-base-url', () {
    for (final (base, expected) in const [
      (
        'http://litellm.local:4000',
        'http://litellm.local:4000/chat/completions',
      ),
      (
        'http://litellm.local:4000/',
        'http://litellm.local:4000/chat/completions',
      ),
      (
        'https://gw.example/litellm/v1',
        'https://gw.example/litellm/v1/chat/completions',
      ),
      (
        'https://gw.example/litellm/v1/',
        'https://gw.example/litellm/v1/chat/completions',
      ),
    ]) {
      test(
        'baseUrl $base -> $expected, key in header, stream is parsed',
        () async {
          final (h, events) = await _run(base);

          expect(h.requests, hasLength(1));
          final request = h.requests.single.request;
          expect(request.method, 'POST');
          expect(request.url.toString(), expected);
          expect(request.url.path, isNot(contains('//')));
          expect(
            request.headers,
            containsPair('Authorization', 'Bearer $_key'),
          );
          expect(request.url.toString(), isNot(contains(_key)));

          expect(events.last, isA<DoneEvent>());
          final message = (events.last as DoneEvent).message;
          expect(message.content, [const TextContent('Hello, world')]);
        },
      );
    }

    test('an auth error of the proxy does not leak the key', () async {
      final (h, events) = await _run(
        'http://litellm.local:4000',
        body: '{"error":{"message":"invalid key","type":"auth_error"}}',
        status: 401,
      );

      expect(events.last, isA<ErrorEvent>());
      final error = (events.last as ErrorEvent).error;
      expect(error.errorMessage, isNot(contains(_key)));
      expect(error.toString(), isNot(contains(_key)));
      expect(h.logger.records.join('\n'), isNot(contains(_key)));
    });
  });
}
