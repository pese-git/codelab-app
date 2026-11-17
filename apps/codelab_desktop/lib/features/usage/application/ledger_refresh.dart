import 'package:codelab_client_core/codelab_client_core.dart'
    show SessionStatusView, UsageLedgerState;

/// Нужен ли автоматический запрос журнала usage (design.md change
/// `add-desktop-usage-pane`, D3, Q4).
///
/// Почему чистая функция: правило «когда обновлять» — политика application,
/// а виджеты и kit его не знают (`add-usage-ledger`, D10: «когда обновлять,
/// решает хост»). Владелец вызова — `ActiveSessionCubit`.
///
/// Для чего: не более одного запроса на значение [lastSeq]; журнал, который
/// не догнал снимки, не даёт цикла запросов.
///
/// Как использовать: [requestedForSeq] — значение `usage.lastSeq`, для
/// которого автоматический запрос уже уходил (`null` — не уходил).
///
/// Заглушка задачи 1.4.
bool ledgerRefreshNeeded({
  required bool paneShown,
  required SessionStatusView status,
  required UsageLedgerState ledger,
  required int lastSeq,
  int? requestedForSeq,
}) => throw UnimplementedError();
