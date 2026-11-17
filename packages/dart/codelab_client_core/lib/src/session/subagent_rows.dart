/// Строки панели Agents v1: проекция субагентов сессии (`SessionView.subagents`).
///
/// Почему: панель Agents — навигация по уже показанным данным, а считать
/// строки (состояние, время, счётчики, одобрение, пункты `#N`) должен kit,
/// чтобы app и CLI не расходились (design.md change
/// `add-subagents-and-tasks`, D33, D49 Т2–Т6, D50; spec acp-client-kit
/// «Список субагентов сессии»; `AGENTS.md` §8).
///
/// Для чего: [SubagentRowView] — строка, [subagentRowsOf] — обход транскрипта
/// (функция дополняет [SubagentRowMemory], поэтому не чистая),
/// [SubagentRowMemory] — память сессии, которой нет в самом транскрипте (первое появление вызова и последний итог).
///
/// Как использовать: `_SessionHandle` держит по одной [SubagentRowMemory] на
/// сессию и зовёт [subagentRowsOf] при каждой публикации `SessionView`;
/// хосты только читают `SessionView.subagents`. Заголовок вызова, строка
/// прогресса и отчёт не разбираются (D33, `AGENTS.md` §9).
library;

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

import '../transcript/subagent_views.dart';
import '../transcript/transcript_item.dart';
import 'session_views.dart';

/// Состояние строки панели (D33): `running`, `awaitingApproval` — поверх
/// нетерминального, `completed`, `failed`, `cancelled` — по статусу вызова.
enum SubagentRowState {
  running,
  awaitingApproval,
  completed,
  failed,
  cancelled,
}

/// Строка панели Agents: один вызов `agent` с признаком `subagentCall`.
///
/// Почему: панель — навигация по уже показанным данным, и строки должен
/// считать kit, а не app (D33, `AGENTS.md` §8); поля — таблица D33.
///
/// Как использовать: читать из `SessionView.subagents`; хост только
/// отображает. Поля без данных — `null`/пусто, а не отказ (терпимый разбор).
final class SubagentRowView {
  const SubagentRowView({
    required this.toolCallId,
    required this.type,
    required this.title,
    required this.state,
    required this.depth,
    required this.path,
    this.subagentId,
    this.startedAt,
    this.summary,
    this.toolCalls,
    this.lastAction,
    this.taskIds = const [],
    this.approvalId,
  });

  /// Ключ строки — `toolCallId` вызова на проводе.
  final ToolCallId toolCallId;

  /// Id субагента; `null` — реплей отклонённого вызова (D36, Т15).
  final String? subagentId;

  /// Тип: `explore`, `review` и т. д.
  final String type;

  /// `rawInput.description`, а без него — `title` вызова как есть.
  final String title;

  final SubagentRowState state;

  /// 1 — вызов без родителя или с неизвестным родителем.
  final int depth;

  /// Id элементов транскрипта от строки верхнего уровня до этой строки
  /// (`TranscriptItem.id`, D49 Т2): по нему app раскрывает путь и
  /// прокручивает ленту.
  final List<String> path;

  /// Момент первого появления вызова по часам `ClientWorkspace` (D49 Т3);
  /// заполнен у всех строк, но у терминальной строки длительность хосты берут
  /// из [summary], а не из разности времён.
  final DateTime? startedAt;

  /// Итог (D24): у терминальной строки; токены и длительность — только отсюда.
  final SubagentSummaryView? summary;

  /// Терминальная — `summary.toolCalls`; работающая — `subtreeCalls`;
  /// без дерева и без итога — `null`.
  final int? toolCalls;

  /// Работающая — `title` последнего вызова поддерева; `failed` — `failure`.
  final String? lastAction;

  /// Id пунктов плана: сначала `owner` = id субагента, затем `rawInput.task`,
  /// без повторов (D49 Т6).
  final List<String> taskIds;

  /// Ожидающее одобрение строки (D33, D50 п. 3); при нескольких — самое раннее.
  final ApprovalRequestId? approvalId;

