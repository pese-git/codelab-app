import 'package:codelab_client_core/codelab_client_core.dart'
    show ToolCallItem, ToolRowFormatter, TranscriptItem, UsageLedgerStep;

/// Подписи шагов журнала по транскрипту клиента (design.md change
/// `add-desktop-usage-pane`, D4, Q6).
///
/// Почему здесь: журнал агента не несёт заголовков вызовов (D1 п. 4 change
/// `add-usage-ledger`), а лента уже знает вызовы по `toolCallId`; подпись
/// строится по тому же правилу, что строка ленты (`ToolRowFormatter`), чтобы
/// одно действие не называлось двумя способами.
///
/// Как использовать: `UsageStepLabeler(view.transcript, cwd: cwd)` строится
/// один раз на ревизию `SessionView` (индекс `toolCallId → item`), затем
/// `labelOf(step)` на каждый шаг. Ищутся только вызовы корневого уровня:
/// вызовы потомков шагу корня не принадлежат.
final class UsageStepLabeler {
  UsageStepLabeler(List<TranscriptItem> transcript, {required String cwd})
    : _cwd = cwd {
    for (final item in transcript) {
      if (item is ToolCallItem) {
        _calls[item.toolCallId.value] = item;
      }
    }
  }

  final String _cwd;
  final Map<String, ToolCallItem> _calls = {};

  /// `<label> <detail>[ +N]`, `reply` или `N tool calls` (D4).
  String labelOf(UsageLedgerStep step) {
    final ids = step.toolCallIds;
    if (ids.isEmpty) {
      return 'reply';
    }
    for (final id in ids) {
      final item = _calls[id];
      if (item == null) {
        continue;
      }
      final row = ToolRowFormatter.format(item, cwd: _cwd);
      final text = '${row.label} ${row.detail}'.trim();
      return ids.length > 1 ? '$text +${ids.length - 1}' : text;
    }
    return '${ids.length} tool calls';
  }
}
