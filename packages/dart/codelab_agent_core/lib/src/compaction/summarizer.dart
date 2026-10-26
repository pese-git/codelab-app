/// Резюме региона моделью (`agent-core-architecture` §9.7).
///
/// Почему регион сериализуется в текст, а не уходит историей разговора:
/// получив историю, модель продолжила бы разговор вместо того, чтобы его
/// пересказать. Почему обязательные разделы: резюме по фиксированным
/// разделам сохраняет состояние задачи и открытые просьбы пользователя
/// (CMP-9), а обрезание старых сообщений теряло бы их.
///
/// Как использовать: компактор собирает [SummaryRequest] и вызывает
/// [Summarizer]; ядро создаёт его через [modelSummarizer] над той же
/// `StreamFunction` и моделью сессии (design.md change
/// `add-agent-core-sessions-and-compaction`, D8). Ошибка модели и пустой
/// ответ — [CompactionFailure], отмена — `CancelledException` (CMP-4).
library;

import 'dart:convert';
import 'dart:math' as math;

import '../cancel/cancel_token.dart';
import '../llm/events.dart';
import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/stream_function.dart';
import '../loop/agent_events.dart';
import '../prompts/prompts.g.dart';
import '../session/records.dart';
import '../session/user_words.dart';
import '../util/clock.dart';
import 'estimate.dart';
import 'settings.dart';

/// Прочитанные и изменённые файлы региона (§9.7, `FileOps`).
final class FileOps {
  const FileOps({this.read = const [], this.modified = const []});

  /// Пути из аргументов `read`.
  final List<String> read;

  /// Пути из аргументов `write` и `edit`.
  final List<String> modified;
}

/// Что сжимать и с чем (§9.2).
final class SummaryRequest {
  const SummaryRequest({
    required this.region,
    this.previousSummary,
    this.turnPrefix,
    this.fileOps = const FileOps(),
    this.focus,
  });

  /// Сообщения, которые заменит резюме.
  final List<MessageRecord> region;

  /// Резюме прошлого сжатия: основа для обновления (CMP-9).
  final String? previousSummary;

  /// Начало разрезанного хода (§9.6), включая слова пользователя.
  final List<MessageRecord>? turnPrefix;
  final FileOps fileOps;

  /// Указание `/compact <текст>` (K-02); только для триггера `manual`.
  final String? focus;
}

/// Генератор резюме; бросает [CompactionFailure] или `CancelledException`.
typedef Summarizer =
    Future<String> Function(SummaryRequest request, CancelToken cancel);

/// Резюме не получено: ошибка модели или пустой ответ (§9.7, шаги 5, 7).
final class CompactionFailure implements Exception {
  const CompactionFailure(this.message);

  final String message;

  @override
  String toString() => 'CompactionFailure: $message';
}

/// Результаты инструментов длиннее этого сокращаются (§9.7, шаг 1).
const _resultLimit = 4000;
const _resultKeep = 1500;

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Слова пользователя разрезанного хода цитируются не длиннее (CMP-7).
const _quoteLimit = 2000;

