/// Журнал usage сессии: модель и свёртка записей (design.md change
/// `add-usage-ledger`, D1, D2; `agent-core/12-observability-and-errors.md`
/// §12.6.1; OBS-10).
///
/// ЗАГЛУШКА красной итерации (задача 1.1): сигнатуры из design.md, тела —
/// `UnimplementedError`. Реализация — задача 1.7.
///
/// Почему в ядре: `/usage` и ACP-адаптер строят одну и ту же свёртку, и
/// правило шага (`noUsage`, `loop_note`, `steer`) должно жить в одном месте.
///
/// Как использовать: `buildUsageLedger(snapshot)` — чистая функция записей;
/// [UsageLedger.serialize] даёт побайтово воспроизводимый `usage.json` v1.
library;

import '../llm/model_catalog.dart';
import '../llm/usage.dart';
import '../session/session_store.dart';

/// Шаг: ответ модели (D1 п. 1).
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

/// Счётчик с суммой usage: субагенты (`runs`) и суммаризатор (`count`).
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

/// Ход: от слов пользователя до следующего хода (D1 п. 3).
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
  });

  final String sessionId;

  /// `source.records`: число разобранных записей.
  final int records;

  /// `source.lastRecordId`; `null` у пустого журнала.
  final String? lastRecordId;

  /// Число шагов всех ходов и файла.
  final int steps;
  final Usage total;
  final List<UsageLedgerModel> byModel;
  final List<UsageLedgerTurn> turns;
  final UsageLedgerGroup? subagents;
  final UsageLedgerGroup? summaries;

  /// `usage.json` формата v1: ключи в порядке формата, без пробелов вне
  /// строк, `\n` в конце; стоимость округлена до 10⁻⁶ (D3).
  String serialize() => throw UnimplementedError('usage ledger: task 1.7');
}

/// Чистая свёртка записей журнала (D1). Не читает файлы и часы.
UsageLedger buildUsageLedger(SessionSnapshot snapshot) =>
    throw UnimplementedError('usage ledger: task 1.7');

/// Модели журнала без цены по каталогу сессии (D2, Q4): у модели
/// `cost == null` или её нет в каталоге. Значения — `<provider>/<id>`.
Set<String> modelsWithoutPrice(UsageLedger ledger, ModelCatalog catalog) =>
    throw UnimplementedError('usage ledger: task 1.7');
