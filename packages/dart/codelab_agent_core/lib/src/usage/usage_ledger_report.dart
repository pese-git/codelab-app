/// Отчёт журнала usage для показа (design.md change `add-usage-ledger`, D2,
/// D3).
///
/// Почему отдельный тип: журнал (`UsageLedger`) зависит только от записей, а
/// показ добавляет состояние файла и цену по каталогу в момент показа (Q4).
/// Операции — `AgentSession.usageLedger` и `usageLedgerInMemory`.
library;

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
///
/// Почему не в самом журнале: файл зависит только от записей (OBS-10), а
/// состояние файла и цена по каталогу меняются независимо от них (Q4).
/// Для чего: единый результат `/usage` и запроса журнала адаптера. Как
/// использовать: `session.usageLedger()`; [reason] есть у `rebuilt` и
/// `notSaved`, [saveError] — только у `notSaved`, [noPriceModels] — модели
/// `<provider>/<id>` без цен в каталоге сессии.
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