  @override
  bool operator ==(Object other) =>
      other is SubagentRowView &&
      other.toolCallId == toolCallId &&
      other.subagentId == subagentId &&
      other.type == type &&
      other.title == title &&
      other.state == state &&
      other.depth == depth &&
      other.path.join('\u0000') == path.join('\u0000') &&
      other.startedAt == startedAt &&
      other.summary == summary &&
      other.toolCalls == toolCalls &&
      other.lastAction == lastAction &&
      other.taskIds.join('\u0000') == taskIds.join('\u0000') &&
      other.approvalId == approvalId;

  @override
  int get hashCode => Object.hash(
    toolCallId,
    subagentId,
    type,
    title,
    state,
    depth,
    Object.hashAll(path),
    startedAt,
    summary,
    toolCalls,
    lastAction,
    Object.hashAll(taskIds),
    approvalId,
  );

  @override
  String toString() => 'SubagentRowView($toolCallId, $type, $state)';
}

/// Память строк одной сессии: то, чего нельзя вывести из транскрипта.
///
/// Почему: kit не вызывает `DateTime.now` в проекции, а `ToolCallRecord.
/// startedAt` ядро клиента не заполняет (D49 Т3); слияние кадров ядра
/// возвращает статус позднему неитоговому кадру (D49 Т4, до F.1).
///
/// Для чего: [firstSeen] — момент первого появления вызова `agent` по часам
/// kit (повтор кадра и реплей его не сдвигают); [finalStatus] — последний
/// итоговый статус: защёлка только строки списка (D50 п. 1), а
/// `ToolCallView.status` ленты не меняется. F.1 сделает итог окончательным
/// для всех вызовов и удалит защёлку.
///
/// Как использовать: один объект на `_SessionHandle`; [subagentRowsOf]
/// дополняет его идемпотентно.
final class SubagentRowMemory {
  final Map<ToolCallId, DateTime> firstSeen = {};
  final Map<ToolCallId, ToolCallStatusView> finalStatus = {};
}

