import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show ToolKind;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ToolCallItem, ToolRowFormatter, TranscriptItem, UsageLedgerStep;

/// Название шага журнала в виде значения: текст собирает presentation по
/// каталогу, а CSV берёт [englishText] (`add-desktop-localization`, D5 п. 4:
/// `features/usage/application` остаётся без языка и без Flutter).
///
/// Почему закрытая иерархия: у названия три источника — шаг без вызовов,
/// вызов, найденный в ленте, и вызовы, которых в ленте нет; presentation
/// обязан разобрать каждый.
sealed class UsageStepTitle {
  const UsageStepTitle();

  /// Английский текст для CSV и диагностики: формат файла не зависит от языка
  /// интерфейса (spec agent-workbench-ui «Панель Usage», D5 change
  /// `add-desktop-usage-pane`).
  String get englishText;
}

/// Шаг без вызовов инструментов: ответ модели.
final class UsageStepReply extends UsageStepTitle {
  const UsageStepReply();

  @override
  String get englishText => 'reply';

  @override
  bool operator ==(Object other) => other is UsageStepReply;

  @override
  int get hashCode => (UsageStepReply).hashCode;
}

/// Вызовы шага есть, но ни один не найден в ленте: называем их число.
final class UsageStepToolCalls extends UsageStepTitle {
  const UsageStepToolCalls(this.count);

  final int count;

  @override
  String get englishText => '$count tool calls';

  @override
  bool operator ==(Object other) =>
      other is UsageStepToolCalls && other.count == count;

  @override
  int get hashCode => Object.hash(UsageStepToolCalls, count);
}

/// Первый найденный вызов шага: [label] и [detail] строит ядро клиента по
/// правилу строки ленты, [kind] нужен presentation, чтобы назвать вид вызова
/// так же, как строка ленты; [more] — сколько ещё вызовов у шага.
final class UsageStepCall extends UsageStepTitle {
  const UsageStepCall({
    required this.kind,
    required this.label,
    required this.detail,
    this.more = 0,
  });

  final ToolKind? kind;
  final String label;
  final String detail;
  final int more;

  @override
  String get englishText {
    final text = '$label $detail'.trim();
    return more > 0 ? '$text +$more' : text;
  }

  @override
  bool operator ==(Object other) =>
      other is UsageStepCall &&
      other.kind == kind &&
      other.label == label &&
      other.detail == detail &&
      other.more == more;

  @override
  int get hashCode => Object.hash(UsageStepCall, kind, label, detail, more);
}

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

  /// Вызов с деталью и `+N`, ответ модели или число вызовов (D4). Английский
  /// текст прежнего вида — [UsageStepTitle.englishText].
  UsageStepTitle labelOf(UsageLedgerStep step) {
    final ids = step.toolCallIds;
    if (ids.isEmpty) {
      return const UsageStepReply();
    }
    for (final id in ids) {
      final item = _calls[id];
      if (item == null) {
        continue;
      }
      final row = ToolRowFormatter.format(item, cwd: _cwd);
      return UsageStepCall(
        kind: item.details?.kind,
        label: row.label,
        detail: row.detail,
        more: ids.length - 1,
      );
    }
    return UsageStepToolCalls(ids.length);
  }
}
