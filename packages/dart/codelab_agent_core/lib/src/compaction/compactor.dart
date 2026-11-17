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

import 'dart:math' as math;

import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../llm/stream_function.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../session/ids.dart';
import '../session/projections.dart';
import '../session/records.dart';
import '../session/session_store.dart' show SessionSnapshot;
import '../session/session_writer.dart';
import '../session/tree.dart';
import '../skills/active_skills.dart';
import '../skills/reattach.dart';
import '../skills/skill_catalog.dart';
import '../skills/skill_invocation.dart' show sha256Hex;
import '../skills/skills_config.dart';
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

/// Сжимать нечего: `no cut point` — нет среза, `no reduction` — резюме не
/// уменьшает оценку контекста (CMP-10); последнее видно в логе
/// `compaction.skipped`. Хосты отвечают на обе причины одинаково (`/compact` —
/// `Nothing to compact.`), аварийный путь трактует как «сжатие не помогло».
final class NothingToCompact extends CompactionOutcome {
  const NothingToCompact(this.reason);

  /// `no cut point` или `no reduction`.
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
/// [skillCatalog] и [skillsConfig] — каталог и бюджеты сессии (design.md
/// change `add-agent-skills`, D15, D20): запись получает `skills`, оценки
/// `tokensAfter` и порога CMP-5 считаются по проекции с приложенным
/// сообщением, а при непустом списке пишется лог `skills.reattached`.
/// Если сообщение навыков одно поднимает оценку выше порога, давние навыки
/// выбрасываются из записи вместо нового прохода (Q49 (б), D20 «M2»).
/// `skillCatalog == null` — навыков нет, поведение прежнее.
///
/// Порог CMP-5 и выброс навыков по окну сравнивают `max(согласованное после,
/// эвристика проекции без якоря)` (D9): цикл после сжатия видит именно
/// эвристику, и «после» ниже порога при эвристике выше окна терял бы ход.
/// В запись, событие и лог идёт согласованное «после».
///
/// Первый проход без среза или без выигрыша — [NothingToCompact] (причины
/// `no cut point` и `no reduction`; обе пишут лог `compaction.skipped` с
/// `reason`). Проход без выигрыша — когда согласованная оценка после него не
/// меньше оценки до (`after >= before`, CMP-10, D3): запись не пишется.
/// Оценка «после» — [estimateAfterCompaction] (D1), «до» следующего прохода —
/// «после» прошлого (D2). Пока `max(после, эвристика)` выше порога (D9), идёт
/// следующий проход (не больше [maxCompactionPasses]); его [NothingToCompact]
/// или [CompactionFailed] не отменяют уже записанное, и результатом остаётся
/// [Compacted] прошлого прохода.
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
  Logger? logger,
  SkillCatalog? skillCatalog,
  SkillsConfig skillsConfig = const SkillsConfig(),
}) async {
  LlmContextProjection project(SessionSnapshot snapshot, {Logger? log}) =>
      buildLlmContext(
        snapshot,
        logger: log,
        skillCatalog: skillCatalog,
        skillsConfig: skillsConfig,
      );
  int estimate(LlmContextProjection p) => estimateContextTokens(
    p.messages,
    systemPrompt: systemPrompt,
    tools: tools,
  );
  // Эвристика без якоря: из её разницы строится согласованное «после» (D1).
  int raw(LlmContextProjection p) =>
      estimateTokens(p.messages, systemPrompt: systemPrompt, tools: tools);
  final session = writer.snapshot.header.id;
  final threshold = compactionThreshold(window, settings);
  Compacted? done;
  for (var pass = 0; pass < maxCompactionPasses; pass++) {
    final snapshot = writer.snapshot;
    final projectionBefore = project(snapshot, log: logger);
    // «До» первого прохода — с якорем на usage. Следующие проходы берут
    // «после» прошлого: в проекции уже нет якоря (§8.7), и пересчёт дал бы
    // чистую эвристику — ту же ошибку, что D1 убирает (D2).
    final before = done?.tokensAfter ?? estimate(projectionBefore);
    final rawBefore = raw(projectionBefore);
    final (:region, :last) = compactionRegion(snapshot, logger: logger);
    final cut = findCutPoint(region, settings);
    if (cut == null) {
      // Видимая причина «сжимать нечего» (как `no reduction` ниже): без лога
      // оператор не отличал пустой регион от сжатия, которое не дало выигрыша.
      // Полей оценок нет: проход до них не дошёл (D3).
      logger?.log(
        LogLevel.info,
        'compaction.skipped',
        fields: {
          'session_id': session.value,
          'trigger': trigger.name,
          'pass': pass + 1,
          'reason': 'no cut point',
        },
      );
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
    final SummaryResult result;
    try {
      result = await summarize(
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
    // Запись собирается из одних и тех же полей несколько раз: черновик для
    // расчёта хвоста, пробные списки `skills` для оценки по окну и итоговая
    // запись с `tokensAfter`.
    final recordId = newRecordId(ids, snapshot.byId.containsKey);
    final recordTime = clock.now();
    final firstKeptId = region[cut.firstKeptIndex].id;
    final details = {
      'readFiles': files.read,
      'modifiedFiles': files.modified,
      'splitTurn': cut.splitTurn,
      // Модель и usage суммаризатора (design.md change `add-usage-ledger`,
      // D4): формат журнала не меняется, поле `usage` описано в §8.2.4.
      'summaryModel': result.model,
      'usage': result.usage.toJson(),
    };
    CompactionRecord withFields({
      List<CompactionSkill> skills = const [],
      int tokensAfter = 0,
    }) => CompactionRecord(
      id: recordId,
      parentId: snapshot.leafId,
      timestamp: recordTime,
      summary: result.text,
      firstKeptId: firstKeptId,
      tokensBefore: before,
      tokensAfter: tokensAfter,
      details: details,
      skills: skills.isEmpty ? null : skills,
    );
    // Две величины одной проекции после прохода (D1, D9): `after` —
    // согласованная оценка (идёт в запись, события, лог и проверку выигрыша),
    // `raw` — чистая эвристика без якоря, то есть то, что увидят preflight
    // цикла и `afterTurn` (якоря после сжатия нет, §8.7).
    ({int after, int raw}) estimateWith(List<CompactionSkill> skills) {
      final draft = withFields(skills: skills);
      final rawAfter = raw(
        project(snapshot.withRecord(draft, leafAfter(draft))),
      );
      return (
        after: estimateAfterCompaction(
          before: before,
          rawBefore: rawBefore,
          rawAfter: rawAfter,
        ),
        raw: rawAfter,
      );
    }

    // Порог сравнивается с `max(after, raw)` (D9): иначе согласованное
    // «после» ниже порога, а цикл после сжатия получает эвристику выше окна —
    // аварийный вызов уже использован (CMP-8), и ход теряется. Для всех
    // триггеров одинаково.
    bool overThreshold(({int after, int raw}) e) =>
        math.max(e.after, e.raw) > threshold;

    // Навыки записи (D15, D20): активные до сжатия, кроме тех, чья последняя
    // активация осталась в хвосте после нового `firstKeptId` — их блок и так
    // в контексте. Хвостовые активации даёт та же `activeSkills`, если
    // поставить на лист запись без `skills`: её `carried` пуст.
    final candidates = skillCatalog == null
        ? const <CompactionSkill>[]
        : _skillsOf(snapshot, withFields(), skillCatalog, skillsConfig);
    // Окно модели (решение Q49 (б), D20 «M2»): если оценка выше порога только
    // из-за сообщения навыков (без него укладывается), нового прохода не
    // будет — давние навыки выбрасываются с конца, пока оценка не уложится.
    // Если не укладывается и без них, работает обычный CMP-5. Решение лежит в
    // самой записи, поэтому проекция и `activeSkills` окна не знают. Сравнение
    // с порогом — по `max(after, raw)` (D9), как у CMP-5.
    var skills = candidates;
    var estimated = estimateWith(skills);
    if (skills.isNotEmpty &&
        overThreshold(estimated) &&
        !overThreshold(estimateWith(const []))) {
      while (skills.isNotEmpty && overThreshold(estimated)) {
        skills = skills.sublist(0, skills.length - 1);
        estimated = estimateWith(skills);
      }
    }
    final after = estimated.after;
    final droppedWindow = skillCatalog == null
        ? 0
        : _attachedCount(candidates, skillCatalog, skillsConfig) -
              _attachedCount(skills, skillCatalog, skillsConfig);
    // Нет выигрыша (CMP-10, D3): запись, которая не уменьшает оценку, только
    // заменяет дословный текст пересказом. Проверка — после выбора навыков и
    // до записи; навыки ради выигрыша не выбрасываются (D6), их активации
    // остаются в контексте как были.
    if (after >= before) {
      logger?.log(
        LogLevel.info,
        'compaction.skipped',
        fields: {
          'session_id': session.value,
          'trigger': trigger.name,
          'pass': pass + 1,
          'reason': 'no reduction',
          'tokens_before': before,
          'tokens_after': after,
        },
      );
      return done ?? const NothingToCompact('no reduction');
    }
    // tokensAfter — согласованная оценка (D1) по проекции с ещё не записанной
    // записью и с приложенным сообщением навыков (CMP-5): запись пишется один
    // раз и уже с итоговым числом (§9.8, шаг 9).
    final record = withFields(skills: skills, tokensAfter: after);
    await writer.appendBuilt(record, durable: true);
    onCompacted?.call(project(writer.snapshot, log: logger));
    await emit(
      ContextCompacted(
        session,
        tokensBefore: before,
        tokensAfter: after,
        usage: result.usage,
        model: result.model,
      ),
    );
    if (skillCatalog != null && candidates.isNotEmpty) {
      _logReattached(
        logger,
        session,
        candidates,
        skills,
        skillCatalog,
        skillsConfig,
        droppedWindow: droppedWindow,
      );
    }
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
    if (!overThreshold(estimated)) {
      break;
    }
  }
  return done!;
}

/// Элементы `compaction.skills` для [draft] (запись без `skills`) на снимке
/// [before] (D15, D20, «Запись»).
List<CompactionSkill> _skillsOf(
  SessionSnapshot before,
  CompactionRecord draft,
  SkillCatalog catalog,
  SkillsConfig config,
) {
  final inTail = {
    for (final s in activeSkills(
      before.withRecord(draft, leafAfter(draft)),
      catalog,
      config,
    ))
      s.name,
  };
  return [
    for (final s in activeSkills(before, catalog, config))
      if (!inTail.contains(s.name))
        CompactionSkill(
          name: s.name,
          fingerprint: sha256Hex(catalog.skill(s.name)!.body),
        ),
  ];
}

/// Сколько навыков [skills] будет приложено (для счёта `dropped_window`).
int _attachedCount(
  List<CompactionSkill> skills,
  SkillCatalog catalog,
  SkillsConfig config,
) => reattachSkills(skills, catalog, config).attached.length;

/// Лог `skills.reattached` (info, D13, D20): приложенные в порядке
/// сообщения, число выпавших по бюджету, усечённых и выброшенных по окну
/// (`dropped_window`, Q49); без тел и отпечатков. При `0` в
/// бюджете сообщения нет, и лога тоже.
///
/// [candidates] — список до выброса по окну: по нему считается `dropped`,
/// иначе навык, выпавший по общему бюджету и затем убранный окном из
/// записи, не попал бы ни в один счётчик. [skills] — итоговый список записи:
/// по нему `names` и `truncated`.
void _logReattached(
  Logger? logger,
  SessionId session,
  List<CompactionSkill> candidates,
  List<CompactionSkill> skills,
  SkillCatalog catalog,
  SkillsConfig config, {
  required int droppedWindow,
}) {
  if (config.reattachPerSkillTokens <= 0 || config.reattachTotalTokens <= 0) {
    return;
  }
  final result = reattachSkills(skills, catalog, config);
  final dropped = reattachSkills(candidates, catalog, config).dropped;
  logger?.log(
    LogLevel.info,
    'skills.reattached',
    fields: {
      'session_id': session.value,
      'names': [for (final s in result.attached) s.skill.name],
      'dropped': dropped,
      'truncated': result.truncated,
      'dropped_window': droppedWindow,
    },
  );
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