/// Строки панели Agents по [transcript] сессии [session].
///
/// Обход в глубину по `ToolCallItem.children` в порядке прихода; строка — у
/// каждого вызова с признаком `subagentCall` (D28), любой глубины. Повтор
/// `toolCallId` (ошибка агента) даёт только первую строку, как в
/// `buildToolCallTree`. Глубина — число строк-предков плюс 1; вызов с
/// неизвестным родителем уже стоит на верхнем уровне и получает 1.
///
/// Одобрение (D33, D49 Т5, D50 п. 3): запрос потомка помечает строку с
/// `subagent.id`, а без такой строки — строку верхнего уровня с
/// `toolCallId == subagent.parentToolCallId`; кроме того, запрос с
/// `toolCall.id` строки (запуск самого `agent`) помечает и эту строку.
/// `approvalId` — самое раннее ожидающее одобрение строки.
List<SubagentRowView> subagentRowsOf({
  required AcpSession session,
  required List<TranscriptItem> transcript,
  required List<PlanEntryView> plan,
  required SubagentRowMemory memory,
  required DateTime Function() clock,
}) {
  final pending = _pendingApprovalsInOrder(session);

  final rows = <SubagentRowView>[];
  final seen = <ToolCallId>{};
  final bySubagent = <String, ToolCallId>{};

  // Первый проход — строки без одобрений: нужны id субагентов для выбора
  // строки по `subagent.id`.
  final drafts = <_Draft>[];
  void walk(List<TranscriptItem> items, List<String> path, int depth) {
    for (final item in items) {
      if (item is! ToolCallItem) {
        continue;
      }
      final call = item.details?.subagentCall;
      final isRow = call != null && seen.add(item.toolCallId);
      if (isRow) {
        final subagentId = call.id;
        if (subagentId != null) {
          bySubagent.putIfAbsent(subagentId, () => item.toolCallId);
        }
        drafts.add(_Draft(item, call, [...path, item.id], depth));
      }
      walk(item.children, [...path, item.id], isRow ? depth + 1 : depth);
    }
  }

  walk(transcript, const [], 1);

  final topLevel = {
    for (final draft in drafts)
      if (draft.depth == 1) draft.item.toolCallId,
  };
  final approvalOf = <ToolCallId, ApprovalRequestId>{};
  for (final approval in pending) {
    final targets = <ToolCallId>{};
    final requester = parseSubagentRequester(approval.subagentRequester);
    if (requester != null) {
      final byId = bySubagent[requester.id];
      final byParent = ToolCallId(requester.parentToolCallId);
      if (byId != null) {
        targets.add(byId);
      } else if (topLevel.contains(byParent)) {
        targets.add(byParent);
      }
    }
    if (seen.contains(approval.toolCall.id)) {
      targets.add(approval.toolCall.id);
    }
    for (final target in targets) {
      approvalOf.putIfAbsent(target, () => approval.id);
    }
  }

  for (final draft in drafts) {
    final item = draft.item;
    final details = item.details!;
    final id = item.toolCallId;
    final started = memory.firstSeen.putIfAbsent(id, clock);

    final current = details.status;
    final ToolCallStatusView status;
    if (_isFinal(current)) {
      memory.finalStatus[id] = current;
      status = current;
    } else {
      status = memory.finalStatus[id] ?? current;
    }
    final terminal = _isFinal(status);
    final approvalId = terminal ? null : approvalOf[id];
    final state = switch (status) {
      ToolCallStatusView.succeeded => SubagentRowState.completed,
      ToolCallStatusView.failed => SubagentRowState.failed,
      ToolCallStatusView.cancelled => SubagentRowState.cancelled,
      ToolCallStatusView.queued || ToolCallStatusView.running =>
        approvalId != null
            ? SubagentRowState.awaitingApproval
            : SubagentRowState.running,
    };
    final summary = details.subagentSummary;
    final failure = details.subagentFailure;
    final description = details.rawInput?['description'];
    final task = details.rawInput?['task'];
    final subagentId = draft.call.id;

    rows.add(
      SubagentRowView(
        toolCallId: id,
        subagentId: subagentId,
        type: draft.call.type,
        title: description is String && description.isNotEmpty
            ? description
            : item.title,
        state: state,
        depth: draft.depth,
        path: List.unmodifiable(draft.path),
        startedAt: started,
        summary: terminal ? summary : null,
        toolCalls: terminal
            ? summary?.toolCalls
            : (item.subtreeCalls > 0 ? item.subtreeCalls : null),
        lastAction: switch (state) {
          SubagentRowState.failed => failure,
          SubagentRowState.running || SubagentRowState.awaitingApproval =>
            item.tail.calls.lastOrNull?.title,
          _ => null,
        },
        taskIds: List.unmodifiable({
          if (subagentId != null)
            for (final entry in plan)
              if (entry.owner == subagentId && entry.taskId != null)
                entry.taskId!,
          if (task is String && task.isNotEmpty) task,
        }),
        approvalId: approvalId,
      ),
    );
  }
  return List.unmodifiable(rows);
}

bool _isFinal(ToolCallStatusView status) =>
    status == ToolCallStatusView.succeeded ||
    status == ToolCallStatusView.failed ||
    status == ToolCallStatusView.cancelled;

/// Ожидающие одобрения сессии: ходы по порядку, внутри хода — по
/// `requestedAt` (как фокус клавиш одобрения, Decision 6 `embed-approval-in-
/// thread`); без времени порядок прихода сохраняется.
List<ApprovalRequest> _pendingApprovalsInOrder(AcpSession session) {
  final result = <ApprovalRequest>[];
  for (final turn in session.turns) {
    final pending = [
      for (final approval in turn.approvals.values)
        if (approval.status == ApprovalStatus.pending) approval,
    ];
    // `List.sort` не стабилен: индекс прихода разрешает равенство и
    // отсутствие `requestedAt`.
    final order = [
      for (final (index, approval) in pending.indexed) (index, approval),
    ];
    order.sort((a, b) {
      final aTime = a.$2.requestedAt;
      final bTime = b.$2.requestedAt;
      final byTime = aTime == null || bTime == null
          ? 0
          : aTime.compareTo(bTime);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
    result.addAll([for (final entry in order) entry.$2]);
  }
  return result;
}

final class _Draft {
  const _Draft(this.item, this.call, this.path, this.depth);

  final ToolCallItem item;
  final SubagentCallView call;
  final List<String> path;
  final int depth;
}
