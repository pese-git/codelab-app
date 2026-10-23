import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/overflow.dart';
import 'package:codelab_agent_core/src/llm/stream_state.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/models.dart';

AssistantMessage _message({
  StopReason stopReason = StopReason.error,
  String? errorMessage,
  LlmErrorClass? errorClass,
  Usage usage = Usage.zero,
}) => AssistantMessage(
  content: const [],
  model: testModel,
  usage: usage,
  stopReason: stopReason,
  errorMessage: errorMessage,
  errorClass: errorClass,
  timestamp: DateTime.utc(2026),
);

void main() {
  group('isContextOverflow (§2.11)', () {
    test('the class set by the adapter', () {
      expect(
        isContextOverflow(
          _message(errorClass: LlmErrorClass.overflow),
          contextWindow: 1000,
        ),
        isTrue,
      );
    });

    for (final phrase in overflowPhrases) {
      test('400 with "$phrase"', () {
        expect(
          isContextOverflow(
            _message(
              errorMessage: 'local 400: Error: ${phrase.toUpperCase()} here',
              errorClass: LlmErrorClass.badRequest,
            ),
            contextWindow: 1000,
          ),
          isTrue,
        );
      });
    }

    test('a phrase with a rate limit sign is not overflow', () {
      expect(
        isContextOverflow(
          _message(
            errorMessage: 'local 400: context length — tokens per minute',
            errorClass: LlmErrorClass.badRequest,
          ),
          contextWindow: 1000,
        ),
        isFalse,
      );
    });

    test('a phrase with another status is not overflow', () {
      expect(
        isContextOverflow(
          _message(
            errorMessage: 'local 500: context length exceeded',
            errorClass: LlmErrorClass.server,
          ),
          contextWindow: 1000,
        ),
        isFalse,
      );
    });

    test('silent overflow: stop with input over the window', () {
      expect(
        isContextOverflow(
          _message(
            stopReason: StopReason.stop,
            usage: const Usage(input: 700, cacheRead: 400),
          ),
          contextWindow: 1000,
        ),
        isTrue,
      );
      expect(
        isContextOverflow(
          _message(stopReason: StopReason.stop, usage: const Usage(input: 900)),
          contextWindow: 1000,
        ),
        isFalse,
      );
    });

    test('length with zero output at 99 % of the window', () {
      expect(
        isContextOverflow(
          _message(
            stopReason: StopReason.length,
            usage: const Usage(input: 990),
          ),
          contextWindow: 1000,
        ),
        isTrue,
      );
      expect(
        isContextOverflow(
          _message(
            stopReason: StopReason.length,
            usage: const Usage(input: 990, output: 1),
          ),
          contextWindow: 1000,
        ),
        isFalse,
      );
    });
  });

  group('the adapter turns silent overflow into ErrorEvent', () {
    final small = ModelRef(
      provider: 'test',
      id: 'small',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost/v1'),
      contextWindow: 1000,
      maxOutputTokens: 256,
    );

    Future<AssistantMessageEvent> finish(StopReason reason, Usage usage) async {
      final events = await runProvider(small, null, FakeClock(), (state) async {
        state
          ..start()
          ..setUsage(usage)
          ..finish(reason);
      }).toList();
      return events.last;
    }

    test('stop over the window', () async {
      final event = await finish(StopReason.stop, const Usage(input: 1200));

      expect(event, isA<ErrorEvent>());
      final error = (event as ErrorEvent).error;
      expect(error.errorClass, LlmErrorClass.overflow);
      expect(error.errorMessage, contains('1000'));
    });

    test('length with zero output near the window', () async {
      final event = await finish(StopReason.length, const Usage(input: 995));

      expect((event as ErrorEvent).error.errorClass, LlmErrorClass.overflow);
    });

    test('a normal answer stays DoneEvent', () async {
      expect(
        await finish(StopReason.stop, const Usage(input: 500)),
        isA<DoneEvent>(),
      );
    });
  });
}
