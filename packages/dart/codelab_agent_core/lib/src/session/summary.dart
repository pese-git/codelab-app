/// Сводка сессии для списка сессий (`agent-core-architecture` §8.10).
///
/// Почему отдельно от остальных проекций: сводку строят хранилища журнала,
/// в том числе `JsonlSessionStore` другого пакета, поэтому она входит в
/// публичный API порта хранилища (design.md этапа 3, D1), а остальные
/// проекции остаются внутренними.
library;

import '../commands/slash_command.dart';
import '../llm/messages.dart';
import '../util/logger.dart';
import 'records.dart';
import 'session_store.dart';
import 'tree.dart';
import 'user_words.dart';

/// Сводка сессии для списка (§8.10).
SessionSummary summarize(SessionSnapshot snapshot, {Logger? logger}) {
  final path = pathToLeaf(snapshot, logger: logger);
  String? title;
  for (final record in path.reversed) {
    if (record case SessionInfoRecord(title: final t?) when t.isNotEmpty) {
      title = t;
      break;
    }
  }
  if (title == null) {
    final words = path.where((r) => isUserWords(r, logger: logger));
    if (words.firstOrNull case final first?) {
      title = sessionTitleFrom(_firstText(first));
    }
  }
  var count = 0;
  AssistantMessage? lastAnswer;
  for (final record in path) {
    if (record is! MessageRecord) {
      continue;
    }
    if (record.message case final AssistantMessage answer) {
      count++;
      lastAnswer = answer;
    } else if (isUserWords(record, logger: logger)) {
      count++;
    }
  }
  return SessionSummary(
    id: snapshot.header.id,
    cwd: snapshot.header.cwd,
    title: title,
    updatedAt:
        snapshot.records.lastOrNull?.timestamp ?? snapshot.header.created,
    messageCount: count,
    lastTurnFailed: lastAnswer?.stopReason == StopReason.error,
  );
}

/// Заголовок из текста пользователя: пробелы схлопнуты, не длиннее 80
/// символов, обрезка по границе слова с `…` (§8.10, шаг 1).
String? sessionTitleFrom(String text) {
  final collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) {
    return null;
  }
  if (collapsed.length <= 80) {
    return collapsed;
  }
  final cut = collapsed.substring(0, 79);
  final space = cut.lastIndexOf(' ');
  return '${(space > 0 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// Текст для заголовка. Развёрнутая команда шаблона даёт то, что набрал
/// пользователь (`/<name> <args>`), как реплей, а не тело шаблона: иначе
/// заголовок списка сессий показал бы служебный текст (agent-sessions «Поле
/// записи command»; D8). Неизвестный источник — текст сообщения.
String _firstText(SessionRecord record) {
  final message = record as MessageRecord;
  if (message.command case final command?
      when command.source == SlashCommandSource.template.wire) {
    return command.displayText;
  }
  return message.message.content
          .whereType<TextContent>()
          .map((b) => b.text)
          .firstOrNull ??
      '';
}
