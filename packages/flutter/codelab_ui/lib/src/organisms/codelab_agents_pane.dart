import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_transcript_row.dart';

/// Состояние строки панели Agents (D33, D49 Т10). Порядок значений — порядок
/// счётчиков в заголовке: `running · waiting for approval · done · failed ·
/// cancelled`.
enum CodeLabAgentRowState {
  running,
  waitingForApproval,
  done,
  failed,
  cancelled,
}

/// Метка пункта списка `#N` у строки субагента и подсказка к ней (D49 Т6).
final class CodeLabAgentItemRef {
  const CodeLabAgentItemRef({required this.label, this.hint});

  /// Готовая метка, например `#2`.
  final String label;

  /// Заголовок пункта плана; `null` — пункта нет в плане, подсказки нет.
  final String? hint;
}

/// Строка панели Agents: данные уже отформатированы app (D49 Т9, Т10).
///
/// Поля без данных — `null`/пусто — не рисуются, без заглушек. [id] —
/// `toolCallId` вызова `agent`: по нему ключи `agents-row-<id>` и действия.
final class CodeLabAgentRow {
  const CodeLabAgentRow({
    required this.id,
    required this.depth,
    required this.type,
    required this.title,
    required this.state,
    this.time,
    this.calls,
    this.tokens,
    this.lastAction,
    this.items = const [],
  });

  final String id;

  /// Глубина: 1 — строка верхнего уровня; отступ растёт с глубиной.
  final int depth;
  final String type;
  final String title;
  final CodeLabAgentRowState state;
  final String? time;
  final String? calls;
  final String? tokens;
  final String? lastAction;
  final List<CodeLabAgentItemRef> items;
}

/// ЗАГЛУШКА красных тестов 5b.1: рисует пустое. Реализация — задача 5b.3.
///
/// Панель Agents v1: заголовок «Subagents» со счётчиками [counts], строки
/// [rows], дерево шагов [steps] выбранной строки [selectedId] (D33, D49 Т10).
class CodeLabAgentsPane extends StatelessWidget {
  const CodeLabAgentsPane({
    required this.rows,
    this.counts = const {},
    this.selectedId,
    this.steps = const [],
    this.onSelect,
    this.onGoToApproval,
    this.onShowInTranscript,
    super.key,
  });

  final List<CodeLabAgentRow> rows;
  final Map<CodeLabAgentRowState, int> counts;
  final String? selectedId;

  /// Дерево шагов выбранной строки: вложенные [CodeLabToolCallRow.children]
  /// показываются раскрытыми целиком.
  final List<CodeLabTranscriptRow> steps;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onGoToApproval;
  final ValueChanged<String>? onShowInTranscript;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
