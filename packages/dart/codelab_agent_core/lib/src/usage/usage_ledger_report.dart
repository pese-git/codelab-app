/// Отчёт журнала usage для показа и операция сессии (design.md change
/// `add-usage-ledger`, D2, D3).
///
/// ЗАГЛУШКА красной итерации (задачи 1.2, 1.4): сигнатуры из design.md, тела —
/// `UnimplementedError`. Реализация — задача 1.7: операция становится членом
/// `AgentSession` (сейчас — расширение, чтобы не ломать реализации интерфейса
/// в тестах `codelab_agent_acp`).
library;

import '../runtime/agent_session.dart';
import 'usage_ledger.dart';

/// Состояние файла `usage.json` в отчёте (D2).
enum UsageLedgerFileState {
  /// Файл свежий, пересчёта и записи не было.
  upToDate,

  /// Свёртка пересчитана и записана; причина — в `reason`.
  rebuilt,

  /// Порта нет: свёртка только в памяти.
  inMemory,

  /// Свёртка пересчитана, запись не удалась.
  notSaved,
}

/// Почему файл пересчитан (D3).
enum UsageLedgerRebuildReason { missing, invalid, stale, explicit }

/// Журнал и состояние его файла плюс модели без цены (D2).
final class UsageLedgerReport {
  const UsageLedgerReport({
    required this.ledger,
    required this.state,
    this.reason,
    this.saveError,
    this.noPriceModels = const {},
  });

  final UsageLedger ledger;
  final UsageLedgerFileState state;

  /// `null` у `upToDate` и `inMemory`.
  final UsageLedgerRebuildReason? reason;

  /// Причина ОС на английском; только у `notSaved`.
  final String? saveError;

  /// Модели без цены по каталогу сессии на момент построения (Q4).
  final Set<String> noPriceModels;
}

/// Операции отчёта сессии (D3).
extension UsageLedgerOnSession on AgentSession {
  /// Отчёт: свежий файл — как есть; иначе пересчёт и запись; [rebuild] —
  /// пересчёт всегда (`explicit`). Не больше одной операции с записью на
  /// сессию одновременно.
  Future<UsageLedgerReport> usageLedger({bool rebuild = false}) =>
      throw UnimplementedError('usage ledger: task 1.7');

  /// Свёртка в памяти без файла: засев адаптера на `session/load` (D8).
  Future<UsageLedgerReport> usageLedgerInMemory() =>
      throw UnimplementedError('usage ledger: task 1.7');
}
