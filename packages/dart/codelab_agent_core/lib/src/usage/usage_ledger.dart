/// Журнал usage сессии: модель и свёртка записей (design.md change
/// `add-usage-ledger`, D1, D2; `agent-core/12-observability-and-errors.md`
/// §12.6.1; OBS-10).
///
/// Почему в ядре: `/usage` и ACP-адаптер строят одну и ту же свёртку, и
/// правило шага (`noUsage`, `loop_note`, `steer`) должно жить в одном месте.
///
/// Как использовать: `buildUsageLedger(snapshot)` — чистая функция записей
/// (ни файлов, ни часов); [UsageLedger.serialize] даёт побайтово
/// воспроизводимый `usage.json` v1 (D3).
library;

import 'dart:convert';

import '../llm/messages.dart';
import '../llm/model_catalog.dart';
import '../llm/usage.dart';
import '../session/command_display.dart';
import '../session/records.dart';
import '../session/session_store.dart';
import '../session/tree.dart';
import '../session/user_words.dart';
import '../subagents/subagent_model.dart';

/// Шаг журнала usage: один ответ модели (design.md change
/// `add-usage-ledger`, D1 п. 1, 2, 4).
///
/// Почему отдельный тип: панель и `/usage` показывают usage по шагам, а
/// «провайдер не прислал usage» (`noUsage`) выводится из записи, поэтому
/// флаг лежит в свёртке, а не в клиенте.
///
/// Для чего: строки хода в `usage.json`. Как использовать: берётся из
/// `UsageLedgerTurn.steps`; [toolCallIds] — id блоков `toolCall` ответа,
/// по ним клиент подписывает шаг заголовком вызова из своего транскрипта.
final class UsageLedgerStep {
  const UsageLedgerStep({
    required this.recordId,
    required this.model,
    required this.usage,
    required this.noUsage,
    this.toolCallIds = const [],
  });

  final String recordId;

  /// `<provider>/<id>`.
  final String model;
  final Usage usage;

  /// Провайдер не прислал usage: не `error` и все четыре счётчика нулевые.
  final bool noUsage;
  final List<String> toolCallIds;
}

/// Группа с числом и суммой usage: завершённые субагенты (`runs`) или вызовы
/// суммаризатора (`count`) (D1 пп. 5, 6).
///
/// Почему отдельно от шагов: их usage входит в итог хода или сессии, но
/// шагом не считается, и в моделях его нет (D1 п. 7). Для чего: строки
/// `Subagents` и `Summaries` и ключи `subagents` и `summaries` файла. Как
/// использовать: читать из `UsageLedger.subagents`, `summaries` и
/// `UsageLedgerTurn.subagents`; `null` — группы нет.
final class UsageLedgerGroup {
  const UsageLedgerGroup({
    required this.count,
    required this.usage,
    this.models = const [],
  });

  final int count;
  final Usage usage;

  /// Только у `summaries` (D1 п. 6): отсортированные различные
  /// `details.summaryModel`, `<provider>/<id>`.
  final List<String> models;
}

/// Ход сессии: от слов пользователя до следующего хода (D1 п. 3, Q9).
///
/// Почему так: ход в журнале usage должен совпадать с ходом живой сессии
/// (`TurnEnded.usage`), поэтому `steer` его не открывает, а служебные записи
/// остаются в ходе. Для чего: таблица «по ходам» панели. Как использовать:
/// из `UsageLedger.turns`; [usage] — шаги плюс субагенты хода, [title] —
/// слова пользователя по правилу S-16 (без пробелов по краям, пробелы и
/// переводы строк схлопнуты, не больше 64 рун).
final class UsageLedgerTurn {
  const UsageLedgerTurn({
    required this.recordId,
    required this.title,
    required this.usage,
    required this.steps,
    this.subagents,
  });

  final String recordId;

  /// Первые 64 руны текста; у команды — её исходный текст.
  final String title;

  /// Шаги хода плюс завершённые субагенты хода.
  final Usage usage;
  final List<UsageLedgerStep> steps;
  final UsageLedgerGroup? subagents;
}

/// Сумма шагов одной модели (D1 п. 7).
///
/// Для чего: блок `By model` и таблица «по моделям». В суммах только шаги:
/// модели субагентов и суммаризатора родителю не видны (R3 change
/// `add-usage-extension`). Как использовать: из `UsageLedger.byModel`,
/// в лексикографическом порядке [model] (`<provider>/<id>`).
final class UsageLedgerModel {
  const UsageLedgerModel({
    required this.model,
    required this.steps,
    required this.usage,
  });

  final String model;
  final int steps;
  final Usage usage;
}

/// Журнал usage сессии — то, что пишется в `usage.json` (D2, D3).
final class UsageLedger {
  const UsageLedger({
    required this.sessionId,
    required this.records,
    required this.lastRecordId,
    required this.steps,
    required this.total,
    this.byModel = const [],
    this.turns = const [],
    this.subagents,
    this.summaries,
    this.subagentRuns = const [],
    this.summaryCalls = const [],
  });

