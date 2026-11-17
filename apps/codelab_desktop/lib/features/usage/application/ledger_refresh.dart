import 'package:codelab_client_core/codelab_client_core.dart'
    show
        SessionStatusView,
        UsageLedgerIdle,
        UsageLedgerLoaded,
        UsageLedgerState;

/// Нужен ли автоматический запрос журнала usage (design.md change
/// `add-desktop-usage-pane`, D3, Q4).
///
/// Почему чистая функция: правило «когда обновлять» — политика application,
/// а виджеты и kit его не знают (`add-usage-ledger`, D10: «когда обновлять,
/// решает хост»). Владелец вызова — `ActiveSessionCubit`.
///
/// Для чего: не более одного запроса на значение [lastSeq]; журнал, который
/// не догнал снимки, не даёт цикла запросов. `failed`, `loading` и
/// `unavailable` автоматически не повторяются — только действие пользователя.
///
/// Как использовать: [requestedForSeq] — значение `usage.lastSeq`, для
/// которого автоматический запрос уже уходил (`null` — не уходил). Опроса по
/// таймеру нет: функцию вызывают на показ панели и на новую ревизию сессии.
bool ledgerRefreshNeeded({
  required bool paneShown,
  required SessionStatusView status,
  required UsageLedgerState ledger,
  required int lastSeq,
  int? requestedForSeq,
}) {
  if (!paneShown) {
    return false;
  }
  // Во время хода журнал не перезапрашивают: на большой сессии он весит до
  // мегабайт (R4 change `add-usage-ledger`).
  if (status == SessionStatusView.running ||
      status == SessionStatusView.cancelling) {
    return false;
  }
  if (requestedForSeq == lastSeq) {
    return false;
  }
  return switch (ledger) {
    UsageLedgerIdle() => true,
    UsageLedgerLoaded(:final view) => view.seq < lastSeq,
    _ => false,
  };
}
