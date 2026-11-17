import 'package:codelab_client_core/codelab_client_core.dart'
    show TranscriptItem, UsageLedgerStep;

/// Подписи шагов журнала по транскрипту клиента (design.md change
/// `add-desktop-usage-pane`, D4, Q6).
///
/// Почему здесь: журнал агента не несёт заголовков вызовов (D1 п. 4 change
/// `add-usage-ledger`), а лента уже знает вызовы по `toolCallId`.
///
/// Как использовать: `UsageStepLabeler(view.transcript, cwd: cwd)` строится
/// один раз на ревизию `SessionView` (индекс `toolCallId → item`), затем
/// `labelOf(step)` на каждый шаг.
///
/// Заглушка задачи 1.4 (красные тесты `usage_step_label_test.dart`).
final class UsageStepLabeler {
  UsageStepLabeler(List<TranscriptItem> transcript, {required String cwd});

  /// `<label> <detail>[ +N]`, `reply` или `N tool calls` (D4).
  String labelOf(UsageLedgerStep step) => throw UnimplementedError();
}