  final String sessionId;

  /// `source.records`: число разобранных записей.
  final int records;

  /// `source.lastRecordId`; `null` у пустого журнала.
  final String? lastRecordId;

  /// Число шагов по всем записям файла (D1 п. 8), не только по пути до
  /// листа.
  final int steps;
  final Usage total;
  final List<UsageLedgerModel> byModel;
  final List<UsageLedgerTurn> turns;
  final UsageLedgerGroup? subagents;
  final UsageLedgerGroup? summaries;

  /// Usage каждого учтённого прогона субагента, в порядке файла. В `usage.json`
  /// НЕ пишется (формат v1 хранит только сумму, D3): нужен печати цены
  /// `/usage`, где эвристика «токены при нулевой стоимости» применяется к
  /// каждому прогону отдельно (D2, «Цена групп без шагов»).
  final List<Usage> subagentRuns;

  /// Каждый учтённый вызов суммаризатора: usage и `details.summaryModel`
  /// (`null`, если его нет). В `usage.json` пишутся только сумма и список
  /// различных моделей; по вызовам цена считается в момент показа (D2).
  final List<({Usage usage, String? model})> summaryCalls;

  /// `usage.json` формата v1: ключи в порядке формата, без пробелов вне
  /// строк, `\n` в конце; стоимость округлена до 10⁻⁶ (D3). Времени
  /// построения и других значений вне записей журнала в тексте нет (OBS-10).
  String serialize() {
    Map<String, Object?> group(UsageLedgerGroup g, String countKey) => {
      countKey: g.count,
      'usage': _usageJson(g.usage),
      if (g.models.isNotEmpty) 'models': g.models,
    };
    final json = <String, Object?>{
      'version': 1,
      'sessionId': sessionId,
      'source': {'records': records, 'lastRecordId': ?lastRecordId},
      'steps': steps,
      'total': _usageJson(total),
      if (byModel.isNotEmpty)
        'byModel': [
          for (final m in byModel)
            {'model': m.model, 'steps': m.steps, 'usage': _usageJson(m.usage)},
        ],
      if (turns.isNotEmpty)
        'turns': [
          for (final t in turns)
            {
              'recordId': t.recordId,
              'title': t.title,
              'usage': _usageJson(t.usage),
              'steps': [
                for (final step in t.steps)
                  {
                    'recordId': step.recordId,
                    'model': step.model,
                    'usage': _usageJson(step.usage),
                    'noUsage': step.noUsage,
                    if (step.toolCallIds.isNotEmpty)
                      'toolCallIds': step.toolCallIds,
                  },
              ],
              if (t.subagents case final g?) 'subagents': group(g, 'runs'),
            },
        ],
      if (subagents case final g?) 'subagents': group(g, 'runs'),
      if (summaries case final g?) 'summaries': group(g, 'count'),
    };
    return '${jsonEncode(json)}\n';
  }
}

/// `Usage` формы §8.2.3 с ценой, округлённой до 10⁻⁶ (D3).
Map<String, Object?> _usageJson(Usage u) => {
  'input': u.input,
  'output': u.output,
  'cacheRead': u.cacheRead,
  'cacheWrite': u.cacheWrite,
  'reasoning': ?u.reasoning,
  'cost': {
    'input': _round6(u.cost.input),
    'output': _round6(u.cost.output),
    'cacheRead': _round6(u.cost.cacheRead),
    'cacheWrite': _round6(u.cost.cacheWrite),
  },
};

double _round6(double v) => (v * 1e6).round() / 1e6;

