import 'package:codelab_client_core/codelab_client_core.dart'
    show SubagentRowState, SubagentRowView;
import 'package:codelab_ui/codelab_ui.dart';

/// Цель показа в ленте: строка верхнего уровня, цель внутри неё и строки пути,
/// которые нужно раскрыть (design.md change `add-subagents-and-tasks`, D49 Т7).
final class AgentsShowTarget {
  const AgentsShowTarget({
    required this.rowId,
    required this.targetId,
    this.expand = const [],
  });

  /// Id строки ленты верхнего уровня (`tool-N`).
  final String rowId;

  /// Id цели внутри строки; равен [rowId], если цель — сама строка.
  final String targetId;

  /// Id строк пути, которые раскрываются тем же обновлением, что и запрос.
  final List<String> expand;
}

/// Данные панели Agents сессии в фокусе: строки kit и то, что нужно, чтобы
/// превратить их в строки панели и переходы к ленте.
///
/// Почему: строки считает kit (`SessionView.subagents`, D33), но app должен
/// связать строку kit со строкой ленты: id элемента транскрипта (`path`) не
/// равен id строки ленты верхнего уровня (`tool-N`), а время работающей
/// строки зависит от часов виджета и потому в данные не входит.
///
/// Для чего: неизменяемый снимок, который `ActiveSessionCubit` собирает при
/// каждой публикации `SessionView`; сам ничего не форматирует. Тексты и
/// время строит маппер (`agentRowsOf`), раскрытие и прокрутку ленты решает
/// `TranscriptViewCubit` по [AgentsShowTarget].
///
/// Как использовать: читать из `CodeLabShellState.agents`; пуст, пока у
/// сессии нет ни одной строки субагента (панель недоступна, D49 Т11).
final class AgentsPaneData {
  const AgentsPaneData({
    this.rows = const [],
    this.planTitles = const {},
    this.busy = false,
    this.topRowIds = const {},
    this.pendingApprovals = const {},
    this.counts = const {},
  });

  static const empty = AgentsPaneData();

  /// Строки kit в порядке обхода: глубина и путь — в самих строках.
  final List<SubagentRowView> rows;

  /// Заголовки пунктов плана по id пункта — подсказки меток `#N`.
  final Map<String, String> planTitles;

  /// Сессия занята (`running` или `cancelling`): время работающих строк
  /// показывается и растёт только тогда (D50 п. 2).
  final bool busy;

  /// Id элемента транскрипта вызова верхнего уровня → id его строки в ленте.
  final Map<String, String> topRowIds;

  /// Id элемента транскрипта вызова → id его ожидающего одобрения. Нужен
  /// шагам дерева: у них своего `approvalId` в строке ленты нет.
  final Map<String, String> pendingApprovals;

  /// Число строк по состояниям — `SessionView.subagentCount` kit (счётчики
  /// заголовка); app их не пересчитывает по строкам UI.
  final Map<SubagentRowState, int> counts;

  bool get isEmpty => rows.isEmpty;

  /// Есть строка, чьё время растёт: работает или ждёт одобрения.
  bool get hasRunning => rows.any(
    (row) =>
        row.state == SubagentRowState.running ||
        row.state == SubagentRowState.awaitingApproval,
  );

  /// Строка по `toolCallId` вызова `agent`; `null` — такой строки нет.
  SubagentRowView? rowOf(String id) {
    for (final row in rows) {
      if (row.toolCallId.value == id) {
        return row;
      }
    }
    return null;
  }

  /// Дерево шагов строки [id]: дети её строки в ленте (`children`), найденной
  /// по пути элементов от строки верхнего уровня. Пусто, если строки или её
  /// ленты нет (выбор устарел).
  List<CodeLabTranscriptRow> stepsOf(
    String id,
    List<CodeLabTranscriptRow> transcriptRows,
  ) {
    final row = rowOf(id);
    final topId = row == null ? null : topRowIds[row.path.first];
    if (row == null || topId == null) {
      return const [];
    }
    CodeLabToolCallRow? current = _toolRowById(transcriptRows, topId);
    for (final step in row.path.skip(1)) {
      if (current == null) {
        break;
      }
      current = _toolRowById(current.children, step);
    }
    return current?.children ?? const [];
  }

  /// Куда вести «Show in transcript» строки [id]: строка верхнего уровня, а у
  /// вложенной — её собственная строка `agent` и раскрытый путь до неё (D49
  /// Т7). `null` — строки нет.
  AgentsShowTarget? showTargetOf(String id) {
    final row = rowOf(id);
    final topId = row == null ? null : topRowIds[row.path.first];
    if (row == null || topId == null) {
      return null;
    }
    if (row.path.length == 1) {
      return AgentsShowTarget(rowId: topId, targetId: topId);
    }
    return AgentsShowTarget(
      rowId: topId,
      targetId: row.path.last,
      // Раскрывается каждая строка пути, кроме самой цели (D33).
      expand: [topId, ...row.path.sublist(1, row.path.length - 1)],
    );
  }

  /// Куда вести «Go to approval» строки [id] (`toolCallId`): к блоку с её
  /// ожидающим одобрением. `null` — у строки нет ожидающего одобрения или
  /// блока уже нет в ленте. Блок потомка стоит под строкой корня
  /// (`childApprovals`), а одобрение запуска самой строки — в её собственной
  /// строке ленты; поэтому цель ищется по готовым строкам [transcriptRows].
  AgentsShowTarget? approvalTargetOf(
    String id,
    List<CodeLabTranscriptRow> transcriptRows,
  ) => _approvalTarget(rowOf(id)?.approvalId?.value, transcriptRows);

  /// То же для шага дерева [id] (id элемента ленты): у шага своего
  /// `approvalId` в строке нет, он берётся только из [pendingApprovals].
  AgentsShowTarget? stepApprovalTargetOf(
    String id,
    List<CodeLabTranscriptRow> transcriptRows,
  ) => _approvalTarget(pendingApprovals[id], transcriptRows);

  static AgentsShowTarget? _approvalTarget(
    String? approvalId,
    List<CodeLabTranscriptRow> transcriptRows,
  ) {
    if (approvalId == null) {
      return null;
    }
    for (final row in transcriptRows) {
      if (row is! CodeLabToolCallRow) {
        continue;
      }
      if (_holdsChildApproval(row, approvalId)) {
        return AgentsShowTarget(rowId: row.id, targetId: approvalId);
      }
      if (row.approval?.targetId == approvalId) {
        return AgentsShowTarget(rowId: row.id, targetId: row.id);
      }
    }
    return null;
  }

  static bool _holdsChildApproval(CodeLabToolCallRow row, String approvalId) =>
      row.childApprovals.any((approval) => approval.targetId == approvalId) ||
      row.children.whereType<CodeLabToolCallRow>().any(
        (child) => _holdsChildApproval(child, approvalId),
      );

  static CodeLabToolCallRow? _toolRowById(
    List<CodeLabTranscriptRow> rows,
    String id,
  ) {
    for (final row in rows) {
      if (row is CodeLabToolCallRow && row.id == id) {
        return row;
      }
    }
    return null;
  }
}
