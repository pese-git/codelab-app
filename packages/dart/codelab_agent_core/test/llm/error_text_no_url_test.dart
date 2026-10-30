import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/call_sequence.dart';

/// Текст ошибки хода и лог не содержат URL запроса: `${ENV}` в `base_url`
/// бывает токеном (change `add-agent-configuration`, D4; согласовано с
/// текстами транспорта MCP `connection failed: <тип>`).
void main() {
  const secret = 'sk-test-secret';
  final context = LlmContext(
    systemPrompt: 's',
    messages: [
      UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
    ],
  );

  Future<(AssistantMessage, RecordingLogger)> failWith(Object error) async {
    final clock = FakeClock();
    final logger = RecordingLogger();
    final config = ProviderConfig(
      name: 'p',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('https://x.test/v1?key=$secret'),
      retry: const RetryPolicy(maxAttempts: 1),
    );
    final client = MockClient.streaming((request, _) async => throw error);
    final stream = createStreamFunction(
      config,
      CoreLlmServices(
        httpClient: client,
        clock: clock,
        random: Random(1),
        logger: logger,
      ),
    );
    final model = ModelRef(
      provider: 'p',
      id: 'm',
      api: ProviderApi.openaiChat,
      baseUrl: config.baseUrl,
      contextWindow: 1000,
      maxOutputTokens: 100,
    );
    final events = await collect(stream(model, context), clock);
    return (terminalOf(events), logger);
  }

  test(
    'ClientException with uri= gives a type-only connection error',
    () async {
      final (message, logger) = await failWith(
        http.ClientException(
          'Connection reset',
          Uri.parse('https://x.test/v1/chat?key=$secret'),
        ),
      );

      expect(message.errorClass, LlmErrorClass.network);
      expect(message.errorMessage, isNot(contains(secret)));
      expect(
        message.errorMessage,
        contains('connection failed: ClientException'),
      );
      expect(logger.records.join('\n'), isNot(contains(secret)));
    },
  );

  test('another error text has URLs masked', () async {
    final (message, logger) = await failWith(
      StateError('bad https://x.test/v1?key=$secret end'),
    );

    expect(message.errorMessage, isNot(contains(secret)));
    expect(message.errorMessage, contains('<url>'));
    expect(logger.records.join('\n'), isNot(contains(secret)));
  });
}
