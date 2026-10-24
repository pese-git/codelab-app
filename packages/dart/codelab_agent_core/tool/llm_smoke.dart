// Manual smoke of a provider against a real server: one request through
// `createStreamFunction` (adapter, watchdogs, retry), the events and the
// usage are printed. Not run in CI; used to check that
// the hand-written SSE fixtures match real streams (design.md, D9).
//
//   CODELAB_SMOKE_PROVIDER=openai-compatible|anthropic
//   CODELAB_SMOKE_BASE_URL=https://api.openai.com/v1
//   CODELAB_SMOKE_MODEL=gpt-4.1-mini
//   CODELAB_SMOKE_API_KEY=...            (optional for local servers)
//   CODELAB_SMOKE_REASONING=low|medium|high   (optional)
//   CODELAB_SMOKE_THINKING=adaptive|budget    (optional, Anthropic;
//                                              default adaptive)
//   fvm dart run tool/llm_smoke.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final env = Platform.environment;
  String required(String name) =>
      env[name] ??
      (throw StateError('set $name (see the header of this file)'));

  final kind = required('CODELAB_SMOKE_PROVIDER');
  final api = switch (kind) {
    'openai-compatible' => ProviderApi.openaiChat,
    'anthropic' => ProviderApi.anthropicMessages,
    _ => throw StateError('CODELAB_SMOKE_PROVIDER: unknown kind "$kind"'),
  };
  final baseUrl = Uri.parse(required('CODELAB_SMOKE_BASE_URL'));
  final effort = ReasoningEffort.values
      .asNameMap()[env['CODELAB_SMOKE_REASONING']];
  final thinking =
      ThinkingMode.values.asNameMap()[env['CODELAB_SMOKE_THINKING']] ??
      ThinkingMode.adaptive;
  final config = ProviderConfig(
    name: 'smoke',
    api: api,
    baseUrl: baseUrl,
    apiKey: env['CODELAB_SMOKE_API_KEY'],
  );
  final model = ModelRef(
    provider: 'smoke',
    id: required('CODELAB_SMOKE_MODEL'),
    api: api,
    baseUrl: baseUrl,
    contextWindow: 32000,
    maxOutputTokens: 4096,
    supportsReasoning: effort != null,
    reasoningEffort: effort,
    thinkingMode: thinking,
  );
  final client = http.Client();
  final services = CoreLlmServices(
    httpClient: client,
    clock: const SystemClock(),
    random: Random(),
    logger: _StderrLogger(),
  );
  final stream = createStreamFunction(config, services);

  final context = LlmContext(
    systemPrompt: 'You are a terse assistant. Use the tool when asked.',
    messages: [
      UserMessage([
        const TextContent(
          'Say hello in three words, then call read for README.md.',
        ),
      ], timestamp: DateTime.now().toUtc()),
    ],
    tools: [
      ToolSchema(
        name: 'read',
        description: 'Read a text file.',
        parameters: const {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
        },
      ),
    ],
    cacheKey: 'smoke-session',
  );

  try {
    await for (final event in stream(model, context)) {
      print(switch (event) {
        StartEvent() => 'start',
        BlockStartEvent(:final index, :final kind) =>
          'block $index ${kind.name}',
        BlockDeltaEvent(:final index, :final delta) =>
          '  $index +${_show(delta)}',
        BlockEndEvent(:final index, :final block) => 'end $index $block',
        DoneEvent(:final message) =>
          'done ${message.stopReason.name} raw=${message.rawStopReason} '
              '${message.usage}',
        ErrorEvent(:final error) =>
          'error ${error.errorClass?.name}: ${error.errorMessage}',
      });
    }
  } finally {
    client.close();
  }
}

String _show(String delta) => delta.replaceAll('\n', r'\n');

final class _StderrLogger implements Logger {
  @override
  bool isEnabled(LogLevel level) => true;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) => stderr.writeln('[${level.name}] $event $fields');
}
