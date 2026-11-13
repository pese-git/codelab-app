import 'dart:convert';

import 'package:http/http.dart' as web;
import 'package:http/testing.dart';

/// Шаг ответа фейкового провайдера (OpenAI chat completions, SSE).
sealed class OpenAiStep {
  const OpenAiStep();

  /// Ответ текстом: ход заканчивается.
  const factory OpenAiStep.text(String text) = _TextStep;

  /// Вызов инструмента [name] с аргументами [arguments].
  const factory OpenAiStep.tool(
    String id,
    String name,
    Map<String, Object?> arguments,
  ) = _ToolStep;
}

final class _TextStep extends OpenAiStep {
  const _TextStep(this.text);
  final String text;
}

final class _ToolStep extends OpenAiStep {
  const _ToolStep(this.id, this.name, this.arguments);
  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

/// Фейковый провайдер: n-й запрос получает n-й шаг, дальше — текст `done`;
/// тела запросов запоминаются для проверок.
///
/// Почему не `scriptedEmbeddedAgentOpener`: тесты открывателя
/// `localEmbeddedAgentOpener` проверяют именно его проводку (`skillFiles`,
/// `hostFiles`), а у него функция модели настоящая — подменяется только
/// `http.Client` (PKG-6). Сети нет.
final class OpenAiScript {
  OpenAiScript(this._steps);

  final List<OpenAiStep> _steps;

  /// Тела запросов к провайдеру в порядке прихода (JSON-строки).
  final bodies = <String>[];

  /// Клиент для `localEmbeddedAgentOpener(httpClient: …)`.
  web.Client get client => MockClient.streaming((request, body) async {
    bodies.add(utf8.decode(await body.expand((c) => c).toList()));
    final index = bodies.length - 1;
    final step = index < _steps.length
        ? _steps[index]
        : const OpenAiStep.text('done');
    final chunks = switch (step) {
      _TextStep(:final text) => [
        _chunk({'role': 'assistant', 'content': text}, null),
        _chunk({}, 'stop'),
      ],
      _ToolStep(:final id, :final name, :final arguments) => [
        _chunk({
          'role': 'assistant',
          'tool_calls': [
            {
              'index': 0,
              'id': id,
              'type': 'function',
              'function': {'name': name, 'arguments': jsonEncode(arguments)},
            },
          ],
        }, null),
        _chunk({}, 'tool_calls'),
      ],
    };
    return web.StreamedResponse(
      Stream.value(utf8.encode('${chunks.join()}data: [DONE]\n\n')),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });

  static String _chunk(Map<String, Object?> delta, String? finish) =>
      'data: ${jsonEncode({
        'id': 'c',
        'object': 'chat.completion.chunk',
        'created': 1,
        'model': 'm',
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      })}\n\n';
}

/// Текст последнего результата инструмента в теле запроса [body]; `null`,
/// если результатов инструментов в запросе нет.
String? lastToolResultOf(String body) {
  final messages =
      (jsonDecode(body) as Map<String, Object?>)['messages']! as List<Object?>;
  final tools = [
    for (final m in messages)
      if (m is Map<String, Object?> && m['role'] == 'tool') m['content'],
  ];
  if (tools.isEmpty) {
    return null;
  }
  final content = tools.last;
  return content is String ? content : jsonEncode(content);
}

/// Текст системной подсказки в теле запроса [body].
String systemPromptOf(String body) {
  final messages =
      (jsonDecode(body) as Map<String, Object?>)['messages']! as List<Object?>;
  return [
    for (final m in messages)
      if (m is Map<String, Object?> &&
          (m['role'] == 'system' || m['role'] == 'developer'))
        m['content'] is String ? m['content']! : jsonEncode(m['content']),
  ].join('\n');
}