/// Чистая свёртка записей журнала (D1). Не читает файлы и часы.
///
/// Почему две обходки: ходы и шаги по ходам берутся по пути до активного
/// листа (`pathToLeaf`, §8.4), а итог, модели, субагенты и суммаризатор — по
/// всем записям файла (D1 п. 8). Пока ядро не пишет веток, пути совпадают.
UsageLedger buildUsageLedger(SessionSnapshot snapshot) {
  final records = snapshot.records;

  // Последняя запись каждого `subagentId` в файле: учитывается, если она
  // завершена и несёт usage (D1 п. 5).
  final lastOfSubagent = <SubagentId, SubagentRecord>{};
  for (final r in records) {
    if (r is SubagentRecord) {
      lastOfSubagent[r.subagentId] = r;
    }
  }
  bool counted(SubagentRecord r) =>
      identical(lastOfSubagent[r.subagentId], r) &&
      r.status != 'running' &&
      r.usage != null;

  var total = Usage.zero;
  var steps = 0;
  final byModel = <String, ({int steps, Usage usage})>{};
  final runs = <Usage>[];
  final calls = <({Usage usage, String? model})>[];
  for (final r in records) {
    switch (r) {
      case MessageRecord(:final message) when _isStep(r):
        final answer = message as AssistantMessage;
        steps++;
        total += answer.usage;
        final key = _modelKey(answer);
        final prev = byModel[key];
        byModel[key] = (
          steps: (prev?.steps ?? 0) + 1,
          usage: (prev?.usage ?? Usage.zero) + answer.usage,
        );
      case SubagentRecord(:final usage?) when counted(r):
        runs.add(usage);
        total += usage;
      case CompactionRecord(:final details):
        final raw = details?['usage'];
        if (raw is Map<String, Object?>) {
          final usage = Usage.fromJson(raw);
          final model = details?['summaryModel'];
          calls.add((usage: usage, model: model is String ? model : null));
          total += usage;
        }
      default:
        break;
    }
  }

  // Ходы: путь до листа; начало хода — слова пользователя без `steer`.
  final turns = <UsageLedgerTurn>[];
  _TurnBuilder? open;
  void close() {
    if (open != null && open!.steps.isNotEmpty) {
      turns.add(open!.build());
    }
    open = null;
  }

  for (final r in pathToLeaf(snapshot)) {
    if (r is MessageRecord &&
        r.message is UserMessage &&
        isUserWords(r) &&
        r.origin != RecordOrigin.steer.wire) {
      close();
      open = _TurnBuilder(r, _titleOf(r));
      continue;
    }
    final turn = open;
    if (turn == null) {
      continue;
    }
    if (r is MessageRecord && _isStep(r)) {
      turn.addStep(r);
    } else if (r is SubagentRecord && counted(r)) {
      turn.subagents.add(r.usage!);
    }
  }
  close();

  final models = [
    for (final key in byModel.keys.toList()..sort())
      UsageLedgerModel(
        model: key,
        steps: byModel[key]!.steps,
        usage: byModel[key]!.usage,
      ),
  ];
  final summaryModels = {
    for (final c in calls)
      if (c.model != null) c.model!,
  }.toList()..sort();
  return UsageLedger(
    sessionId: snapshot.header.id.value,
    records: records.length,
    lastRecordId: records.isEmpty ? null : records.last.id,
    steps: steps,
    total: total,
    byModel: models,
    turns: turns,
    subagents: runs.isEmpty
        ? null
        : UsageLedgerGroup(count: runs.length, usage: _sum(runs)),
    summaries: calls.isEmpty
        ? null
        : UsageLedgerGroup(
            count: calls.length,
            usage: _sum([for (final c in calls) c.usage]),
            models: summaryModels,
          ),
    subagentRuns: runs,
    summaryCalls: calls,
  );
}

/// Шаг — ответ модели, кроме заметки цикла (D1 п. 1).
bool _isStep(MessageRecord r) =>
    r.message is AssistantMessage && r.origin != RecordOrigin.loopNote.wire;

String _modelKey(AssistantMessage m) => '${m.model.provider}/${m.model.id}';

Usage _sum(Iterable<Usage> all) => all.fold(Usage.zero, (a, b) => a + b);

/// Подпись хода: первые 64 руны; у развёрнутой команды — её исходный текст
/// (D1 п. 3, S-16). Пробелы по краям убираются, пробелы и переводы строк
/// схлопываются в один пробел — как в `sessionTitleFrom`; потом берутся первые
/// 64 руны.
String _titleOf(MessageRecord r) {
  final command = r.command;
  final raw = command != null && command.showsTyped
      ? command.displayText
      : r.message.content
            .whereType<TextContent>()
            .map((b) => b.text)
            .join('\n');
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  return String.fromCharCodes(text.runes.take(64));
}

final class _TurnBuilder {
  _TurnBuilder(this.start, this.title);

  final MessageRecord start;
  final String title;
  final steps = <UsageLedgerStep>[];
  final subagents = <Usage>[];

  void addStep(MessageRecord r) {
    final answer = r.message as AssistantMessage;
    final u = answer.usage;
    steps.add(
      UsageLedgerStep(
        recordId: r.id,
        model: _modelKey(answer),
        usage: u,
        // D1 п. 2: не `error` и все четыре счётчика нулевые.
        noUsage:
            answer.stopReason != StopReason.error &&
            u.input == 0 &&
            u.output == 0 &&
            u.cacheRead == 0 &&
            u.cacheWrite == 0,
        toolCallIds: [for (final c in answer.toolCalls) c.id],
      ),
    );
  }

  UsageLedgerTurn build() => UsageLedgerTurn(
    recordId: start.id,
    title: title,
    usage: _sum([for (final s in steps) s.usage, ...subagents]),
    steps: steps,
    subagents: subagents.isEmpty
        ? null
        : UsageLedgerGroup(count: subagents.length, usage: _sum(subagents)),
  );
}

/// Модели журнала без цены по каталогу сессии (D2, Q4): у модели
/// `cost == null` или её нет в каталоге. Значения — `<provider>/<id>`.
/// Включает и модели суммаризатора: их цена нужна печати `/usage` (D2).
Set<String> modelsWithoutPrice(UsageLedger ledger, ModelCatalog catalog) => {
  for (final model in [
    for (final m in ledger.byModel) m.model,
    ...?ledger.summaries?.models,
  ])
    if (catalog.resolve(ModelId(model))?.cost == null) model,
};