/// Суммаризатор над [stream] и [model] сессии (§9.7).
///
/// [settings] задают бюджет текста региона: `max(w - reserve, w/2)` окна
/// модели; без них — пороги `forWindow` того же окна. [clock] — время
/// сообщения запроса; запрос в журнал не пишется.
Summarizer modelSummarizer({
  required StreamFunction stream,
  required ModelRef model,
  required SessionId sessionId,
  CompactionSettings? settings,
  Clock? clock,
}) {
  final window = effectiveContextWindow(model);
  final s = settings ?? CompactionSettings.forWindow(window);
  final budget = math.max(window - s.reserveTokens, window ~/ 2);

  Future<String> ask(String text, CancelToken cancel) async {
    final events = stream(
      model,
      LlmContext(
        systemPrompt: Prompts.compactionSystem.render(const {}),
        messages: [
          UserMessage([TextContent(text)], timestamp: clock?.now() ?? _epoch),
        ],
        cacheKey: '${sessionId.value}:summary',
      ),
      cancel: cancel,
    );
    AssistantMessage? answer;
    await for (final event in events) {
      if (event
          case DoneEvent(:final message) || ErrorEvent(error: final message)) {
        answer = message;
      }
    }
    final message = answer ?? await events.result;
    if (message.stopReason == StopReason.aborted || cancel.isCancelled) {
      throw CancelledException(cancel.reason);
    }
    if (message.stopReason == StopReason.error) {
      throw CompactionFailure(message.errorMessage ?? 'summary model failed');
    }
    final summary = message.content
        .whereType<TextContent>()
        .map((b) => b.text)
        .join()
        .trim();
    if (summary.isEmpty) {
      throw const CompactionFailure('empty summary');
    }
    return summary;
  }

  return (request, cancel) async {
    final files = request.fileOps;
    final focus = request.focus == null
        ? ''
        : Prompts.compactionFocus.render({'text': request.focus!});
    final values = {
      'transcript': _withinBudget(request.region, budget),
      'readFiles': _paths(files.read),
      'modifiedFiles': _paths(files.modified),
      'focus': focus,
    };
    // Разрезанный ход без более раннего региона: новое резюме не нужно,
    // прошлое переносится как есть.
    final main = request.region.isEmpty
        ? request.previousSummary ?? ''
        : await ask(
            request.previousSummary == null
                ? Prompts.compactionSummary.render(values)
                : Prompts.compactionSummaryUpdate.render({
                    ...values,
                    'previousSummary': request.previousSummary!,
                  }),
            cancel,
          );
    final prefix = request.turnPrefix;
    if (prefix == null) {
      return main;
    }
    final context = await ask(
      Prompts.compactionTurnContext.render({
        'transcript': _withinBudget(prefix, budget),
      }),
      cancel,
    );
    final turn =
        '## Current turn context (split turn)\n\n'
        'User request, verbatim:\n\n${_quote(_userText(prefix))}\n\n$context';
    return main.isEmpty ? turn : '$main\n\n---\n\n$turn';
  };
}

/// Регион текстом с заголовками сообщений (§9.7, шаг 1).
String serializeRegion(List<MessageRecord> records) =>
    _entries(records).join('\n\n');

List<String> _entries(List<MessageRecord> records) => [
  for (final record in records) ..._serialize(record),
];

List<String> _serialize(MessageRecord record) {
  final message = record.message;
  switch (message) {
    case UserMessage(:final content):
      final header = isUserWords(record) ? '[user]' : '[notice]';
      return ['$header\n${_text(content)}'];
    case AssistantMessage(:final content):
      final text = _text(content);
      return [
        if (text.isNotEmpty) '[assistant]\n$text',
        for (final call in content.whereType<ToolCall>())
          '[tool call ${call.name}]\n${_canonical(call.arguments)}',
      ];
    case ToolResultMessage(:final toolName, :final isError, :final content):
      final header = isError
          ? '[tool result $toolName, error]'
          : '[tool result $toolName]';
      return ['$header\n${_shorten(_text(content))}'];
  }
}

String _text(List<ContentBlock> content) => [
  for (final block in content)
    switch (block) {
      TextContent(:final text) => text,
      ImageContent() => '[image]',
      _ => null,
    },
].nonNulls.join('\n');

String _shorten(String text) {
  if (text.length <= _resultLimit) {
    return text;
  }
  final omitted = text.length - 2 * _resultKeep;
  return '${text.substring(0, _resultKeep)}\n'
      '[… $omitted characters omitted …]\n'
      '${text.substring(text.length - _resultKeep)}';
}

/// Канонический JSON: ключи по алфавиту на всех уровнях — одинаковые
/// аргументы дают одинаковый текст.
String _canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys.map((k) => '$k').toList()..sort())
      key: _sorted(value[key]),
  },
  List() => [for (final item in value) _sorted(item)],
  _ => value,
};

/// Самые старые сообщения уходят, пока текст не уложится в бюджет
/// (§9.7, шаг 2).
String _withinBudget(List<MessageRecord> records, int budget) {
  final entries = _entries(records);
  var text = entries.join('\n\n');
  var dropped = 0;
  while ((text.length / 4).ceil() > budget && dropped < entries.length - 1) {
    dropped++;
    text = [
      '[… $dropped earlier messages omitted …]',
      ...entries.skip(dropped),
    ].join('\n\n');
  }
  return text;
}

String _paths(List<String> paths) => paths.isEmpty ? 'none' : paths.join(', ');

/// Слова пользователя разрезанного хода (CMP-7).
String _userText(List<MessageRecord> prefix) {
  final words = prefix.where((r) => r.message is UserMessage && isUserWords(r));
  final text = words.isEmpty ? '' : _text(words.first.message.content);
  return text.length <= _quoteLimit ? text : text.substring(0, _quoteLimit);
}

String _quote(String text) =>
    text.split('\n').map((line) => '> $line').join('\n');
