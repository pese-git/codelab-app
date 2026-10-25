/// Сжатие журнала сессии (`agent-core-architecture` §9.8).
///
/// Почему запись, а не правка истории: сжатие только добавляет запись
/// `compaction` (CMP-2). Исходные записи остаются в файле и в реплее, а
/// контекст модели строит проекция `buildLlmContext`. Неудача и отмена
/// ничего не пишут (CMP-3).
///
/// Как использовать: сессия вызывает [compact] с писателем своего журнала
/// после хода (`afterTurn`), из аварийного пути цикла (`preflight`,
/// `overflow`) или по команде (`manual`). Транскрипт сессия заменяет в
/// [onCompacted] — до события `ContextCompacted`.
library;

import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../llm/stream_function.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../session/ids.dart';
import '../session/projections.dart';
import '../session/records.dart';
import '../session/session_writer.dart';
import '../session/tree.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';
import 'cut_point.dart';
import 'estimate.dart';
import 'settings.dart';
import 'summarizer.dart';

/// Откуда пришло сжатие (§9.5).
enum CompactionTrigger { afterTurn, preflight, overflow, manual }

/// Итог [compact]; отмена — не значение, а `CancelledException` (CMP-4).
sealed class CompactionOutcome {
  const CompactionOutcome();
}

final class Compacted extends CompactionOutcome {
  const Compacted(this.record, this.tokensBefore, this.tokensAfter);

  /// Запись последнего прохода.
  final CompactionRecord record;
  final int tokensBefore, tokensAfter;
}

final class NothingToCompact extends CompactionOutcome {
  const NothingToCompact(this.reason);

  final String reason;
}

final class CompactionFailed extends CompactionOutcome {
  const CompactionFailed(this.error);

  final Object error;
}

/// Проходов не больше: каждый сжимает то, что осталось перед хвостом
/// (CMP-5).
const maxCompactionPasses = 3;

/// Сжимает журнал [writer] по шагам §9.8.
///
/// Первый проход без среза — [NothingToCompact]. Пока оценка после прохода
/// выше порога, идёт следующий (не больше [maxCompactionPasses]); его
/// [NothingToCompact] или [CompactionFailed] не отменяют уже записанное, и
/// результатом остаётся [Compacted] прошлого прохода.
Future<CompactionOutcome> compact({
  required SessionWriter writer,
  required CompactionTrigger trigger,
  required Summarizer summarize,
  required CompactionSettings settings,
  required int window,
  required String systemPrompt,
  required List<ToolSchema> tools,
  required IdGenerator ids,
  required Clock clock,
  required CancelToken cancel,
  required AgentEventSink emit,
  void Function(LlmContextProjection projection)? onCompacted,
  String? focus,
  String? summaryModel,
  Logger? logger,
}) async {
  int estimate(LlmContextProjection p) => estimateContextTokens(
    p.messages,
    systemPrompt: systemPrompt,
    tools: tools,
  );
  final session = writer.snapshot.header.id;
  final threshold = compactionThreshold(window, settings);
  Compacted? done;
  for (var pass = 0; pass < maxCompactionPasses; pass++) {
    final snapshot = writer.snapshot;
    final before = estimate(buildLlmContext(snapshot, logger: logger));
    final (:region, :last) = compactionRegion(snapshot, logger: logger);
    final cut = findCutPoint(region, settings);
    if (cut == null) {
      return done ?? const NothingToCompact('no cut point');
    }
    final end = cut.splitTurn ? cut.turnStartIndex : cut.firstKeptIndex;
    final summarized = region.take(end).whereType<MessageRecord>().toList();
    final prefix = cut.splitTurn
        ? region
              .sublist(cut.turnStartIndex, cut.firstKeptIndex)
              .whereType<MessageRecord>()
              .toList()
        : null;
    final files = _fileOps([...summarized, ...?prefix], last);
    final String summary;
    try {
      summary = await summarize(
        SummaryRequest(
          region: summarized,
          previousSummary: last?.summary,
          turnPrefix: prefix,
          fileOps: files,
          // Указание пользователя — только у ручного сжатия (§9.5).
          focus: trigger == CompactionTrigger.manual ? focus : null,
        ),
        cancel,
      );
    } on CompactionFailure catch (error) {
      logger?.log(
        LogLevel.warning,
        'compaction.failed',
        fields: {
          'session_id': session.value,
          'trigger': trigger.name,
          'error': error.message,
        },
      );
      await emit(
        AgentError(
          session,
          cls: AgentErrorClass.compaction,
          message: 'compaction failed: ${error.message}',
        ),
      );
      return done ?? CompactionFailed(error);
    }
    // Отмена после ответа модели тоже не пишет запись (§9.8, шаг 7).
    cancel.throwIfCancelled();
    final draft = CompactionRecord(
      id: newRecordId(ids, snapshot.byId.containsKey),
      parentId: snapshot.leafId,
      timestamp: clock.now(),
      summary: summary,
      firstKeptId: region[cut.firstKeptIndex].id,
      tokensBefore: before,
      tokensAfter: 0,
      details: {
        'readFiles': files.read,
        'modifiedFiles': files.modified,
        'splitTurn': cut.splitTurn,
        'summaryModel': ?summaryModel,
      },
    );
    // tokensAfter — по проекции с ещё не записанной записью: запись
    // пишется один раз и уже с итоговым числом (§9.8, шаг 9).
    final after = estimate(
      buildLlmContext(snapshot.withRecord(draft, leafAfter(draft))),
    );
    final record = CompactionRecord(
      id: draft.id,
      parentId: draft.parentId,
      timestamp: draft.timestamp,
      summary: draft.summary,
      firstKeptId: draft.firstKeptId,
      tokensBefore: before,
      tokensAfter: after,
      details: draft.details,
    );
    await writer.appendBuilt(record, durable: true);
    onCompacted?.call(buildLlmContext(writer.snapshot, logger: logger));
    await emit(
      ContextCompacted(session, tokensBefore: before, tokensAfter: after),
    );
    logger?.log(
      LogLevel.info,
      'compaction.done',
      fields: {
        'session_id': session.value,
        'trigger': trigger.name,
        'pass': pass + 1,
        'tokens_before': before,
        'tokens_after': after,
        'split_turn': cut.splitTurn,
      },
    );
    done = Compacted(record, before, after);
    if (after <= threshold) {
      break;
    }
  }
  return done!;
}

/// Пути `read` (прочитанные) и `write`/`edit` (изменённые) региона плюс
/// списки прошлого сжатия (§9.7, `FileOps`).
FileOps _fileOps(List<MessageRecord> records, CompactionRecord? last) {
  List<String> previous(String key) => [
    for (final path in (last?.details?[key] as List<Object?>?) ?? const [])
      if (path is String) path,
  ];
  final read = {...previous('readFiles')};
  final modified = {...previous('modifiedFiles')};
  for (final record in records) {
    if (record.message case AssistantMessage(:final toolCalls)) {
      for (final call in toolCalls) {
        if (call.arguments['path'] case final String path) {
          switch (call.name) {
            case 'read':
              read.add(path);
            case 'write' || 'edit':
              modified.add(path);
          }
        }
      }
    }
  }
  return FileOps(read: read.toList(), modified: modified.toList());
}
